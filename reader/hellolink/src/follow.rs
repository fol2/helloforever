//! `watch`: follows the row and prints one line for each thing that is new, as `follow` in
//! tools/hellolink_strip.py. What it does to the world (the clock, sleeps, the capture tool,
//! the look, the stream, `screencapture`, the output) goes through a `World`, so that the
//! tests can give their own.

use crate::bitmap::Bitmap;
use crate::capture::{
    self, Found, ONE_FRAME_WAIT, STREAM_PAUSES, Screencapture, Stream, capture_tool,
};
use crate::record::Recorder;
use crate::rows::dumps;
use crate::strip1::{GROUPS, LEVEL_NAMES, Row, read_row};
use crate::watch::{Event, Watcher};
use serde_json::{Value, json};
use std::convert::Infallible;
use std::fs;
use std::io::{self, Write};
use std::path::{Path, PathBuf};
use std::time::{Duration, Instant};

/// The options of `watch`, as `hellolink_strip.py watch` takes them.
#[derive(Debug, Default)]
pub struct Args {
    /// Every event as a JSON line.
    pub json: bool,
    /// Captures a second asked of the stream.
    pub fps: i64,
    /// A built strip_capture, instead of building tools/strip_capture.swift.
    pub capture: Option<String>,
    /// Keep the row's place in this file and try it first at the next start.
    pub remember: Option<PathBuf>,
    /// Append a record of every capture to this file (docs/STRIP.md, section 10).
    pub record: Option<PathBuf>,
    /// Step 2c: the game's AddOns folder, for the request to fall back.
    pub addons: Option<String>,
    /// Step 2c: the local HTTP API's port.
    pub serve: Option<String>,
}

/// The arguments after `watch`: `--name value` or `--name=value`, and `--json`.
pub fn parse_watch(args: &[String]) -> Result<Args, String> {
    let mut out = Args {
        fps: 60,
        ..Args::default()
    };
    let mut it = args.iter();
    while let Some(arg) = it.next() {
        if arg == "--json" {
            out.json = true;
            continue;
        }
        let (name, value) = match arg.split_once('=') {
            Some((name, value)) => (name, value.to_string()),
            None => (
                arg.as_str(),
                it.next().ok_or(format!("{arg} needs a value"))?.clone(),
            ),
        };
        match name {
            "--fps" => {
                out.fps = value
                    .parse()
                    .map_err(|_| format!("--fps: not a whole number: {value}"))?
            }
            "--capture" => out.capture = Some(value),
            "--remember" => out.remember = Some(value.into()),
            "--record" => out.record = Some(value.into()),
            "--addons" => out.addons = Some(value),
            "--serve" => out.serve = Some(value),
            _ => return Err(format!("watch: unknown argument {arg}")),
        }
    }
    Ok(out)
}

/// What ends a turn of the reader early.
#[derive(Debug)]
pub enum Halt {
    /// The capture process failed (Python's CaptureFailed): the stream is tried again.
    Failed(String),
    /// The world ends the watch (a test's end).
    Stop,
    /// The output or the record cannot be written: the watch ends with this error.
    Fatal(String),
}

/// A capture's row, for the record.
pub type Note<'a> = &'a mut dyn FnMut(Option<&Row>);
/// What a stream gives: frames, None for an idle turn.
pub type Frames = Box<dyn Iterator<Item = Result<Option<Bitmap>, Halt>>>;
pub type ToolFn = Box<dyn FnMut(Option<&str>) -> Result<PathBuf, String>>;
pub type LocateFn = Box<dyn FnMut(&Path, Note) -> Result<Result<Found, String>, Halt>>;
pub type StreamFn = Box<dyn FnMut(&[String], f64) -> Frames>;
pub type TurnFn = Box<dyn FnMut(Note) -> Result<Option<Bitmap>, Halt>>;

/// Everything `follow` does outside itself.
pub struct World {
    /// Seconds, monotonic.
    pub now: Box<dyn FnMut() -> f64>,
    pub sleep: Box<dyn FnMut(f64) -> Result<(), Halt>>,
    pub capture_tool: ToolFn,
    /// Looks at every display: Ok(Err(why)) when none shows the row.
    pub locate: LocateFn,
    /// A stream of the command's frames, with an idle turn every so many seconds.
    pub stream: StreamFn,
    /// One turn of the slow fall-back.
    pub screencapture: TurnFn,
    pub out: Box<dyn Write>,
    pub err: Box<dyn Write>,
}

impl World {
    /// The real one: the capture processes, the clock, stdout and stderr.
    pub fn real() -> World {
        let start = Instant::now();
        let mut fallback = Screencapture::real();
        World {
            now: Box::new(move || start.elapsed().as_secs_f64()),
            sleep: Box::new(|s| {
                std::thread::sleep(Duration::from_secs_f64(s));
                Ok(())
            }),
            capture_tool: Box::new(capture_tool),
            locate: Box::new(|tool, note| capture::locate(tool, note).map_err(Halt::Failed)),
            stream: Box::new(|command, idle| match Stream::start(command, idle) {
                Ok(stream) => Box::new(stream.map(|item| item.map_err(Halt::Failed))),
                Err(e) => Box::new(std::iter::once(Err(Halt::Failed(e)))),
            }),
            screencapture: Box::new(move |note| fallback.turn(note).map_err(Halt::Fatal)),
            out: Box::new(io::stdout()),
            err: Box::new(io::stderr()),
        }
    }
}

const KEYS: [&str; 5] = ["display", "left", "top", "width", "lines"];

/// The place of the row at the last run, kept in the file of --remember: the display and the
/// rectangle, five whole numbers and nothing else. None for anything else.
fn recall(path: &Path) -> Option<[i64; 5]> {
    let kept: Value = serde_json::from_str(&fs::read_to_string(path).ok()?).ok()?;
    let kept = kept.as_object()?;
    if kept.len() != KEYS.len() || !KEYS.iter().all(|k| kept.contains_key(*k)) {
        return None;
    }
    let mut place = [0; 5];
    for (v, k) in place.iter_mut().zip(KEYS) {
        // an int in Python's eyes: no float, no bool
        *v = kept[k].as_i64().filter(|_| !kept[k].is_f64())?;
    }
    let [display, left, top, width, lines] = place;
    let ok = (0..64).contains(&display)
        && (0..100000).contains(&left)
        && (0..100000).contains(&top)
        && (1..100000).contains(&width)
        && (1..100000).contains(&lines);
    ok.then_some(place)
}

fn fatal(e: io::Error) -> Halt {
    Halt::Fatal(e.to_string())
}

struct Reader<'a> {
    args: &'a Args,
    world: &'a mut World,
    watcher: Watcher,
    record: Option<Recorder>,
    /// The reason last said in `waiting`, and when.
    waiting: (Option<String>, f64),
    /// Why the stream was last taken for failed, as noted.
    said: Option<String>,
    /// Failures of the stream in a row.
    tries: usize,
    /// The note about replayd was given (once a run, #113).
    hinted: bool,
}

impl Reader<'_> {
    fn now(&mut self) -> f64 {
        (self.world.now)()
    }

    fn say(&mut self, event: &Value) -> Result<(), Halt> {
        writeln!(self.world.out, "{}", dumps(event)).map_err(fatal)?;
        self.world.out.flush().map_err(fatal)
    }

    fn note(&mut self, text: &str) -> Result<(), Halt> {
        writeln!(self.world.err, "{text}").map_err(fatal)?;
        self.world.err.flush().map_err(fatal)
    }

    /// Says the events; true when one asks for a new search.
    fn handle(&mut self, events: Vec<Event>) -> Result<bool, Halt> {
        let mut again = false;
        for event in &events {
            again |= event["kind"] == "relocate";
            if self.args.json || event["kind"] != "state" {
                self.say(event)?;
                continue;
            }
            let shown = |v: &Value| match v {
                Value::Null => "-".to_string(),
                Value::String(s) => s.clone(),
                v => v.to_string(),
            };
            let levels: Vec<String> = LEVEL_NAMES
                .iter()
                .map(|k| format!("{k}={}", shown(&event["levels"][k])))
                .collect();
            let unknown: Vec<&str> = GROUPS
                .iter()
                .map(|(name, _)| *name)
                .filter(|name| event["fast"].get(name).is_some_and(Value::is_null))
                .collect();
            let unknown = if unknown.is_empty() {
                String::new()
            } else {
                format!("  unknown: {}", unknown.join(" "))
            };
            let line = format!(
                "seq {}  depth {}  {}{unknown}",
                event["seq"],
                event["depth"],
                levels.join(" ")
            );
            writeln!(self.world.out, "{line}").map_err(fatal)?;
            self.world.out.flush().map_err(fatal)?;
        }
        Ok(again)
    }

    /// `waiting`, again once a minute, is the whole story while no display shows the row.
    /// `relocate` is what a row that stands still gives; with no row the search runs anyway,
    /// and the line was read as a row that was found (#52).
    fn no_row(&mut self, why: &str, events: Vec<Event>, now: f64) -> Result<(), Halt> {
        if self.waiting.0.as_deref() != Some(why) || now - self.waiting.1 >= 60.0 {
            self.say(&json!({"kind": "waiting", "why": why}))?;
            self.waiting = (Some(why.to_string()), now);
        }
        let events = events
            .into_iter()
            .filter(|e| e["kind"] != "relocate")
            .collect();
        self.handle(events).map(|_| ())
    }

    /// The Watcher's events for a capture (None: an idle turn), noted in the record first.
    fn feed(&mut self, frame: Option<&Bitmap>, now: f64) -> Result<Vec<Event>, Halt> {
        let Some(bmp) = frame else {
            return Ok(self.watcher.idle(now));
        };
        let row = read_row(bmp, self.watcher.hint);
        if let Some(record) = &mut self.record {
            record.note(row.as_ref(), now).map_err(fatal)?;
        }
        Ok(self.watcher.feed_row(row, now))
    }

    /// The events of time alone, without `relocate`.
    fn idle_only(&mut self, now: f64) -> Vec<Event> {
        let events = self.watcher.idle(now);
        events
            .into_iter()
            .filter(|e| e["kind"] != "relocate")
            .collect()
    }

    /// A note for the record, from a look or the fall-back: the row and the time now.
    fn noting<T>(&mut self, act: impl FnOnce(&mut World, Note) -> T) -> Result<T, Halt> {
        let mut broken = None;
        let record = &mut self.record;
        let world = &mut *self.world;
        let mut now = std::mem::replace(&mut world.now, Box::new(|| 0.0));
        let done = act(world, &mut |row| {
            if let Some(record) = record.as_mut()
                && let Err(e) = record.note(row, now())
            {
                broken.get_or_insert(e);
            }
        });
        world.now = now;
        match broken {
            Some(e) => Err(fatal(e)),
            None => Ok(done),
        }
    }

    /// The slow fall-back, only when there is no capture tool at all (no stream can run).
    fn by_screencapture(&mut self, why: &str) -> Result<Infallible, Halt> {
        self.note(&format!(
            "no capture tool ({why}): one screencapture a frame, which is slow"
        ))?;
        self.watcher.hint = None;
        let mut first = true;
        loop {
            if !first {
                (self.world.sleep)(0.2)?;
            }
            first = false;
            let frame = self.noting(|world, note| (world.screencapture)(note))??;
            let now = self.now();
            let events = self.feed(frame.as_ref(), now)?;
            if frame.is_none() || !self.watcher.shown {
                self.no_row("no row on any display", events, now)?;
            } else {
                self.waiting.0 = None;
                self.handle(events)?;
            }
        }
    }

    /// The streams, one after the other, until one fails: Err(Halt::Failed) is why.
    fn streams(
        &mut self,
        tool: &Path,
        place: &mut Option<[i64; 5]>,
        recalled: &mut bool,
    ) -> Result<Infallible, Halt> {
        loop {
            let rectangle = match place.take() {
                Some(rectangle) => {
                    *recalled = true;
                    rectangle
                }
                None => {
                    *recalled = false;
                    let found = self.noting(|world, note| (world.locate)(tool, note))??;
                    let (display, width, (x0, top, side)) = match found {
                        Ok(found) => found,
                        Err(why) => {
                            let now = self.now();
                            let events = self.watcher.idle(now);
                            self.no_row(&why, events, now)?;
                            (self.world.sleep)(2.0)?;
                            continue;
                        }
                    };
                    self.waiting.0 = None;
                    let (left, upper) = ((x0 as i64 - 2).max(0), (top - 1).max(0));
                    let rectangle = [
                        display,
                        left,
                        upper,
                        width - left,
                        (side + 0.999) as i64 + 2,
                    ];
                    if let Some(path) = &self.args.remember {
                        self.keep(path, rectangle)?;
                    }
                    rectangle
                }
            };
            self.watcher.hint = None; // the place is given in the new rectangle's own pixels
            let command: Vec<String> = [tool.to_string_lossy().into_owned(), "stream".into()]
                .into_iter()
                .chain(rectangle.iter().map(|v| v.to_string()))
                .chain([self.args.fps.to_string()])
                .collect();
            let mut stream = (self.world.stream)(&command, 0.5);
            let (began, mut answered) = (self.now(), false);
            for item in stream.by_ref() {
                let frame = item?;
                let now = self.now();
                if !answered {
                    // Before its first frame a stream's silence is a slow start, not "nothing
                    // new": under load the first frame took 4.5 to 10 s (#103). The limit
                    // holds for a frame that comes after it too (#38).
                    if now - began >= ONE_FRAME_WAIT {
                        return Err(Halt::Failed(format!("no frame in {ONE_FRAME_WAIT} s")));
                    }
                    if frame.is_none() {
                        // what is old still goes stale; only the look again waits
                        let events = self.idle_only(now);
                        self.handle(events)?;
                        continue;
                    }
                }
                if frame.is_some() {
                    (answered, self.tries) = (true, 0); // the next failure starts short
                }
                let events = self.feed(frame.as_ref(), now)?;
                if self.handle(events)? {
                    break; // look for the row again
                }
            }
            drop(stream); // stops the process and its reader thread
            (self.world.sleep)(0.2)?; // a row that is gone is not searched for in a tight loop
        }
    }

    fn keep(&mut self, path: &Path, place: [i64; 5]) -> Result<(), Halt> {
        let text = format!(
            "{{{}}}",
            KEYS.iter()
                .zip(place)
                .map(|(k, v)| format!("\"{k}\": {v}"))
                .collect::<Vec<_>>()
                .join(", ")
        );
        let written = match path.parent() {
            Some(folder) if !folder.as_os_str().is_empty() => fs::create_dir_all(folder),
            _ => Ok(()),
        }
        .and_then(|_| fs::write(path, text));
        if let Err(e) = written {
            self.note(&format!(
                "the row's place was not written to {}: {e}",
                path.display()
            ))?;
        }
        Ok(())
    }

    /// Streaming only (owner, 15 Nov 2026: "i always wanted streaming not capturing"). A
    /// stream that failed is tried again after a pause that grows to 30 s; meanwhile the
    /// reader says `waiting` with the reason.
    fn streaming(&mut self, tool: &Path) -> Result<Infallible, Halt> {
        let mut place = self.args.remember.as_deref().and_then(recall);
        let mut recalled = false; // the stream that runs is on a remembered place
        loop {
            let failure = match self.streams(tool, &mut place, &mut recalled) {
                Err(Halt::Failed(e)) => e,
                Err(halt) => return Err(halt),
            };
            if recalled {
                // the remembered place may be of a display that is gone: look first
                recalled = false;
                self.note(&format!(
                    "the remembered place gave no stream ({failure}): looking at the displays"
                ))?;
                continue;
            }
            let pause = STREAM_PAUSES[self.tries.min(STREAM_PAUSES.len() - 1)];
            self.tries += 1;
            let why = format!("the capture stream does not answer ({failure})");
            if self.said.as_deref() != Some(&why) {
                self.note(&format!(
                    "{why}: it is tried again, after {pause} s at first, then at most each 30 s"
                ))?;
                self.said = Some(why.clone());
            }
            if self.tries >= 3 && !self.hinted {
                self.hinted = true; // once a run, also after a recovery (#113)
                self.note(
                    "the capture stream has failed 3 times in a row. If it goes on, restarting \
                     macOS's capture service may help: killall replayd (macOS starts it again \
                     at once). On 15 Nov 2026, after a restart, 5 of 6 first frames came in 1 \
                     to 2 s (before: 4 to 11 s) and 1 gave none; the cause of the slow starts \
                     is not known.",
                )?;
            }
            let now = self.now();
            let events = self.watcher.idle(now);
            self.no_row(&why, events, now)?;
            (self.world.sleep)(pause as f64)?;
        }
    }

    fn run(&mut self) -> Result<Infallible, Halt> {
        // Said at once, so that a program that follows the reader has an answer while the
        // row is looked for: the look takes seconds (#80).
        let now = self.now();
        self.no_row("looking for the row", vec![], now)?;
        match (self.world.capture_tool)(self.args.capture.as_deref()) {
            Ok(tool) => self.streaming(&tool),
            Err(why) => self.by_screencapture(&why),
        }
    }
}

/// `watch` itself. It returns when the world stops it, or with an error when the output or
/// the record cannot be written.
pub fn follow(args: &Args, world: &mut World) -> Result<(), String> {
    for (given, flag) in [(&args.serve, "--serve"), (&args.addons, "--addons")] {
        if given.is_some() {
            return Err(format!(
                "{flag}: not yet in the Rust reader (step 2c of #195)"
            ));
        }
    }
    if !(1..=120).contains(&args.fps) {
        return Err("--fps must be 1 to 120".into());
    }
    let record = match &args.record {
        // closed with the process; written a line at a time
        Some(path) => Some(
            Recorder::new(path, None).map_err(|e| format!("--record {}: {e}", path.display()))?,
        ),
        None => None,
    };
    let mut reader = Reader {
        args,
        world,
        watcher: Watcher::default(), // one for the whole run: it remembers a session
        record,
        waiting: (None, 0.0),
        said: None,
        tries: 0,
        hinted: false,
    };
    match reader.run() {
        Err(Halt::Stop) => Ok(()),
        Err(Halt::Fatal(e) | Halt::Failed(e)) => Err(e),
    }
}
