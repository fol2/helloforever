//! The processes around the capture, as tools/hellolink_strip.py runs them: the capture tool
//! (tools/strip_capture.swift, built into the user's cache folder), one frame of it, a stream
//! of frames, the look at every display for the row, and the slow fall-back with macOS
//! `screencapture`. A capture process is asked to stop (SIGTERM) before it is killed, so that
//! it can close its capture stream, and no wait on a process is without a limit (#38).

use crate::bitmap::{Bitmap, frames_from};
use crate::strip1::{Row, read_row};
use std::fs;
use std::io::{self, Read};
use std::os::unix::fs::DirBuilderExt;
use std::os::unix::process::CommandExt;
use std::os::unix::process::ExitStatusExt;
use std::path::{Path, PathBuf};
use std::process::{Child, ChildStdout, Command, ExitStatus, Stdio};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::mpsc::{self, Receiver, RecvTimeoutError, TryRecvError};
use std::sync::{Arc, LazyLock};
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

/// The capture source the program `exe` builds: the one beside it when there is one (an
/// install, `hellolink install-reader`), else CAPTURE_SOURCE in the checkout.
pub fn capture_source(exe: Option<&Path>) -> PathBuf {
    exe.and_then(|exe| Some(exe.parent()?.join("strip_capture.swift")))
        .filter(|beside| beside.is_file())
        .unwrap_or_else(|| PathBuf::from(CAPTURE_SOURCE))
}

/// The colour space the capture stream gives its pixels in (`watch --colour`; docs/specs/232.md,
/// part C, "Deeper colour").
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum Colour {
    /// sRGB, the default.
    #[default]
    Srgb,
    /// The display's own colour space.
    Display,
}

impl Colour {
    /// Its name in `--colour` and in the record.
    pub fn name(self) -> &'static str {
        match self {
            Colour::Srgb => "srgb",
            Colour::Display => "display",
        }
    }

    /// The capture tool's arguments before its command. None for sRGB: the default command
    /// is as before, so a tool given with `--capture` that has no `--colour` still runs.
    pub fn args(self) -> &'static [&'static str] {
        match self {
            Colour::Srgb => &[],
            Colour::Display => &["--colour", "display"],
        }
    }

    /// `tool [--colour display] stream <numbers>`.
    pub fn stream(self, tool: &Path, numbers: &[i64]) -> Vec<String> {
        std::iter::once(tool.to_string_lossy().into_owned())
            .chain(self.args().iter().map(|s| s.to_string()))
            .chain(std::iter::once("stream".into()))
            .chain(numbers.iter().map(|v| v.to_string()))
            .collect()
    }
}

/// Seconds as Python's "%g" writes the limits above (15.0 is "15").
fn g(seconds: f64) -> String {
    format!("{seconds}")
}

/// Set by Ctrl-C (SIGINT): the waits for a frame, a list or an image end early, and `watch`
/// stops its capture and ends, as Python's KeyboardInterrupt does.
static INTERRUPTED: LazyLock<Arc<AtomicBool>> = LazyLock::new(Arc::default);

/// Ctrl-C sets the flag instead of ending the process at once.
pub fn on_ctrl_c() -> std::io::Result<()> {
    signal_hook::flag::register(signal_hook::consts::SIGINT, Arc::clone(&INTERRUPTED)).map(|_| ())
}

/// Ctrl-C was pressed.
pub fn interrupted() -> bool {
    INTERRUPTED.load(Ordering::Relaxed)
}

/// Set when a pipe's reader thread was left (a child outside the group holds the pipe). A
/// blocking read cannot be cancelled in safe Rust, so `watch` then ends rather than try again:
/// at most one thread is left a run, not one a try.
static READER_LEFT: AtomicBool = AtomicBool::new(false);

/// A pipe's reader thread was left in this process.
pub fn reader_left() -> bool {
    READER_LEFT.load(Ordering::Relaxed)
}

/// An exit code as Python's returncode: a signal is its number, negative.
fn code_of(status: ExitStatus) -> i32 {
    status
        .code()
        .unwrap_or_else(|| -status.signal().unwrap_or(0))
}

/// Waits up to `seconds` for a process; None when it is still there. With `interruptible`,
/// Ctrl-C ends the wait too.
fn wait_for(child: &mut Child, seconds: f64, interruptible: bool) -> Option<ExitStatus> {
    let end = Instant::now() + Duration::from_secs_f64(seconds);
    loop {
        if let Ok(Some(status)) = child.try_wait() {
            return Some(status);
        }
        if Instant::now() >= end || (interruptible && interrupted()) {
            return None;
        }
        thread::sleep(Duration::from_millis(5));
    }
}

/// Sends a signal with kill(1): std sends only SIGKILL, and this crate has no unsafe code.
/// `target` is a process id, or a process group's as "-ID". kill(1) is waited for STOP_WAIT.
fn signal(name: &str, target: &str) {
    let sent = Command::new("kill")
        .args([&format!("-{name}"), "--", target])
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn();
    if let Ok(mut kill) = sent
        && wait_for(&mut kill, STOP_WAIT, false).is_none()
    {
        let _ = kill.kill();
        let _ = wait_for(&mut kill, STOP_WAIT, false);
    }
}

/// What a pipe gave, read in a thread of its own. A blocking read cannot be cancelled in safe
/// Rust: the thread ends at the pipe's end, which comes at the latest when the process group is
/// killed; a child that left the group can hold it longer, and the thread is then left (it
/// ends when that child does), and said. Only the first MAX_KEPT bytes are kept.
struct Pipe {
    rx: Receiver<Vec<u8>>,
    bytes: Vec<u8>,
    ended: bool,
}

impl Pipe {
    fn read(mut pipe: impl Read + Send + 'static) -> Pipe {
        let (tx, rx) = mpsc::channel();
        thread::spawn(move || {
            let mut buf = [0; 8192];
            loop {
                let n = match pipe.read(&mut buf) {
                    Ok(n) => n,
                    Err(e) if e.kind() == io::ErrorKind::Interrupted => continue, // a signal (#236)
                    Err(_) => return,
                };
                if n == 0 || tx.send(buf[..n].to_vec()).is_err() {
                    return;
                }
            }
        });
        Pipe {
            rx,
            bytes: Vec::new(),
            ended: false,
        }
    }

    /// Takes what came, until `end` at the latest (a child that writes without end cannot
    /// keep it here); true when the pipe has ended.
    fn poll(&mut self, end: Instant) -> bool {
        while !self.ended && Instant::now() < end {
            match self.rx.try_recv() {
                Ok(chunk) => {
                    let room = MAX_KEPT.saturating_sub(self.bytes.len());
                    self.bytes.extend(&chunk[..room.min(chunk.len())]);
                }
                Err(TryRecvError::Empty) => break,
                Err(TryRecvError::Disconnected) => self.ended = true,
            }
        }
        self.ended
    }

    fn text(&self) -> String {
        String::from_utf8_lossy(&self.bytes).into_owned()
    }
}

/// Bytes of a pipe kept: a child that writes without end does not fill the memory.
const MAX_KEPT: usize = 64 * 1024;

/// What a capture whose pipe stayed open after its group was killed is said to have done.
pub const LEFT: &str =
    "a child of it kept its output open from outside its process group: its reader was left";

/// A capture process, in a process group of its own, so that a child it leaves behind (which
/// may keep a pipe open) is stopped with it; Ctrl-C reaches it only through the reader.
/// Threads read its stderr and stdout; no read and no wait on it is without a limit.
///
/// The group is named after a keeper (`sleep 60`), started first and held unreaped (alive, or a
/// zombie) until after the group's last signal: a process id cannot be another's while it is
/// not reaped, so a signal to the group never reaches a recycled id. The capture itself may
/// be reaped as soon as it ends (std's `try_wait` reaps), since the group is not named after it.
struct Proc {
    child: Child,
    keeper: Child,
    err: Pipe,
    /// A stdout read whole (a command run to its end).
    out: Option<Pipe>,
    /// Threads that read stdout frame by frame: each drops its sender when it ends.
    readers: Vec<Receiver<()>>,
}

/// How a capture process ended.
#[derive(Debug)]
pub struct Ended {
    /// Its stderr, trimmed.
    pub error: String,
    /// Python's returncode; 0 for a process that was told to stop and did (SIGTERM, SIGKILL).
    pub code: i32,
    /// Every thread that read its pipes has ended.
    pub threads_ended: bool,
}

impl Proc {
    /// Starts a command; its stdout is given to the caller, or with `whole` read here.
    fn start(command: &[String], whole: bool) -> Result<(Proc, Option<ChildStdout>), String> {
        let (program, args) = command.split_first().ok_or("no command")?;
        // 60 s: it only has to be there when the capture joins its group; then, a zombie the
        // reader does not reap still holds the id. A reader killed outright leaves it 60 s.
        let mut keeper = Command::new("sleep")
            .arg("60")
            .process_group(0)
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .spawn()
            .map_err(|e| format!("the process group's keeper (sleep) could not be started: {e}"))?;
        let group = i32::try_from(keeper.id()).map_err(|e| e.to_string())?;
        let spawned = Command::new(program)
            .args(args)
            .process_group(group)
            .stdin(Stdio::null())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn();
        let mut child = match spawned {
            Ok(child) => child,
            Err(e) => {
                let _ = keeper.kill();
                let _ = wait_for(&mut keeper, STOP_WAIT, false);
                return Err(format!("{program} could not be started: {e}"));
            }
        };
        let err = child.stderr.take().map(Pipe::read);
        let stdout = child.stdout.take();
        let (out, stdout) = if whole {
            (stdout.map(Pipe::read), None)
        } else {
            (None, stdout)
        };
        let proc = Proc {
            child,
            keeper,
            err: err.ok_or("no stderr")?,
            out,
            readers: Vec::new(),
        };
        Ok((proc, stdout))
    }

    fn group(&self, name: &str) {
        signal(name, &format!("-{}", self.keeper.id()));
    }

    /// Tells the process to stop: SIGTERM, then SIGKILL (to its whole group) when it is still
    /// there after STOP_WAIT. It is asked first so that it can close its capture stream; a
    /// process that is killed cannot.
    fn stop(&mut self) {
        if let Ok(None) = self.child.try_wait() {
            signal("TERM", &self.child.id().to_string());
        }
        if wait_for(&mut self.child, STOP_WAIT, false).is_none() {
            self.group("KILL");
            let _ = self.child.kill();
        }
    }

    /// Every pipe and reader thread has ended (what came is taken until `end`).
    fn quiet(&mut self, end: Instant) -> bool {
        let err = self.err.poll(end);
        let out = self.out.as_mut().is_none_or(|p| p.poll(end));
        self.readers
            .retain(|r| !matches!(r.try_recv(), Err(TryRecvError::Disconnected)));
        err && out && self.readers.is_empty()
    }

    /// Waits up to `seconds` for the pipes and reader threads to end.
    fn settle(&mut self, seconds: f64) -> bool {
        let end = Instant::now() + Duration::from_secs_f64(seconds);
        loop {
            if self.quiet(end) {
                return true;
            }
            if Instant::now() >= end {
                return false;
            }
            thread::sleep(Duration::from_millis(5));
        }
    }

    /// After the process ended or was stopped: reaps it and lets its pipes end. A child of it
    /// that keeps a pipe open gets STOP_WAIT, then the group is killed, and the pipes get
    /// STOP_WAIT more; a pipe still open then is held from outside the group: its thread is
    /// left, and `threads_ended` says so. Last, the keeper is killed and reaped: the group's
    /// name is free only after its last signal.
    fn finish(&mut self) -> (Option<ExitStatus>, bool) {
        let mut quiet = self.settle(STOP_WAIT);
        if !quiet {
            self.group("KILL");
        }
        let status = wait_for(&mut self.child, STOP_WAIT, false);
        if !quiet {
            quiet = self.settle(STOP_WAIT);
        }
        if !quiet {
            READER_LEFT.store(true, Ordering::Relaxed);
        }
        self.release_keeper();
        (status, quiet)
    }

    fn release_keeper(&mut self) {
        if let Ok(None) = self.keeper.try_wait() {
            let _ = self.keeper.kill();
        }
        let _ = wait_for(&mut self.keeper, STOP_WAIT, false);
    }

    /// Waits for a capture process whose output is over. `told`: the caller is the one who
    /// stops it (it left early, or gave up), so an end by SIGTERM or SIGKILL is no failure and
    /// comes back as 0. A process that ended its output by itself gets STOP_WAIT to leave by
    /// itself, so its own exit code stands; one that then stays is stopped, and that is a
    /// failure.
    fn ended(&mut self, told: bool) -> Ended {
        let stuck = self.halt(told);
        self.outcome(told, stuck)
    }

    /// The first half of `ended`: waits for the process, or stops it. True when it stayed
    /// after its output ended (`stuck`).
    fn halt(&mut self, told: bool) -> bool {
        let stuck = !told && wait_for(&mut self.child, STOP_WAIT, false).is_none();
        if told || stuck {
            self.stop();
        }
        stuck
    }

    /// The second half of `ended`, once the process was stopped or left.
    fn outcome(&mut self, told: bool, stuck: bool) -> Ended {
        let (status, threads_ended) = self.finish();
        let mut error = self.err.text().trim().to_string();
        // not reaped even after SIGKILL: taken as killed
        let mut code = status.map_or(-9, code_of);
        if stuck {
            if error.is_empty() {
                error = "it did not leave after its output ended".into();
            }
            code = if code == 0 { 1 } else { code };
        } else if told && STOPPED.contains(&code) {
            code = 0;
        }
        if !threads_ended {
            // the cleanup did not end: a failure, whatever the process did
            error = if error.is_empty() {
                LEFT.to_string()
            } else {
                format!("{error}; {LEFT}")
            };
            code = if code == 0 { 1 } else { code };
        }
        Ended {
            error,
            code,
            threads_ended,
        }
    }
}

impl Drop for Proc {
    /// A Proc dropped before its end (a caller that returned early) leaves no keeper behind.
    fn drop(&mut self) {
        if let Ok(None) = self.child.try_wait() {
            let _ = self.child.kill();
            let _ = wait_for(&mut self.child, STOP_WAIT, false);
        }
        self.release_keeper();
    }
}

/// Why a command run with a limit gave no result.
#[derive(Debug)]
pub enum Unrun {
    /// It could not be started: why.
    Start(String),
    /// It did not end within the limit, and was killed.
    Late,
    /// Ctrl-C was pressed: it was killed.
    Interrupted,
    /// What it made cannot be read: why.
    Bad(String),
}

/// Runs a command to its end, with a limit: (exit code, stdout, stderr). A command still
/// there at the limit, or at Ctrl-C, is killed with its process group.
pub fn run_limited(command: &[String], seconds: f64) -> Result<(i32, String, String), Unrun> {
    let (mut proc, _) = Proc::start(command, true).map_err(Unrun::Start)?;
    let Some(status) = wait_for(&mut proc.child, seconds, true) else {
        proc.group("KILL");
        let _ = proc.child.kill();
        let (_, quiet) = proc.finish();
        return Err(if interrupted() {
            Unrun::Interrupted
        } else if !quiet {
            Unrun::Bad(format!("it did not end in {} s; {LEFT}", g(seconds)))
        } else {
            Unrun::Late
        });
    };
    let (_, quiet) = proc.finish();
    if !quiet {
        return Err(Unrun::Bad(LEFT.into()));
    }
    let out = proc.out.as_ref().map(Pipe::text).unwrap_or_default();
    Ok((code_of(status), out, proc.err.text()))
}

/// The built capture stream: the one given, or one built from the source into the user's
/// cache folder. The built tool's name holds a digest of the source's bytes, so a reader never
/// takes a tool built from another source (an install and a checkout share the folder; the
/// Python reader's tool is `strip_capture`). It is built under a name of its own, then renamed:
/// a build cut short is never taken. Err is why there is none: the caller then falls back to
/// one `screencapture` a frame (docs/specs/29.md, section 8).
/// ponytail: tools of older sources stay in the folder (about 100 KB each); delete by hand.
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
    let source = capture_source(std::env::current_exe().ok().as_deref());
    build_capture(
        &PathBuf::from(home).join("Library/Caches/HelloLink"),
        &source,
        "swiftc",
    )
}

/// The capture tool built from `source` with `compiler` (swiftc) in `folder`, under a name
/// that holds the source's digest; built only when that name is not there yet.
pub fn build_capture(folder: &Path, source: &Path, compiler: &str) -> Result<PathBuf, String> {
    let could_not = |e: std::io::Error| format!("it could not be built: {e}");
    let bytes = fs::read(source).map_err(could_not)?;
    let digest = crate::built_from::fnv(crate::built_from::FNV_START, &bytes);
    let built = folder.join(format!("strip_capture-{digest:016x}"));
    let stale = !built.is_file();
    let building = folder.join(format!(
        ".strip_capture-{digest:016x}-{}",
        std::process::id()
    ));
    // the compiler reads a copy of the bytes the digest is of: the source can change meanwhile
    let snapshot = building.with_extension("swift");
    if stale {
        fs::create_dir_all(folder).map_err(could_not)?;
        fs::write(&snapshot, &bytes).map_err(could_not)?;
        let command: Vec<String> = [compiler, "-O", "-swift-version", "5"]
            .iter()
            .map(|s| s.to_string())
            .chain([snapshot.to_string_lossy().into_owned(), "-o".into()])
            .chain([building.to_string_lossy().into_owned()])
            .collect();
        let done = run_limited(&command, BUILD_WAIT);
        let done = done.and_then(|r| {
            if r.0 == 0 {
                fs::rename(&building, &built).map_err(|e| Unrun::Bad(e.to_string()))?;
            }
            Ok(r)
        });
        let _ = fs::remove_file(&building);
        let _ = fs::remove_file(&snapshot);
        match done {
            Err(Unrun::Start(e) | Unrun::Bad(e)) => {
                return Err(format!("it could not be built: {e}"));
            }
            Err(Unrun::Late) => {
                return Err(format!(
                    "it could not be built: swiftc took more than {} s",
                    g(BUILD_WAIT)
                ));
            }
            Err(Unrun::Interrupted) => return Err("it could not be built: interrupted".into()),
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

/// The first frame a capture command gives; None when it ended cleanly without one. The
/// process is always stopped. Err is the reason when the process failed, and when it gave no
/// frame in `wait` seconds (ONE_FRAME_WAIT; the tests give less): on an idle machine a stream
/// gives its first frame at once, under load in up to about 10 s (#103); longer silence means
/// the capture service is not answering, and the caller tries the stream again later. Ctrl-C
/// ends the wait: the process is stopped, and Err is "interrupted".
pub fn one_frame(command: &[String], wait: f64) -> Result<Option<Bitmap>, String> {
    let (mut shot, stdout) = Proc::start(command, false)?;
    let (tx, rx) = mpsc::channel();
    let (done, reader) = mpsc::channel::<()>();
    shot.readers.push(reader);
    thread::spawn(move || {
        let _done = done; // dropped when the thread ends
        let mut stdout = stdout;
        let first = stdout.as_mut().and_then(|pipe| frames_from(pipe).next());
        // the pipe goes back with the frame: it stays open until the process was told to
        // stop, so that a capture still writing does not fail on a broken pipe first
        let _ = tx.send((first, stdout));
    });
    let end = Instant::now() + Duration::from_secs_f64(wait);
    let (received, in_time) = first_by(&rx, end);
    let (got, kept) = match received {
        Some((got, pipe)) if in_time => (Some(got), pipe),
        Some((_, pipe)) => (None, pipe), // after the limit: the limit holds
        None => (None, None),
    };
    let late = got.is_none(); // no frame in time: given up
    let (frame, failed) = match got {
        Some(Some(Ok(frame))) => (Some(frame), None),
        Some(Some(Err(e))) => (None, Some(format!("bad output: {e}"))),
        _ => (None, None),
    };
    let took = frame.is_some();
    let Ended {
        error,
        code,
        threads_ended,
    } = shot.ended(took || failed.is_some() || late);
    drop(kept);
    if !threads_ended {
        let first = failed.or(late.then(|| format!("no frame in {} s", g(wait))));
        return Err(first.map_or(error.clone(), |first| format!("{first}; {error}")));
    }
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
        if interrupted() {
            return Err("interrupted".into());
        }
        return Err(format!("no frame in {} s", g(wait)));
    }
    Ok(frame)
}

/// The first item of `rx`, waited for until `end` (Ctrl-C ends the wait too), and whether it
/// came in time: one that is there but taken after `end` (the thread was held up) is late.
pub fn first_by<T>(rx: &Receiver<T>, end: Instant) -> (Option<T>, bool) {
    loop {
        let slice = end
            .saturating_duration_since(Instant::now())
            .min(Duration::from_millis(100));
        match rx.recv_timeout(slice) {
            Ok(item) => return (Some(item), Instant::now() < end),
            Err(_) if Instant::now() >= end || interrupted() => return (None, false),
            Err(_) => {}
        }
    }
}

/// Where a look found the row: the display, its width, and the row's grid (left edge, top,
/// square's side) in the display's pixels.
pub type Found = (i64, i64, (f64, i64, f64));

/// The displays the capture tool lists: index, width, height. Err when the tool fails or does
/// not list them in `wait` seconds (ONE_FRAME_WAIT in use; a silent capture service: the caller
/// tries again later).
pub fn displays(tool: &Path, wait: f64) -> Result<Vec<(i64, i64, i64)>, String> {
    let command = [tool.to_string_lossy().into_owned(), "list".into()];
    let (code, out, err) = match run_limited(&command, wait) {
        Ok(done) => done,
        Err(Unrun::Late) => {
            return Err(format!("no list of the displays in {} s", g(wait)));
        }
        Err(Unrun::Interrupted) => return Err("interrupted".into()),
        Err(Unrun::Start(e) | Unrun::Bad(e)) => return Err(e),
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
/// (a record of the play, #178). `one_frame` takes a capture command. The look's captures are
/// in `colour`, as the stream after it, so that a run's record is in one colour space.
pub fn look(
    tool: &Path,
    colour: Colour,
    displays: &[(i64, i64, i64)],
    one_frame: OneFrame,
    note: &mut dyn FnMut(Option<&Row>),
) -> Result<Result<Found, String>, String> {
    if displays.is_empty() {
        return Ok(Err("no display (are the displays asleep?)".into()));
    }
    for &(index, width, height) in displays {
        for lines in [64, height] {
            let command = colour.stream(tool, &[index, 0, 0, width, lines, 30, 1]);
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
    colour: Colour,
    note: &mut dyn FnMut(Option<&Row>),
) -> Result<Result<Found, String>, String> {
    let listed = displays(tool, ONE_FRAME_WAIT)?;
    look(
        tool,
        colour,
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
/// is one Err with the reason, then the end. `close` leaves it early and says how the process
/// ended; dropping it does the same and drops the answer.
pub struct Stream {
    proc: Proc,
    frames: Option<Receiver<Item>>,
    idle: Duration,
    over: bool,
}

impl Stream {
    pub fn start(command: &[String], idle: f64) -> Result<Stream, String> {
        let (mut proc, stdout) = Proc::start(command, false)?;
        let (tx, frames) = mpsc::sync_channel(8);
        let (done, pump) = mpsc::channel::<()>();
        proc.readers.push(pump);
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
            proc,
            frames: Some(frames),
            idle: Duration::from_secs_f64(idle),
            over: false,
        })
    }

    /// The process's id.
    pub fn pid(&self) -> u32 {
        self.proc.child.id()
    }

    /// Stops the process (`clean`: its output ended by itself) and its reader thread.
    fn finish(&mut self, clean: bool) -> Ended {
        self.over = true;
        // The process is stopped while the pipe is still read: a capture whose pipe closed
        // first could fail by itself on a write (a broken pipe), and that is not its failure.
        let stuck = self.proc.halt(!clean);
        self.frames = None; // a reader thread waiting to hand a frame on gives up
        self.proc.outcome(!clean, stuck)
    }

    /// Leaves the stream: how its process ended, told to stop (SIGTERM or SIGKILL are code
    /// 0, its own failure is its code and stderr). None when the stream had already ended:
    /// its end was given by `next`.
    pub fn close(mut self) -> Option<Ended> {
        if self.over {
            return None;
        }
        Some(self.finish(false))
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
                let ended = self.finish(false);
                Some(Err(match ended.threads_ended {
                    true => format!("bad output: {e}"),
                    false => format!("bad output: {e}; {}", ended.error),
                }))
            }
            Item::End => {
                let Ended { error, code, .. } = self.finish(true);
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

/// A new empty folder in the temporary folder, for its owner only (0700, as Python's
/// mkdtemp): the screenshots in it show the screen.
fn temp_folder() -> Result<PathBuf, String> {
    let base = std::env::temp_dir();
    let stamp = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map_or(0, |d| d.as_nanos());
    for n in 0..100 {
        let dir = base.join(format!("hellolink-{}-{stamp}-{n}", std::process::id()));
        if fs::DirBuilder::new().mode(0o700).create(&dir).is_ok() {
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
pub type Shoot = Box<dyn FnMut(&[String]) -> Result<(), Unrun>>;

impl Screencapture {
    pub fn new(shoot: Shoot) -> Screencapture {
        Screencapture { at: None, shoot }
    }

    /// With macOS `screencapture`, given ONE_FRAME_WAIT a turn (Python waits without a limit).
    /// Its exit code is not looked at, as in Python: a display it could not take has no file.
    pub fn real() -> Screencapture {
        Screencapture::new(Box::new(|command| {
            run_limited(command, ONE_FRAME_WAIT).map(|_| ())
        }))
    }

    /// One turn: the image given on, or None when no display gave one. `note` gets the row of
    /// each image that is not given on (a record of the play, #178). Err when `screencapture`
    /// could not be started, did not end within its limit, was interrupted, or wrote an image
    /// that cannot be read; the turn's files are deleted whatever happens, and a turn that did
    /// not end is not read.
    pub fn turn(&mut self, note: &mut dyn FnMut(Option<&Row>)) -> Result<Option<Bitmap>, Unrun> {
        let tmp = temp_folder().map_err(Unrun::Bad)?;
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
        let shot = (self.shoot)(&command);
        // a display keeps its number when an earlier one wrote no file
        let images: Result<Vec<(usize, Bitmap)>, Unrun> = shot.and_then(|_| {
            shots
                .iter()
                .filter_map(|(n, path)| fs::read(path).ok().map(|data| (*n, data)))
                .map(|(n, data)| Ok((n, Bitmap::new(&data).map_err(Unrun::Bad)?)))
                .collect()
        });
        let removed = fs::remove_dir_all(&tmp);
        let images = images?;
        removed.map_err(|e| Unrun::Bad(format!("{}: {e}", tmp.display())))?;
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
