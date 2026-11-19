//! The processes around the capture, as tools/hellolink_strip.py runs them: the capture tool
//! (tools/strip_capture.swift, built into the user's cache folder), one frame of it, a stream
//! of frames, the look at every display for the row, and the slow fall-back with macOS
//! `screencapture`. A capture process is asked to stop (SIGTERM) before it is killed, so that
//! it can close its capture stream, and no wait on a process is without a limit (#38).

use crate::bitmap::{Bitmap, frames_from};
use crate::strip1::{Row, read_row};
use std::fs;
use std::io::Read;
use std::os::unix::process::ExitStatusExt;
use std::path::{Path, PathBuf};
use std::process::{Child, Command, ExitStatus, Stdio};
use std::sync::mpsc::{self, Receiver, RecvTimeoutError};
use std::thread;
use std::time::{Duration, Instant};

/// Seconds for a capture's first frame: 4.5 to 10 s seen under load (#103).
pub const ONE_FRAME_WAIT: f64 = 15.0;
/// Seconds before the stream is tried again, then 30 s each time.
pub const STREAM_PAUSES: [u64; 5] = [2, 4, 8, 16, 30];
/// Seconds a capture process gets to stop by itself.
pub const STOP_WAIT: f64 = 2.0;
/// How a process that was told to stop may end: by itself, SIGTERM, SIGKILL.
pub const STOPPED: [i32; 3] = [0, -15, -9];
/// Seconds `swiftc` gets to build the capture tool. Python waits without a limit (#38).
pub const BUILD_WAIT: f64 = 300.0;
/// The capture tool's source, in the checkout this reader was built from.
pub const CAPTURE_SOURCE: &str = concat!(
    env!("CARGO_MANIFEST_DIR"),
    "/../../tools/strip_capture.swift"
);

/// Seconds as Python's "%g" writes the limits above (15.0 is "15").
fn g(seconds: f64) -> String {
    format!("{seconds}")
}

/// An exit code as Python's returncode: a signal is its number, negative.
fn code_of(status: ExitStatus) -> i32 {
    status
        .code()
        .unwrap_or_else(|| -status.signal().unwrap_or(0))
}

/// Waits up to `seconds` for a process; None when it is still there.
fn wait_for(child: &mut Child, seconds: f64) -> Option<ExitStatus> {
    let end = Instant::now() + Duration::from_secs_f64(seconds);
    loop {
        if let Ok(Some(status)) = child.try_wait() {
            return Some(status);
        }
        if Instant::now() >= end {
            return None;
        }
        thread::sleep(Duration::from_millis(5));
    }
}

/// All a pipe gives, read in a thread of its own; the receiver gets it at the pipe's end.
fn drain(pipe: Option<impl Read + Send + 'static>) -> Receiver<Vec<u8>> {
    let (tx, rx) = mpsc::channel();
    if let Some(mut pipe) = pipe {
        thread::spawn(move || {
            let mut all = Vec::new();
            let _ = pipe.read_to_end(&mut all);
            let _ = tx.send(all);
        });
    }
    rx
}

/// Why a command run with a limit gave no result.
pub enum Unrun {
    /// It could not be started.
    Start(std::io::Error),
    /// It did not end within the limit, and was killed.
    Late,
}

/// Runs a command to its end, with a limit: (exit code, stdout, stderr). A command still
/// there at the limit is killed. What it wrote is read in threads, so a full pipe cannot
/// stop it; output still held open by a child of it after its end is given up after STOP_WAIT.
pub fn run_limited(command: &[String], seconds: f64) -> Result<(i32, String, String), Unrun> {
    let (program, args) = command.split_first().ok_or(Unrun::Late)?;
    let mut child = Command::new(program)
        .args(args)
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(Unrun::Start)?;
    let (out, err) = (drain(child.stdout.take()), drain(child.stderr.take()));
    let Some(status) = wait_for(&mut child, seconds) else {
        let _ = child.kill();
        let _ = child.wait(); // after SIGKILL: at once
        return Err(Unrun::Late);
    };
    let text = |rx: Receiver<Vec<u8>>| {
        let bytes = rx
            .recv_timeout(Duration::from_secs_f64(STOP_WAIT))
            .unwrap_or_default();
        String::from_utf8_lossy(&bytes).into_owned()
    };
    Ok((code_of(status), text(out), text(err)))
}

/// The built capture stream: the one given, or one built from the source into the user's
/// cache folder when it is missing or older than the source. Err is why there is none: the
/// caller then falls back to one `screencapture` a frame (docs/specs/29.md, section 8).
pub fn capture_tool(given: Option<&str>) -> Result<PathBuf, String> {
    if let Some(given) = given {
        let path = PathBuf::from(given);
        return if path.is_file() {
            Ok(path)
        } else {
            Err(format!("{given} is not a file"))
        };
    }
    let home = std::env::var_os("HOME")
        .ok_or("it could not be built: no home folder (HOME is not set)")?;
    let built = PathBuf::from(home).join("Library/Caches/HelloLink/strip_capture");
    let could_not = |e: std::io::Error| format!("it could not be built: {e}");
    let stale = match fs::metadata(&built) {
        Err(_) => true,
        Ok(m) => {
            m.modified().map_err(could_not)?
                < fs::metadata(CAPTURE_SOURCE)
                    .and_then(|s| s.modified())
                    .map_err(could_not)?
        }
    };
    if stale {
        if let Some(folder) = built.parent() {
            fs::create_dir_all(folder).map_err(could_not)?;
        }
        let command: Vec<String> = ["swiftc", "-O", "-swift-version", "5", CAPTURE_SOURCE, "-o"]
            .iter()
            .map(|s| s.to_string())
            .chain([built.to_string_lossy().into_owned()])
            .collect();
        match run_limited(&command, BUILD_WAIT) {
            Err(Unrun::Start(e)) => return Err(could_not(e)),
            Err(Unrun::Late) => {
                return Err(format!(
                    "it could not be built: swiftc took more than {} s",
                    g(BUILD_WAIT)
                ));
            }
            Ok((0, _, _)) => {}
            Ok((_, _, err)) => {
                let err: Vec<char> = err.trim().chars().collect();
                let tail: String = err[err.len().saturating_sub(300)..].iter().collect();
                return Err(format!("swiftc could not build it: {tail}"));
            }
        }
    }
    Ok(built)
}

/// Tells a capture process to stop: SIGTERM, then SIGKILL when it is still there after
/// STOP_WAIT. It is asked first so that it can close its capture stream; a process that is
/// killed cannot. SIGTERM is sent with kill(1): std sends only SIGKILL, and this crate has no
/// unsafe code.
pub fn stop(child: &mut Child) {
    if let Ok(None) = child.try_wait() {
        let term = ["kill".to_string(), "-TERM".into(), child.id().to_string()];
        let _ = run_limited(&term, STOP_WAIT);
    }
    if wait_for(child, STOP_WAIT).is_none() {
        let _ = child.kill();
    }
}

/// Waits for a capture process whose output is over, and returns (its error text, its exit
/// code). `told`: the caller is the one who stops it (it left early, or gave up), so an end
/// by SIGTERM or SIGKILL is no failure and comes back as 0. A process that ended its output
/// by itself gets STOP_WAIT to leave by itself, so its own exit code stands; one that then
/// stays is stopped, and that is a failure.
pub fn ended(child: &mut Child, told: bool) -> (String, i32) {
    let stuck = !told && wait_for(child, STOP_WAIT).is_none();
    if told || stuck {
        stop(child);
    }
    // ponytail: as in Python, stderr is read to its end; a child of the capture that keeps it
    // open would hold this. The capture tool starts none.
    let mut bytes = Vec::new();
    if let Some(mut err) = child.stderr.take() {
        let _ = err.read_to_end(&mut bytes);
    }
    let error = String::from_utf8_lossy(&bytes).trim().to_string();
    let code = child.wait().map_or(1, code_of); // stopped above: at once
    if stuck {
        let error = if error.is_empty() {
            "it did not leave after its output ended".to_string()
        } else {
            error
        };
        return (error, if code == 0 { 1 } else { code });
    }
    (
        error,
        if told && STOPPED.contains(&code) {
            0
        } else {
            code
        },
    )
}

fn spawn(command: &[String]) -> Result<Child, String> {
    let (program, args) = command.split_first().ok_or("no command")?;
    Command::new(program)
        .args(args)
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|e| format!("{program} could not be started: {e}"))
}

/// The first frame a capture command gives; None when it ended cleanly without one. The
/// process is always stopped. Err is the reason when the process failed, and when it gave no
/// frame in `wait` seconds (ONE_FRAME_WAIT; the tests give less): on an idle machine a stream
/// gives its first frame at once, under load in up to about 10 s (#103); longer silence means
/// the capture service is not answering, and the caller tries the stream again later.
pub fn one_frame(command: &[String], wait: f64) -> Result<Option<Bitmap>, String> {
    let mut shot = spawn(command)?;
    let (tx, rx) = mpsc::channel();
    let stdout = shot.stdout.take();
    // The read ends when the process does: it is stopped below whatever happens.
    thread::spawn(move || {
        let first = stdout.and_then(|pipe| frames_from(pipe).next());
        let _ = tx.send(first);
    });
    let got = rx.recv_timeout(Duration::from_secs_f64(wait));
    let late = got.is_err(); // also when a frame came after the limit: the limit holds
    let (frame, failed) = match got {
        Ok(Some(Ok(frame))) => (Some(frame), None),
        Ok(Some(Err(e))) => (None, Some(format!("bad output: {e}"))),
        _ => (None, None),
    };
    let took = frame.is_some();
    let (error, code) = ended(&mut shot, took || failed.is_some() || late);
    if let Some(failed) = failed {
        return Err(failed);
    }
    if !took && code != 0 {
        return Err(if error.is_empty() {
            format!("exit {code}")
        } else {
            error
        });
    }
    if late {
        return Err(format!("no frame in {} s", g(wait)));
    }
    Ok(frame)
}

/// Where a look found the row: the display, its width, and the row's grid (left edge, top,
/// square's side) in the display's pixels.
pub type Found = (i64, i64, (f64, i64, f64));

/// The displays the capture tool lists: index, width, height. Err when the tool fails or does
/// not list them in ONE_FRAME_WAIT (a silent capture service: the caller tries again later).
pub fn displays(tool: &Path) -> Result<Vec<(i64, i64, i64)>, String> {
    let command = [tool.to_string_lossy().into_owned(), "list".into()];
    let (code, out, err) = match run_limited(&command, ONE_FRAME_WAIT) {
        Ok(done) => done,
        Err(Unrun::Late) => {
            return Err(format!(
                "no list of the displays in {} s",
                g(ONE_FRAME_WAIT)
            ));
        }
        Err(Unrun::Start(e)) => {
            return Err(format!("{} could not be started: {e}", tool.display()));
        }
    };
    if code != 0 {
        let err = err.trim();
        return Err(if err.is_empty() {
            format!("exit {code}")
        } else {
            err.into()
        });
    }
    out.lines()
        .filter(|line| !line.trim().is_empty())
        .map(|line| {
            let v: Vec<i64> = line
                .split_whitespace()
                .map(str::parse)
                .collect::<Result<_, _>>()
                .map_err(|_| format!("not a display: {line}"))?;
            match v[..] {
                [index, width, height] => Ok((index, width, height)),
                _ => Err(format!("not a display: {line}")),
            }
        })
        .collect()
}

/// Looks at one frame of each display for the row: the top 64 lines first (the row is 2 to 4
/// pixels high and sits at the top by default), then the whole display. Ok(Err(why)) when no
/// display shows it; Err when a capture failed. `note` gets the row of each frame looked at
/// (a record of the play, #178). `one_frame` takes a capture command.
pub fn look(
    tool: &Path,
    displays: &[(i64, i64, i64)],
    one_frame: OneFrame,
    note: &mut dyn FnMut(Option<&Row>),
) -> Result<Result<Found, String>, String> {
    if displays.is_empty() {
        return Ok(Err("no display (are the displays asleep?)".into()));
    }
    for &(index, width, height) in displays {
        for lines in [64, height] {
            let command: Vec<String> = [tool.to_string_lossy().into_owned(), "stream".into()]
                .into_iter()
                .chain(
                    [index, 0, 0, width, lines, 30, 1]
                        .iter()
                        .map(|v| v.to_string()),
                )
                .collect();
            let Some(frame) = one_frame(&command)? else {
                continue;
            };
            let row = read_row(&frame, None);
            note(row.as_ref());
            if let Some(grid) = row.and_then(|r| r.grid) {
                return Ok(Ok((index, width, grid)));
            }
        }
    }
    Ok(Err("no row on any display".into()))
}

/// Takes a capture command and gives its first frame, as `one_frame`.
pub type OneFrame<'a> = &'a mut dyn FnMut(&[String]) -> Result<Option<Bitmap>, String>;

/// `displays`, then `look` with real captures of ONE_FRAME_WAIT.
pub fn locate(
    tool: &Path,
    note: &mut dyn FnMut(Option<&Row>),
) -> Result<Result<Found, String>, String> {
    let listed = displays(tool)?;
    look(
        tool,
        &listed,
        &mut |command| one_frame(command, ONE_FRAME_WAIT),
        note,
    )
}

enum Item {
    Frame(Bitmap),
    Bad(String),
    End,
}

/// Frames from a capture process, and None each time `idle` seconds pass without one (a
/// stream gives a frame only when its rectangle changed). A thread reads the pipe. It ends
/// (None) when the process ends cleanly; a process that fails, or output that is not frames,
/// is one Err with the reason, then the end. Dropping it early stops the process and its
/// reader thread.
pub struct Stream {
    child: Child,
    frames: Option<Receiver<Item>>,
    /// Disconnected when the reader thread has ended.
    pump: Receiver<()>,
    idle: Duration,
    over: bool,
}

impl Stream {
    pub fn start(command: &[String], idle: f64) -> Result<Stream, String> {
        let mut child = spawn(command)?;
        let stdout = child.stdout.take();
        let (tx, frames) = mpsc::sync_channel(8);
        let (done, pump) = mpsc::channel::<()>();
        thread::spawn(move || {
            let _done = done; // dropped when the thread ends
            let Some(stdout) = stdout else { return };
            // A send fails when the reader has left: the thread ends then.
            for frame in frames_from(stdout) {
                let item = match frame {
                    Ok(frame) => Item::Frame(frame),
                    Err(e) => Item::Bad(e),
                };
                let bad = matches!(item, Item::Bad(_));
                if tx.send(item).is_err() || bad {
                    return;
                }
            }
            let _ = tx.send(Item::End);
        });
        Ok(Stream {
            child,
            frames: Some(frames),
            pump,
            idle: Duration::from_secs_f64(idle),
            over: false,
        })
    }

    /// The process's id.
    pub fn pid(&self) -> u32 {
        self.child.id()
    }

    /// Stops the process (`clean`: its output ended by itself) and its reader thread:
    /// (error text, exit code, the thread ended within STOP_WAIT).
    fn finish(&mut self, clean: bool) -> (String, i32, bool) {
        self.over = true;
        self.frames = None; // a reader thread waiting to hand a frame on gives up
        let (error, code) = ended(&mut self.child, !clean);
        let gone = matches!(
            self.pump.recv_timeout(Duration::from_secs_f64(STOP_WAIT)),
            Err(RecvTimeoutError::Disconnected)
        );
        (error, code, gone)
    }

    /// Leaves the stream early: true when its reader thread ended within STOP_WAIT.
    pub fn close(mut self) -> bool {
        if self.over {
            return true;
        }
        self.finish(false).2
    }
}

impl Iterator for Stream {
    type Item = Result<Option<Bitmap>, String>;

    fn next(&mut self) -> Option<Self::Item> {
        if self.over {
            return None;
        }
        let item = match self.frames.as_ref()?.recv_timeout(self.idle) {
            Ok(item) => item,
            Err(RecvTimeoutError::Timeout) => return Some(Ok(None)),
            Err(RecvTimeoutError::Disconnected) => Item::End,
        };
        match item {
            Item::Frame(frame) => Some(Ok(Some(frame))),
            Item::Bad(e) => {
                self.finish(false);
                Some(Err(format!("bad output: {e}")))
            }
            Item::End => {
                let (error, code, _) = self.finish(true);
                match (code, error.is_empty()) {
                    (0, _) => None,
                    (_, true) => Some(Err(format!("exit {code}"))),
                    (_, false) => Some(Err(error)),
                }
            }
        }
    }
}

impl Drop for Stream {
    fn drop(&mut self) {
        if !self.over {
            self.finish(false);
        }
    }
}

/// A new empty folder in the temporary folder.
fn temp_folder() -> Result<PathBuf, String> {
    let base = std::env::temp_dir();
    let stamp = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map_or(0, |d| d.as_nanos());
    for n in 0..100 {
        let dir = base.join(format!("hellolink-{}-{stamp}-{n}", std::process::id()));
        if fs::create_dir(&dir).is_ok() {
            return Ok(dir);
        }
    }
    Err(format!("no temporary folder in {}", base.display()))
}

/// The fall-back when there is no capture stream: one image a turn, of the display that shows
/// the row. Until a display shows it, one `screencapture` takes every display and the first
/// image with the row is given (with no row anywhere, the first display's, so that the reader
/// counts one miss a turn); from then on only that display is captured, until the row leaves
/// it. Slow (a few a second at best), so a reader on it cannot follow a short `dwell`. No
/// screenshot outlives its turn.
pub struct Screencapture {
    /// The display that shows the row, counted from 1.
    at: Option<usize>,
    /// Runs the `screencapture` command given (the tests write the images themselves).
    shoot: Shoot,
}

/// Runs a `screencapture` command.
pub type Shoot = Box<dyn FnMut(&[String])>;

impl Screencapture {
    pub fn new(shoot: Shoot) -> Screencapture {
        Screencapture { at: None, shoot }
    }

    /// With macOS `screencapture`, given ONE_FRAME_WAIT a turn (Python waits without a limit).
    pub fn real() -> Screencapture {
        Screencapture::new(Box::new(|command| {
            let _ = run_limited(command, ONE_FRAME_WAIT);
        }))
    }

    /// One turn: the image given on, or None when no display gave one. `note` gets the row of
    /// each image that is not given on (a record of the play, #178).
    pub fn turn(&mut self, note: &mut dyn FnMut(Option<&Row>)) -> Result<Option<Bitmap>, String> {
        let tmp = temp_folder()?;
        let numbers: Vec<usize> = self.at.map_or((1..=4).collect(), |n| vec![n]);
        let shots: Vec<(usize, PathBuf)> = numbers
            .iter()
            .map(|n| (*n, tmp.join(format!("display{n}.bmp"))))
            .collect();
        let mut command: Vec<String> = ["screencapture", "-x", "-t", "bmp"]
            .iter()
            .map(|s| s.to_string())
            .collect();
        if let Some(n) = self.at {
            command.extend(["-D".into(), n.to_string()]);
        }
        command.extend(shots.iter().map(|(_, p)| p.to_string_lossy().into_owned()));
        (self.shoot)(&command);
        // a display keeps its number when an earlier one wrote no file
        let images: Result<Vec<(usize, Bitmap)>, String> = shots
            .iter()
            .filter_map(|(n, path)| fs::read(path).ok().map(|data| (*n, data)))
            .map(|(n, data)| Ok((n, Bitmap::new(&data)?)))
            .collect();
        fs::remove_dir_all(&tmp).map_err(|e| format!("{}: {e}", tmp.display()))?;
        let images = images?;
        // ponytail: the row is searched for here and again by the reader; at a few images a
        // second that costs nothing that matters. Pass the row on if it ever does.
        let rows: Vec<Option<Row>> = images.iter().map(|(_, b)| read_row(b, None)).collect();
        let shown = rows
            .iter()
            .position(|r| r.as_ref().is_some_and(|r| r.grid.is_some()));
        let given = shown.or(if images.is_empty() { None } else { Some(0) });
        for (i, row) in rows.iter().enumerate() {
            if Some(i) != given {
                note(row.as_ref());
            }
        }
        self.at = shown.map(|i| images[i].0);
        Ok(given
            .and_then(|i| images.into_iter().nth(i))
            .map(|(_, b)| b))
    }
}
