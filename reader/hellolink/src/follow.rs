//! `watch`: follows the row and prints one line for each thing that is new, as `follow` in
//! tools/hellolink_strip.py. What it does to the world (the clock, sleeps, the capture tool,
//! the look, the stream, `screencapture`, the output) goes through a `World`, so that the
//! tests can give their own.

use crate::bitmap::Bitmap;
use crate::capture::{
    self, Colour, Found, NO_GAME, ONE_FRAME_WAIT, STREAM_PAUSES, Screencapture, Stream, Unrun,
    capture_tool, interrupted,
};
use crate::record::Recorder;
use crate::rows::dumps;
use crate::slots;
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
    /// `--display`: the displays only, not the game's window (as before 23 Nov 2026).
    pub display: bool,
    /// Captures a second asked of the stream.
    pub fps: i64,
    /// A built strip_capture, instead of building tools/strip_capture.swift.
    pub capture: Option<String>,
    /// Keep the row's place in this file and try it first at the next start (a place of the source
    /// searched first: the game's window, or with `--display` a display).
    pub remember: Option<PathBuf>,
    /// Append a record of every capture to this file (docs/STRIP.md, section 10).
    pub record: Option<PathBuf>,
    /// The game's AddOns folder: lets the reader ask the strip to fall back (the slots).
    pub addons: Option<PathBuf>,
    /// Also serve the events to local programs on this port (0: no API, as Python).
    pub serve: Option<u16>,
    /// Format 2: keep the names of object 25 in this file, and give them in /state.
    pub names: Option<PathBuf>,
    /// The capture stream's colour space (`--colour`): sRGB unless asked.
    pub colour: Colour,
    /// `-h` or `--help` was given: print WATCH_HELP, do nothing else.
    pub help: bool,
}

impl Args {
    /// Whether the search reads the game's window first: in sRGB, unless `--display`.
    pub fn window(&self) -> bool {
        self.colour == Colour::Srgb && !self.display
    }
}

/// `hellolink watch --help`.
pub const WATCH_HELP: &str = "\
usage: hellolink watch [-h] [--json] [--fps FPS] [--addons ADDONS] [--serve PORT]
                       [--capture CAPTURE] [--remember FILE] [--record FILE] [--names FILE]
                       [--colour {srgb,display}] [--display]

Follows the row on screen and prints one line for each thing that is new, as
tools/hellolink_strip.py watch does. Stops at Ctrl-C. Takes no picture while the game is
not running (it says `waiting`, \"the game is not running\").

options:
  -h, --help         show this help message and exit
  --json             every event as a JSON line
  --fps FPS          captures a second asked of the stream (default 60)
  --addons ADDONS    the game's AddOns folder: lets the reader ask the strip to fall back
  --serve PORT       also serve the events to local programs:
                     http://127.0.0.1:PORT/state and /events
  --capture CAPTURE  a built strip_capture, instead of building tools/strip_capture.swift
  --remember FILE    keep the row's place in FILE and try it first at the next start
                     (a place of the source searched first)
  --record FILE      append a record of every capture to FILE, for measurement offline; it
                     holds the character's state: keep it out of the repository
  --names FILE       strip format 2: keep the names the strip sends (object 25) in FILE,
                     and give them in /state as \"names\" (with --serve)
  --colour {srgb,display}
                     the capture stream's colour space (default srgb); display: the
                     display's own, for the hour of 9 bits (docs/specs/232.md, part C)
  --display          capture the displays only, not the game's window (the default reads the
                     game's window first, so that another window over the game does not
                     hide the row; the owner, 23 Nov 2026)
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
            "--display" => {
                out.display = true;
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
            "--names" => out.names = Some(value.into()),
            "--colour" => {
                out.colour = match value.as_str() {
                    "srgb" => Colour::Srgb,
                    "display" => Colour::Display,
                    _ => {
                        return Err(format!(
                            "watch: argument --colour: invalid choice: {value:?} (choose from 'srgb', 'display')"
                        ));
                    }
                }
            }
            "--addons" => out.addons = Some(value.into()),
            "--serve" => {
                out.serve = Some(value.parse().map_err(|_| {
                    format!("watch: argument --serve: invalid int value: {value:?}")
                })?)
            }
            _ => return Err(format!("watch: unrecognized argument: {arg}")),
        }
    }
    if out.names.is_some() && out.serve.is_none_or(|p| p == 0) {
        return Err(
            "watch: argument --names: needs --serve PORT (the names are kept by the local API)"
                .into(),
        );
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
    /// Gets every event (the local HTTP API of `--serve`).
    pub tell: Box<dyn FnMut(&Value)>,
    /// A pipe's reader thread was left (capture::reader_left): a failure then ends `watch`.
    pub reader_left: fn() -> bool,
    /// Whether the game's process runs (#348): while it does not, no picture of any display or
    /// window is taken. Err: it could not be checked, which counts as not running.
    pub game: Box<dyn FnMut() -> Result<bool, String>>,
}

impl World {
    /// The real one: the capture processes (in `colour`), the clock, stdout and stderr.
    pub fn real(colour: Colour, window: bool) -> World {
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
            locate: {
                // searches in a row whose game window showed no row (capture::window_first)
                let mut blank = 0;
                Box::new(move |tool, note| {
                    let first = capture::window_first(window, blank);
                    let mut game = || capture::game_runs() == Ok(true);
                    let got = capture::locate_in(tool, colour, first, &mut game, note);
                    blank = capture::next_blank(blank, &got);
                    got.map_err(|e| match interrupted() {
                        true => Halt::Stop,
                        false => Halt::Failed(e),
                    })
                })
            },
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
            reader_left: capture::reader_left,
            tell: Box::new(|_| {}),
            game: Box::new(capture::game_runs),
        }
    }
}

/// Seconds between two looks at the game's process: while it is not running, and while a stream
/// runs (a stream is left within this time of the game's end).
const GAME_PAUSE: f64 = 2.0;

const KEYS: [&str; 5] = ["display", "left", "top", "width", "lines"];

/// The place of the row at the last run, kept in the file of --remember: the display (-1: the
/// game's window) and the rectangle, five whole numbers and nothing else. None for anything else.
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
    // -1: the game's window (since 23 Nov 2026)
    let ok = (display == crate::capture::GAME_WINDOW_INDEX || (0..64).contains(&display))
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

    /// None while the game runs; else why no picture may be taken (#348).
    fn no_game(&mut self) -> Option<String> {
        match (self.world.game)() {
            Ok(true) => None,
            Ok(false) => Some(NO_GAME.into()),
            Err(e) => Some(format!("{NO_GAME} (its process could not be checked: {e})")),
        }
    }

    /// While the game is not running: `waiting` with why, and a pause; true when it waited. The
    /// owner, 24 Nov 2026: "if game is not on don't bother to read the screen. it's privacy issue".
    fn waited_for_game(&mut self) -> Result<bool, Halt> {
        let Some(why) = self.no_game() else {
            return Ok(false);
        };
        let now = self.now();
        let events = self.watcher.idle(now);
        self.no_row(&why, events, now)?;
        (self.world.sleep)(GAME_PAUSE)?;
        Ok(true)
    }

    /// Says the events; true when one asks for a new search.
    fn handle(&mut self, events: Vec<Event>) -> Result<bool, Halt> {
        let mut again = false;
        for event in &events {
            (self.world.tell)(event);
            if event["kind"] == "ask"
                && let Some(addons) = &self.args.addons
            {
                let session = event["session"].as_i64().unwrap_or(0);
                let bits = event["bits"].as_u64().map_or(3, |b| b as u8);
                // keeps the text and its seq
                // Ctrl-C while the lock is waited for is the end, not a failure
                slots::write(addons, None, Some((session, bits)), None).map_err(|e| {
                    match interrupted() {
                        true => Halt::Stop,
                        false => Halt::Fatal(e),
                    }
                })?;
                self.note(&format!(
                    "asked the strip of session {session} to fall back to {bits} bits a square"
                ))?;
            }
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
            let waiting = json!({"kind": "waiting", "why": why});
            self.say(&waiting)?;
            (self.world.tell)(&waiting);
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
            if self.waited_for_game()? {
                continue;
            }
            let frame = match self.noting(|world, note| (world.screencapture)(note))? {
                Ok(frame) => frame,
                // a turn that did not end within its limit: said, and counted as no image
                Err(Halt::Failed(why)) if (self.world.reader_left)() => {
                    return Err(Halt::Fatal(why));
                }
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
            // no picture with no game: a remembered place waits too (#348)
            if self.waited_for_game()? {
                continue;
            }
            let rectangle = match place.take() {
                Some(mut rectangle) => {
                    *recalled = true;
                    // a place kept before the lanes for a row of 1-pixel squares is 3 lines high (the
                    // only height that changed): that row may have 4 lanes, so 6 lines (review of #299)
                    if rectangle[4] == 3 {
                        rectangle[4] = 6;
                    }
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
                    // the game may have ended during the search: no stream then (review of #349)
                    if self.waited_for_game()? {
                        continue;
                    }
                    self.waiting.0 = None;
                    // the game's window was looked at first and showed no row: say where it is
                    // read from instead (review of #316)
                    if display != crate::capture::GAME_WINDOW_INDEX && self.args.window() {
                        self.note(&format!(
                            "the row is read from display {display}, not from the game's window"
                        ))?;
                    }
                    let (left, upper) = ((x0 as i64 - 2).max(0), (top - 1).max(0));
                    let rectangle = [
                        display,
                        left,
                        upper,
                        width - left,
                        // a row of 1-pixel squares may have 4 lanes (docs/specs/232.md, part C)
                        (side + 0.999) as i64 + if side < 1.5 { 5 } else { 2 },
                    ];
                    if let Some(path) = &self.args.remember {
                        self.keep(path, rectangle)?;
                    }
                    rectangle
                }
            };
            self.watcher.hint = None; // the place is given in the new rectangle's own pixels
            let [display, left, upper, width, lines] = rectangle;
            let numbers = [display, left, upper, width, lines, self.args.fps];
            let command = self.args.colour.stream(tool, &numbers);
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
        let mut checked = began;
        for item in stream.by_ref() {
            let frame = item?;
            let now = self.now();
            // the game's process every GAME_PAUSE s: the stream is left when the game has ended (#348)
            if now - checked >= GAME_PAUSE {
                checked = now;
                if self.no_game().is_some() {
                    return Ok(()); // the search that follows waits for the game
                }
            }
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
        // A remembered place of the source the search reads first, else none: with the game's
        // window first, a display's place (kept when the window showed no row) is not taken at the
        // start, so the start looks at the window again (seen 23 Nov 2026: the first start after
        // the install streamed the remembered display); with `--display` or in the display's
        // colour space, a window's place is not taken (review of #316).
        let window = self.args.window();
        let mut place = self
            .args
            .remember
            .as_deref()
            .and_then(recall)
            .filter(|p| (p[0] == crate::capture::GAME_WINDOW_INDEX) == window);
        let mut recalled = false; // the stream that runs is on a remembered place
        loop {
            let failure = match self.streams(tool, &mut place, &mut recalled) {
                // a reader thread was left: no new try, so no more are (World::reader_left)
                Err(Halt::Failed(e)) if (self.world.reader_left)() => return Err(Halt::Fatal(e)),
                Err(Halt::Failed(e)) => e,
                Err(halt) => return Err(halt),
            };
            if recalled {
                // the remembered place may be of a display that is gone: look first
                recalled = false;
                // the displays only with --display; else the game's window first (review of #317)
                let looking = match self.args.window() {
                    true => "looking for the row again, in the game's window first",
                    false => "looking at the displays",
                };
                self.note(&format!(
                    "the remembered place gave no stream ({failure}): {looking}"
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
            // the display's colour space is the stream's alone: no screenshots in its place, so a
            // record that says `display` holds only the stream's captures (review of #292)
            Err(why) if self.args.colour == Colour::Display => Err(Halt::Fatal(format!(
                "--colour display needs the capture stream, which cannot run: {why}"
            ))),
            Err(why) => self.by_screencapture(&why),
        }
    }
}

/// `watch` itself. It returns when the world stops it, or with an error when the output or
/// the record cannot be written.
pub fn follow(args: &Args, world: &mut World) -> Result<(), String> {
    if !(1..=120).contains(&args.fps) {
        return Err("--fps must be 1 to 120".into());
    }
    let record = match &args.record {
        // closed with the process; written a line at a time
        Some(path) => Some(
            Recorder::new(path, None, args.colour)
                .map_err(|e| format!("--record {}: {e}", path.display()))?,
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
