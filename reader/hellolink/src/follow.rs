//! `watch`: follows the row and prints one line for each thing that is new, as `follow` in
//! tools/hellolink_strip.py. What it does to the world (the clock, sleeps, the capture tool,
//! the look, the stream, `screencapture`, the output) goes through a `World`, so that the
//! tests can give their own.

use crate::bitmap::Bitmap;
use crate::capture::{
    self, Found, ONE_FRAME_WAIT, STREAM_PAUSES, Screencapture, Stream, Unrun, capture_tool,
    interrupted,
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
use std::sync::mpsc;
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
    /// `-h` or `--help` was given: print WATCH_HELP, do nothing else.
    pub help: bool,
}

/// `hellolink watch --help`.
pub const WATCH_HELP: &str = "\
usage: hellolink watch [-h] [--json] [--fps FPS] [--capture CAPTURE] [--remember FILE]
                       [--record FILE]

Follows the row on screen and prints one line for each thing that is new, as
tools/hellolink_strip.py watch does. Stops at Ctrl-C.

options:
  -h, --help         show this help message and exit
  --json             every event as a JSON line
  --fps FPS          captures a second asked of the stream (default 60)
  --capture CAPTURE  a built strip_capture, instead of building tools/strip_capture.swift
  --remember FILE    keep the row's place in FILE and try it first at the next start
  --record FILE      append a record of every capture to FILE, for measurement offline; it
                     holds the character's state: keep it out of the repository
  --addons, --serve  not yet in the Rust reader (step 2c of #195)
";

/// The arguments after `watch`: `--name value` or `--name=value`, `--json`, and `-h` or
/// `--help` (then `help` is set and nothing else is read). As argparse, a value that looks
/// like an option (it starts with "-" and is no number) is no value: the option is refused,
/// before anything is done.
pub fn parse_watch(args: &[String]) -> Result<Args, String> {
    let mut out = Args {
        fps: 60,
        ..Args::default()
    };
    let mut it = args.iter().peekable();
    while let Some(arg) = it.next() {
        match arg.as_str() {
            "-h" | "--help" => {
                out.help = true;
                return Ok(out);
            }
            "--json" => {
                out.json = true;
                continue;
            }
            _ => {}
        }
        let (name, value) = match arg.split_once('=') {
            Some((name, value)) => (name, value.to_string()),
            None => {
                let given = it.next_if(|v| !v.starts_with('-') || v.parse::<f64>().is_ok());
                let value = given.ok_or(format!("watch: argument {arg}: expected one argument"))?;
                (arg.as_str(), value.clone())
            }
        };
        match name {
            "--fps" => {
                out.fps = value
                    .parse()
                    .map_err(|_| format!("watch: argument --fps: invalid int value: {value:?}"))?
            }
            "--capture" => out.capture = Some(value),
            "--remember" => out.remember = Some(value.into()),
            "--record" => out.record = Some(value.into()),
            "--addons" => out.addons = Some(value),
            "--serve" => out.serve = Some(value),
            _ => return Err(format!("watch: unrecognized argument: {arg}")),
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
/// A stream: frames, None for an idle turn; `close` leaves it.
pub trait Capture: Iterator<Item = Result<Option<Bitmap>, Halt>> {
    /// Leaves the stream: Err(Halt::Failed) when its capture failed by itself (not by being
    /// told to stop), with the capture's reason. Ok when the stream had already ended.
    fn close(self: Box<Self>) -> Result<(), Halt>;
}

/// What a stream gives.
pub type Frames = Box<dyn Capture>;

/// Frames that no process gives (a stream that could not start, a test's): closing them is
/// nothing.
pub struct NoProcess<I>(pub I);

impl<I: Iterator<Item = Result<Option<Bitmap>, Halt>>> Iterator for NoProcess<I> {
    type Item = I::Item;
    fn next(&mut self) -> Option<I::Item> {
        self.0.next()
    }
}

impl<I: Iterator<Item = Result<Option<Bitmap>, Halt>>> Capture for NoProcess<I> {
    fn close(self: Box<Self>) -> Result<(), Halt> {
        Ok(())
    }
}

/// A capture process's stream. Ctrl-C ends it at the next frame or idle turn.
struct Live(Stream);

impl Iterator for Live {
    type Item = Result<Option<Bitmap>, Halt>;
    fn next(&mut self) -> Option<Self::Item> {
        if interrupted() {
            return Some(Err(Halt::Stop));
        }
        self.0.next().map(|item| item.map_err(Halt::Failed))
    }
}

impl Capture for Live {
    fn close(self: Box<Self>) -> Result<(), Halt> {
        match self.0.close() {
            Some(ended) if ended.code != 0 => Err(Halt::Failed(if ended.error.is_empty() {
                format!("exit {}", ended.code)
            } else {
                ended.error
            })),
            _ => Ok(()),
        }
    }
}
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
                // a tenth of a second at a time: Ctrl-C ends the sleep
                let end = Instant::now() + Duration::from_secs_f64(s);
                while !interrupted() {
                    let left = end.saturating_duration_since(Instant::now());
                    if left.is_zero() {
                        return Ok(());
                    }
                    std::thread::sleep(left.min(Duration::from_millis(100)));
                }
                Err(Halt::Stop)
            }),
            capture_tool: Box::new(capture_tool),
            locate: Box::new(|tool, note| {
                capture::locate(tool, note).map_err(|e| match interrupted() {
                    true => Halt::Stop,
                    false => Halt::Failed(e),
                })
            }),
            stream: Box::new(|command, idle| match Stream::start(command, idle) {
                Ok(stream) => Box::new(Live(stream)),
                Err(e) => Box::new(NoProcess(std::iter::once(Err(Halt::Failed(e))))),
            }),
            screencapture: Box::new(move |note| {
                if interrupted() {
                    return Err(Halt::Stop); // no screencapture is started after Ctrl-C
                }
                fallback.turn(note).map_err(|e| match e {
                    Unrun::Interrupted => Halt::Stop,
                    _ if interrupted() => Halt::Stop,
                    Unrun::Late => {
                        Halt::Failed(format!("screencapture gave no image in {ONE_FRAME_WAIT} s"))
                    }
                    Unrun::Start(e) => Halt::Fatal(format!("screencapture: {e}")),
                    Unrun::Bad(e) => Halt::Fatal(e),
                })
            }),
            out: Box::new(Outlet::new(io::stdout())),
            err: Box::new(Outlet::new(io::stderr())),
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

/// A write to the output that failed: at Ctrl-C (a reader of the output that does not read
/// keeps a write waiting), the end of the watch; else a fatal error.
fn unwritten(e: io::Error) -> Halt {
    if interrupted() { Halt::Stop } else { fatal(e) }
}

/// Lines of output waiting for the writer thread, at most.
const OUTLET_LINES: usize = 256;

/// stdout or stderr through a thread of its own: a reader of the output that does not read
/// fills the pipe, and the thread waits, not `watch`. A write waits for room in the queue a
/// tenth of a second at a time, and gives up at Ctrl-C. When it is dropped, the thread gets
/// STOP_WAIT to write what is queued; then it is left (it ends with the process).
pub struct Outlet {
    tx: Option<mpsc::SyncSender<Vec<u8>>>,
    done: mpsc::Receiver<()>,
}

impl Outlet {
    pub fn new(mut to: impl Write + Send + 'static) -> Outlet {
        let (tx, rx) = mpsc::sync_channel::<Vec<u8>>(OUTLET_LINES);
        let (done_tx, done) = mpsc::channel::<()>();
        std::thread::spawn(move || {
            let _done = done_tx;
            for chunk in rx {
                if to.write_all(&chunk).and_then(|_| to.flush()).is_err() {
                    return; // the reader of the output left: the next write says so
                }
            }
        });
        Outlet { tx: Some(tx), done }
    }
}

impl Write for Outlet {
    fn write(&mut self, data: &[u8]) -> io::Result<usize> {
        let Some(tx) = &self.tx else {
            return Err(io::ErrorKind::BrokenPipe.into());
        };
        let mut chunk = data.to_vec();
        loop {
            match tx.try_send(chunk) {
                Ok(()) => return Ok(data.len()),
                Err(mpsc::TrySendError::Disconnected(_)) => {
                    return Err(io::ErrorKind::BrokenPipe.into());
                }
                Err(mpsc::TrySendError::Full(back)) => {
                    if interrupted() {
                        // not ErrorKind::Interrupted: write_all would try again at once
                        return Err(io::Error::other("Ctrl-C"));
                    }
                    chunk = back;
                    std::thread::sleep(Duration::from_millis(10));
                }
            }
        }
    }

    fn flush(&mut self) -> io::Result<()> {
        Ok(()) // the thread flushes after each write
    }
}

impl Drop for Outlet {
    fn drop(&mut self) {
        self.tx = None;
        let _ = self
            .done
            .recv_timeout(Duration::from_secs_f64(capture::STOP_WAIT));
    }
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
        writeln!(self.world.out, "{}", dumps(event)).map_err(unwritten)?;
        self.world.out.flush().map_err(unwritten)
    }

    fn note(&mut self, text: &str) -> Result<(), Halt> {
        writeln!(self.world.err, "{text}").map_err(unwritten)?;
        self.world.err.flush().map_err(unwritten)
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
            writeln!(self.world.out, "{line}").map_err(unwritten)?;
            self.world.out.flush().map_err(unwritten)?;
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
            let frame = match self.noting(|world, note| (world.screencapture)(note))? {
                Ok(frame) => frame,
                // a turn that did not end within its limit: said, and counted as no image
                Err(Halt::Failed(why)) => {
                    self.note(&why)?;
                    None
                }
                Err(halt) => return Err(halt),
            };
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
            let read = self.read_stream(&mut stream);
            // Left for a new search, at the limit or at Ctrl-C: the capture is stopped. When it
            // had failed by itself, that is a failure of the stream too, with its reason.
            match (read, stream.close()) {
                (Err(Halt::Failed(why)), Err(Halt::Failed(capture))) => {
                    return Err(Halt::Failed(format!("{why}; {capture}")));
                }
                (Err(halt), _) | (Ok(()), Err(halt)) => return Err(halt),
                (Ok(()), Ok(())) => {}
            }
            (self.world.sleep)(0.2)?; // a row that is gone is not searched for in a tight loop
        }
    }

    /// Follows one stream until it ends or asks for a new search (Ok), or fails.
    fn read_stream(&mut self, stream: &mut Frames) -> Result<(), Halt> {
        let (began, mut answered) = (self.now(), false);
        for item in stream.by_ref() {
            let frame = item?;
            let now = self.now();
            if !answered {
                // Before its first frame a stream's silence is a slow start, not "nothing
                // new": under load the first frame took 4.5 to 10 s (#103). The limit holds
                // for a frame that comes after it too (#38).
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
                return Ok(()); // look for the row again
            }
        }
        Ok(())
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
            // Ctrl-C while the tool was built: the end, not the fall-back
            Err(_) if interrupted() => Err(Halt::Stop),
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
