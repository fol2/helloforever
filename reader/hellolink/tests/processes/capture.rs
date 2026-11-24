//! The processes around the capture, with real processes and the real time limits: the checks
//! of tests/strip_watch_test.py (its capture part), strip_slow_start_test.py,
//! strip_capture_late_test.py and the list's limit of strip_stream_back_test.py. Each assert's
//! message is the Python check's name. Fake captures are the fake_capture program, and small
//! `sh` scripts where a capture must catch or ignore SIGTERM (safe Rust cannot). Each test
//! that waits is a test of its own, so that cargo runs them at the same time.

use crate::common::*;
use hellolink::capture::{ONE_FRAME_WAIT, Stream, capture_tool, displays, first_by, one_frame};
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::thread;
use std::time::{Duration, Instant};

const FAKE: &str = env!("CARGO_BIN_EXE_fake_capture");

/// A folder of the test's own, empty.
fn folder(name: &str) -> PathBuf {
    let dir = Path::new(env!("CARGO_TARGET_TMPDIR")).join(format!("capture-{name}"));
    let _ = fs::remove_dir_all(&dir);
    fs::create_dir_all(&dir).unwrap();
    dir
}

fn words(w: &[&str]) -> Vec<String> {
    w.iter().map(|s| s.to_string()).collect()
}

fn fake(w: &[&str]) -> Vec<String> {
    [vec![FAKE.to_string()], words(w)].concat()
}

/// A frame of the row on the pipe, 2560 x 4, as tests/strip_watch_test.py's `framed(one)`.
fn frame_file(dir: &Path) -> String {
    let raw = capture(4711, 4, LEVELS, &frame(1), None, WIDE);
    let mut data = b"HLC1".to_vec();
    data.extend((WIDE as u32).to_le_bytes());
    data.extend(4u32.to_le_bytes());
    data.extend(raw);
    let path = dir.join("frame.bin");
    fs::write(&path, data).unwrap();
    path.to_string_lossy().into_owned()
}

/// tests/strip_watch_test.py's CHILD: a capture that writes "asked" to MARK when it is told
/// to stop (SIGTERM), or ignores it ("deaf..."). Its sleeps hold no pipe of the reader's, so
/// a capture that is killed leaves no process behind that keeps the pipes open.
const CHILD: &str = r#"
mark=$1 what=$2
case $what in
    deaf*) trap '' TERM ;;
    *) trap 'echo asked > "$mark"; kill $! 2>/dev/null; exit 0' TERM ;;
esac
frame() { printf 'HLC1\002\000\000\000\001\000\000\000\000\000\000\000\000\000\000\000'; }
nap() { sleep "$1" >/dev/null 2>&1 & wait $!; }
case $what in
    frame) frame ;;
    late) nap 0.7; frame ;;
    slow-exit) exec >&-; nap 0.3; exit 0 ;;
    deaf-stays) exec >&-; exec sleep 30 ;;
    deaf-fails) nap 3.3; printf 'the display went away' >&2; exit 7 ;;
    deaf) exec sleep 30 ;;
esac
nap 30
"#;

fn child(dir: &Path, mark: &str, what: &str) -> (Vec<String>, PathBuf) {
    let script = dir.join("child.sh");
    fs::write(&script, CHILD).unwrap();
    let mark = dir.join(mark);
    let command = vec![
        "sh".to_string(),
        script.to_string_lossy().into_owned(),
        mark.to_string_lossy().into_owned(),
        what.to_string(),
    ];
    (command, mark)
}

/// Every item of a stream, to its end; a stream that does not end in 20 s fails the test
/// instead of holding it.
fn whole(
    command: Vec<String>,
    idle: f64,
) -> Vec<Result<Option<hellolink::bitmap::Bitmap>, String>> {
    within(20.0, move || {
        Stream::start(&command, idle).unwrap().collect::<Vec<_>>()
    })
    .expect("the stream ended within 20 s")
    .0
}

/// The tests' ONE_FRAME_WAIT, where the Python test sets it: "these checks are of the limit's
/// handling, not its value (#103)".
const THREE: f64 = 3.0;

fn took<T>(f: impl FnOnce() -> T) -> (T, f64) {
    let began = Instant::now();
    let out = f();
    (out, began.elapsed().as_secs_f64())
}

fn is_running(pid: u32) -> bool {
    Command::new("kill")
        .args(["-0", &pid.to_string()])
        .stderr(std::process::Stdio::null())
        .status()
        .is_ok_and(|s| s.success())
}

// --- tests/strip_watch_test.py, the processes around the capture ---

#[test]
fn one_frame_takes_the_first_frame() {
    let dir = folder("first");
    let file = frame_file(&dir);
    let (got, seconds) = took(|| one_frame(&fake(&["feed", &file, "30", "30"]), ONE_FRAME_WAIT));
    assert!(
        matches!(got, Ok(Some(_))) && seconds < 5.0,
        "one_frame takes the first frame and stops the process, though it would run on"
    );
}

#[test]
fn stream_frames_gives_frames_and_idle_turns() {
    let dir = folder("frames");
    let file = frame_file(&dir);
    let command = fake(&["feed", &file, "0.7", "0"]);
    let seen: Vec<bool> = whole(command, 0.3)
        .into_iter()
        .map(|item| item.unwrap().is_some())
        .collect();
    assert!(
        seen[0] && seen.contains(&false) && seen.iter().filter(|f| **f).count() == 2,
        "stream_frames gives the frames, and None when none came for a while"
    );
}

#[test]
fn failures_of_the_capture_process() {
    let dir = folder("failures");
    // an idle turn before the end is no frame: a slow start under load gives one (seen in a
    // full run of tests/run_all.sh)
    let events = |items: Vec<_>| -> Vec<_> {
        items
            .into_iter()
            .filter(|i| !matches!(i, Ok(None)))
            .collect()
    };
    let items = events(whole(fake(&["fail"]), 0.3));
    assert!(
        matches!(&items[..], [Err(e)] if e == "no display"),
        "a capture process that fails is an error with its reason, not an empty stream"
    );
    assert!(
        capture_tool(Some(&dir.join("nope").to_string_lossy())).is_err(),
        "a capture tool that is not there is reported, for the fall-back to take over"
    );
    assert!(
        matches!(one_frame(&fake(&["fail"]), ONE_FRAME_WAIT), Err(e) if e == "no display"),
        "one_frame says why a capture failed, instead of 'no frame'"
    );
    assert!(
        matches!(one_frame(&fake(&["pass"]), ONE_FRAME_WAIT), Ok(None)),
        "one_frame gives None for a capture that ended cleanly with nothing"
    );
    let nope = vec![dir.join("nope").to_string_lossy().into_owned()];
    assert!(
        one_frame(&nope, ONE_FRAME_WAIT).is_err() && Stream::start(&nope, 0.1).is_err(),
        "a command that cannot be started is a failed capture too"
    );
    let items = events(whole(fake(&["junk"]), 0.3));
    assert!(
        matches!(&items[..], [Err(e)] if e.starts_with("bad output")),
        "output that is not frames is a failed capture, not a silent end"
    );
}

#[test]
fn output_that_is_not_a_frame_from_a_process_that_runs_on() {
    let (got, seconds) = took(|| one_frame(&fake(&["junk-hang"]), ONE_FRAME_WAIT));
    assert!(
        matches!(got, Err(e) if e.starts_with("bad output")) && seconds < 5.0,
        "output that is not a frame from a process that runs on: stopped at once and reported, not waited for"
    );
}

#[test]
fn leaving_a_stream_early() {
    let dir = folder("flood");
    let file = frame_file(&dir);
    let mut stream = Stream::start(&fake(&["flood", &file]), 0.3).unwrap();
    // the first frame; on a busy machine an idle turn (None) may come before it
    let first = stream
        .by_ref()
        .take(20)
        .find(|item| !matches!(item, Ok(None)));
    thread::sleep(Duration::from_millis(500)); // the queue fills behind the one frame taken
    let pid = stream.pid();
    let closed = stream.close();
    let running = is_running(pid);
    assert!(
        matches!(first, Some(Ok(Some(_))))
            && closed
                .as_ref()
                .is_some_and(|e| e.threads_ended && e.code == 0)
            && !running,
        "leaving a stream early stops its process and its reader thread, though the queue was full ({first:?}, {closed:?}, running: {running})"
    );
}

// A capture process is asked to stop before it is killed, so that it can close its stream,
// and no wait for a frame is without a limit (#38).

#[test]
fn a_capture_that_gives_no_frame() {
    let dir = folder("silent");
    let (command, mark) = child(&dir, "silent", "none");
    let (got, seconds) = took(|| one_frame(&command, THREE));
    // the two waits' budget is the frame wait and STOP_WAIT before the kill (3 + 2 s); the signal, the
    // pipes and the reaping add a little: the bound is the budget and a second more, as a loaded machine
    // took 5.03 s (23 Nov 2026; LESSONS: a check of two measures states its margin)
    let bound = THREE + hellolink::capture::STOP_WAIT + 1.0;
    assert!(
        matches!(&got, Err(e) if e.contains("no frame")) && seconds < bound,
        "a capture that gives no frame is a failure after 3 s, not waited for ({got:?}, {seconds} s, bound {bound} s)"
    );
    assert!(mark.exists(), "... and it was asked to stop, not killed");
}

#[test]
fn a_capture_that_does_not_listen() {
    let dir = folder("deaf");
    let (command, _) = child(&dir, "deaf", "deaf");
    let (got, seconds) = took(|| one_frame(&command, THREE));
    assert!(
        got.is_err() && seconds < 7.0,
        "a capture that gives no frame and does not listen is killed two seconds later"
    );
}

#[test]
fn a_capture_that_fails_after_it_was_told_to_stop() {
    let dir = folder("fails");
    let (command, _) = child(&dir, "fails", "deaf-fails");
    let got = one_frame(&command, THREE);
    assert!(
        matches!(&got, Err(e) if e.contains("the display went away")),
        "a capture that fails by itself after it was told to stop is still a failure, with its reason ({got:?})"
    );
}

#[test]
fn a_capture_whose_output_ends_before_it_leaves() {
    let dir = folder("slow");
    let (command, mark) = child(&dir, "slow", "slow-exit");
    assert!(
        matches!(one_frame(&command, THREE), Ok(None)) && !mark.exists(),
        "a capture whose output ends before it leaves is waited for: no frame, no failure, no signal"
    );
    let (command, mark) = child(&dir, "slow2", "slow-exit");
    let items = whole(command, 0.5);
    assert!(
        items.iter().all(|i| matches!(i, Ok(None))) && !mark.exists(),
        "a stream whose output ends before it leaves ends cleanly"
    );
}

#[test]
fn a_capture_that_gave_its_frame() {
    let dir = folder("one");
    let (command, mark) = child(&dir, "one", "frame");
    assert!(
        matches!(one_frame(&command, THREE), Ok(Some(_))) && mark.exists(),
        "a capture that gave its frame is asked to stop, not killed"
    );
}

#[test]
fn a_stream_whose_reader_leaves_early() {
    let dir = folder("left");
    let (command, mark) = child(&dir, "left", "late");
    let mut stream = Stream::start(&command, 0.5).unwrap();
    // a None is an idle turn, not a frame
    let (mut idle, mut first) = (false, None);
    for item in stream.by_ref().take(10) {
        match item {
            Ok(None) => idle = true,
            Ok(Some(frame)) => {
                first = Some(frame);
                break;
            }
            Err(_) => break,
        }
    }
    assert!(
        first.is_some() && idle,
        "a stream gives its frame, after an idle turn"
    );
    stream.close();
    assert!(
        mark.exists(),
        "a stream whose reader leaves early is asked to stop, not killed"
    );
}

#[test]
fn a_capture_whose_output_ends_but_which_stays() {
    let dir = folder("stays");
    let (command, _) = child(&dir, "stays", "deaf-stays");
    let (got, seconds) = took(|| one_frame(&command, THREE));
    assert!(
        got.is_err() && seconds < 7.0,
        "a capture whose output ends but which stays and does not listen is a failure, not a clean end"
    );
}

#[test]
fn a_stream_whose_output_ends_but_which_stays() {
    let dir = folder("stays2");
    let (command, _) = child(&dir, "stays2", "deaf-stays");
    let (items, seconds) = took(|| whole(command, 0.5));
    assert!(
        items.last().is_some_and(|i| i.is_err()) && seconds < 7.0,
        "... and the same for a stream ({seconds} s)"
    );
}

// --- tests/strip_slow_start_test.py: a capture whose first frame is slow is no failure (#103) ---

#[test]
fn a_first_frame_after_5_s() {
    let (got, seconds) = took(|| one_frame(&fake(&["slow", "5"]), ONE_FRAME_WAIT));
    assert!(
        matches!(got, Ok(Some(_))),
        "a first frame after 5 s is taken, not a failure ({seconds} s)"
    );
    // (const) the limit is at least 12 s: the slowest first frame seen under load was 10.1 s
    const { assert!(ONE_FRAME_WAIT >= 12.0) };
}

#[test]
fn a_capture_that_gives_nothing_fails_at_the_limit() {
    let (got, seconds) = took(|| one_frame(&fake(&["slow", "99"]), THREE));
    assert!(
        matches!(&got, Err(e) if e.contains("no frame")) && seconds < THREE + 3.0,
        "a capture that gives nothing still fails, at the limit ({got:?}, {seconds} s)"
    );
}

// --- tests/strip_capture_late_test.py: the limit holds once it has passed (#38) ---

#[test]
fn a_frame_after_the_limit_is_not_taken() {
    let dir = folder("late");
    let script = dir.join("late.sh");
    fs::write(
        &script,
        "trap '' TERM\nsleep 3.4\n\
         printf 'HLC1\\002\\000\\000\\000\\001\\000\\000\\000\\000\\000\\000\\000\\000\\000\\000\\000'\n\
         exec sleep 30\n",
    )
    .unwrap();
    let command = words(&["sh", &script.to_string_lossy()]);
    let (got, seconds) = took(|| one_frame(&command, THREE));
    assert!(
        matches!(&got, Err(e) if e.contains("no frame")) && seconds < 7.0,
        "a frame that comes after the 3 s limit is not taken: the capture failed ({got:?})"
    );
}

// --- tests/strip_stream_back_test.py: the look at the stream has a limit ---

#[test]
fn a_list_of_the_displays_that_does_not_come() {
    let dir = folder("list");
    let tool = dir.join("tool");
    executable(&tool, "#!/bin/sh\nexec sleep 60\n");
    let (got, seconds) = took(|| displays(&tool, THREE));
    assert!(
        (THREE..THREE + 2.0).contains(&seconds),
        "the list of the displays has a limit of some seconds ({seconds} s)"
    );
    assert!(
        matches!(&got, Err(e) if e.contains("list") && e.contains(" 3 s")),
        "a list that does not come is a failure of the stream, which says its limit ({got:?})"
    );
}

#[test]
fn a_list_of_the_displays_after_3_s_is_still_taken() {
    // the search for the row waits the real limit for the list, not the tests' short one
    let dir = folder("list-late");
    let tool = dir.join("tool");
    executable(
        &tool,
        "#!/bin/sh\n[ \"$1\" = list ] && { sleep 4; printf '0 2560 4\\n'; exit 0; }\nexit 1\n",
    );
    let got = hellolink::capture::locate(&tool, hellolink::capture::Colour::Srgb, &mut |_| {});
    assert!(
        !matches!(&got, Err(e) if e.contains("no list of the displays")),
        "a list of the displays that comes after 4 s is taken ({got:?})"
    );
}

// --- review round 1: a child of the capture that keeps a pipe open (#198) ---

/// `f` in a thread of its own: its result and seconds, or None when it took more than
/// `seconds` (the thread is left).
fn within<T: Send + 'static>(
    seconds: f64,
    f: impl FnOnce() -> T + Send + 'static,
) -> Option<(T, f64)> {
    let (tx, rx) = std::sync::mpsc::channel();
    thread::spawn(move || {
        let began = Instant::now();
        let out = f();
        let _ = tx.send((out, began.elapsed().as_secs_f64()));
    });
    rx.recv_timeout(Duration::from_secs_f64(seconds)).ok()
}

#[test]
fn a_child_of_the_capture_that_keeps_stderr_open() {
    // the capture fails with its reason, and leaves a child that keeps stderr open for 60 s
    let command = words(&[
        "sh",
        "-c",
        "sleep 60 >/dev/null & printf 'no display' >&2; exit 3",
    ]);
    let got = within(15.0, move || one_frame(&command, ONE_FRAME_WAIT));
    assert!(
        matches!(&got, Some((Err(e), s)) if e == "no display" && *s < 8.0),
        "a child of the capture that keeps stderr open holds the reader at most some seconds, and the reason still comes ({got:?})"
    );
}

#[test]
fn a_child_of_the_list_that_keeps_stdout_open() {
    let dir = folder("list-child");
    let tool = dir.join("tool");
    executable(
        &tool,
        "#!/bin/sh\nprintf '0 2560 4\\n'\nsleep 60 2>/dev/null &\n",
    );
    let got = within(15.0, move || displays(&tool, THREE));
    assert!(
        matches!(&got, Some((Ok(d), s)) if d == &[(0, 2560, 4)] && *s < 8.0),
        "a list whose child keeps stdout open is read whole, within some seconds ({got:?})"
    );
}

#[test]
fn a_child_of_the_stream_that_keeps_stdout_open() {
    // one frame, then the capture leaves; its child keeps stdout open for 60 s
    let command = words(&[
        "sh",
        "-c",
        &format!("'{FAKE}' slow 0; sleep 60 2>/dev/null & exit 0"),
    ]);
    let got = within(15.0, move || {
        let mut stream = Stream::start(&command, 0.3).unwrap();
        let first = stream
            .by_ref()
            .take(20)
            .find(|item| !matches!(item, Ok(None)));
        let closed = stream.close();
        (
            matches!(first, Some(Ok(Some(_)))),
            closed.is_some_and(|e| e.threads_ended),
        )
    });
    assert!(
        matches!(&got, Some(((true, true), s)) if *s < 8.0),
        "a stream left early ends its reader thread, though a child of the capture keeps stdout open ({got:?})"
    );
}

// --- review round 2 of #198 ---

#[test]
fn a_child_of_the_capture_that_keeps_writing() {
    // the capture fails; its child writes to stderr without end
    let command = words(&["sh", "-c", "yes hellolink-test-writer >&2 & exit 3"]);
    let got = within(15.0, move || {
        one_frame(&command, ONE_FRAME_WAIT).map(|_| ())
    });
    let _ = Command::new("pkill")
        .args(["-f", "yes hellolink-test-writer"])
        .status();
    assert!(
        matches!(&got, Some((Err(_), s)) if *s < 8.0),
        "a child of the capture that keeps writing to its stderr holds the reader at most some seconds ({:?})",
        got.map(|(r, s)| (r.map_err(|e| e.len()), s))
    );
}

#[test]
fn a_child_of_the_capture_outside_its_group() {
    let got = within(15.0, || one_frame(&fake(&["escape", "30"]), THREE));
    assert!(
        matches!(&got, Some((Err(e), s)) if e.contains("kept its output open") && *s < 10.0),
        "a capture that left a child outside its group with its output open is a failure that says so ({got:?})"
    );
    assert!(
        hellolink::capture::reader_left(),
        "... and the process knows a reader thread was left, so that watch does not try again"
    );
    let dir = folder("list-escape");
    let tool = dir.join("tool");
    executable(
        &tool,
        &format!("#!/bin/sh\nprintf '0 2560 4\\n'\nexec '{FAKE}' escape 30\n"),
    );
    let got = within(15.0, move || displays(&tool, THREE));
    assert!(
        matches!(&got, Some((Err(e), s)) if e.contains("kept its output open") && *s < 10.0),
        "... and so is a list of the displays ({got:?})"
    );
}

#[test]
fn the_capture_group_is_not_named_after_the_capture() {
    // its stderr says its process group; it fails, so the stream ends with that text
    let command = words(&["sh", "-c", "ps -o pgid= -p $$ >&2; exit 3"]);
    let stream = Stream::start(&command, 0.3).unwrap();
    let pid = stream.pid();
    let items = within(15.0, move || stream.collect::<Vec<_>>()).unwrap().0;
    let group: u32 = match items.last() {
        Some(Err(e)) => e.trim().parse().unwrap(),
        other => panic!("no group in {other:?}"),
    };
    assert_ne!(
        group, pid,
        "the capture's process group is named after a keeper the reader holds unreaped, not after the capture, whose id is freed when it is reaped"
    );
}

#[test]
fn a_frame_taken_after_the_limit_is_late() {
    // the frame is there, but the reader takes it after the limit (it was held up)
    let (tx, rx) = std::sync::mpsc::channel();
    tx.send("frame").unwrap();
    let end = Instant::now() - Duration::from_millis(1);
    assert_eq!(
        first_by(&rx, end),
        (Some("frame"), false),
        "a frame taken after the limit is late, though it was there: the limit holds on a good receive too"
    );
    let (tx, rx) = std::sync::mpsc::channel();
    tx.send("frame").unwrap();
    assert_eq!(
        first_by(&rx, Instant::now() + Duration::from_secs(1)),
        (Some("frame"), true),
        "... and one taken in time is in time"
    );
}

/// A capture tool that answers `[--window Wow] list | stream ...` with one 2560 x 4 frame of the
/// row, and writes each call's arguments to `log`. `window`: "ok", "none" (no game window),
/// "blank" (the window's frames show no row) or
/// "fails" (the window is listed, but its capture fails, as a minimised one gives no frame).
fn window_tool(dir: &Path, window: &str) -> (PathBuf, PathBuf) {
    let tool = dir.join("tool");
    let log = dir.join("calls.log");
    let frame = frame_file(dir);
    // a frame of the window with no row in it: a loading screen
    let blank = dir.join("blank.bin");
    let mut data = b"HLC1".to_vec();
    data.extend(2560u32.to_le_bytes());
    data.extend(4u32.to_le_bytes());
    data.extend(vec![0u8; 2560 * 4 * 4]);
    fs::write(&blank, data).unwrap();
    let blank_stream = format!("[ \"$1\" = stream ] && exec cat '{}'", blank.display());
    let (refuse, fails) = match window {
        "none" => ("exit 3", String::new()),
        "fails" => ("", "[ \"$1\" = stream ] && exit 2".to_string()),
        "blank" => ("", blank_stream),
        _ => ("", String::new()),
    };
    executable(
        &tool,
        &format!(
            "#!/bin/sh\necho \"$*\" >> '{}'\nif [ \"$1\" = --window ]; then {refuse}\n  [ \"$2\" = Wow ] || exit 3; shift 2; {fails}\nfi\ncase \"$1\" in list) printf '0 2560 4\\n' ;; stream) cat '{frame}' ;; *) exit 1 ;; esac\n",
            log.display()
        ),
    );
    (tool, log)
}

#[test]
fn the_search_reads_the_games_window_first() {
    // the owner, 23 Nov 2026: the capture takes the game's window, so that another window over
    // the game does not hide the row
    let dir = folder("window-first");
    let (tool, log) = window_tool(&dir, "ok");
    let got = hellolink::capture::locate(&tool, hellolink::capture::Colour::Srgb, &mut |_| {});
    assert!(
        matches!(got, Ok(Ok((-1, 2560, _)))),
        "the row is found in the game's window, display -1 ({got:?})"
    );
    let calls = fs::read_to_string(&log).unwrap();
    assert!(
        calls.lines().next() == Some("--window Wow list")
            && calls
                .lines()
                .any(|l| l.starts_with("--window Wow stream 0 0 0 2560")),
        "the game's window is listed, then read: {calls}"
    );
    assert!(
        !calls.lines().any(|l| l == "list"),
        "no display is listed when the window shows the row: {calls}"
    );
    // the place found carries its source to the stream (review of #316: no flag beside it)
    let command = hellolink::capture::Colour::Srgb.stream(&tool, &[-1, 0, 0, 2560, 6, 60]);
    assert_eq!(
        command[1..],
        [
            "--window", "Wow", "stream", "0", "0", "0", "2560", "6", "60"
        ],
        "the stream of a place in the window takes the window"
    );
    let command = hellolink::capture::Colour::Srgb.stream(&tool, &[1, 0, 0, 2560, 6, 60]);
    assert_eq!(
        command[1..],
        ["stream", "1", "0", "0", "2560", "6", "60"],
        "the stream of a place on a display takes the display"
    );
}

#[test]
fn with_no_game_window_the_search_reads_the_displays() {
    let dir = folder("window-none");
    let (tool, log) = window_tool(&dir, "none");
    let got = hellolink::capture::locate(&tool, hellolink::capture::Colour::Srgb, &mut |_| {});
    assert!(
        matches!(got, Ok(Ok((0, 2560, _)))),
        "the row is found on display 0 ({got:?})"
    );
    let calls = fs::read_to_string(&log).unwrap();
    assert!(
        calls.lines().any(|l| l == "list")
            && calls.lines().any(|l| l.starts_with("stream 0 0 0 2560")),
        "the displays are listed and read, with no --window: {calls}"
    );
}

#[test]
fn a_window_whose_capture_fails_leaves_the_search_to_the_displays() {
    // review of #316: a failed capture of the window (a minimised one gives no frame) is no
    // reason to stop looking
    let dir = folder("window-fails");
    let (tool, log) = window_tool(&dir, "fails");
    let got = hellolink::capture::locate(&tool, hellolink::capture::Colour::Srgb, &mut |_| {});
    assert!(
        matches!(got, Ok(Ok((0, 2560, _)))),
        "the row is found on display 0 after the window failed ({got:?})"
    );
    let calls = fs::read_to_string(&log).unwrap();
    assert!(
        calls.lines().any(|l| l.starts_with("--window Wow stream"))
            && calls.lines().any(|l| l == "list"),
        "the window was tried, then the displays: {calls}"
    );
}

#[test]
fn a_window_that_shows_no_row_is_looked_at_again_not_the_displays() {
    // 23 Nov 2026, at two /reloads, the search turned to a display that showed the row a moment
    // later, and the reader stayed there; the window's frames had most likely no row (a loading
    // screen, not recorded)
    let dir = folder("window-blank");
    let (tool, log) = window_tool(&dir, "blank");
    let got = hellolink::capture::locate(&tool, hellolink::capture::Colour::Srgb, &mut |_| {});
    assert!(
        matches!(&got, Ok(Err(why)) if why.contains("game's window")),
        "no row in the game's window: no row this search ({got:?})"
    );
    let calls = fs::read_to_string(&log).unwrap();
    assert!(
        !calls
            .lines()
            .any(|l| l == "list" || l.starts_with("stream ")),
        "the displays are not looked at: {calls}"
    );
}

#[test]
fn a_window_with_no_row_is_tried_five_searches_then_the_displays_once() {
    // review of #321: a window that never shows the row must not hold the reader from a display
    use hellolink::capture::{Found, NO_ROW_IN_WINDOW, WINDOW_TRIES, next_blank, window_first};
    type Searched = Result<Result<Found, String>, String>;
    let no_row: Searched = Ok(Err(NO_ROW_IN_WINDOW.into()));
    let mut blank = 0;
    let mut firsts = vec![];
    for _ in 0..WINDOW_TRIES + 1 {
        firsts.push(window_first(true, blank));
        blank = next_blank(blank, &no_row);
    }
    assert_eq!(
        firsts,
        [true, true, true, true, true, false],
        "five searches in the window, then one on the displays"
    );
    let elsewhere: Searched = Ok(Err("no row on any display".into()));
    assert_eq!(next_blank(blank, &elsewhere), 0, "then the window again");
    assert!(!window_first(false, 0), "never with --display");
}

// --- #348: the game's process, by `pgrep -f` ---

#[test]
fn process_runs_finds_a_running_process_and_not_a_missing_one() {
    // a process of its own: macOS's pgrep leaves out its own ancestors, so not this test
    let game = Game::start();
    assert_eq!(
        hellolink::capture::process_runs(&game.pattern),
        Ok(true),
        "pgrep finds a running process ({})",
        game.pattern
    );
    assert_eq!(
        hellolink::capture::process_runs("no-such-process-c1d2e3f4"),
        Ok(false),
        "pgrep finds no process of a name nobody runs"
    );
}

#[test]
fn a_game_that_ends_during_the_search_leaves_the_displays_unread() {
    // #348, review round 1: a game that quits closes its window before its process ends; the
    // search finds no window then, and asks again before it would read a display
    let dir = folder("window-game-ended");
    let (tool, log) = window_tool(&dir, "none");
    let got = hellolink::capture::locate_in(
        &tool,
        hellolink::capture::Colour::Srgb,
        true,
        &mut || false,
        &mut |_| {},
    );
    assert_eq!(
        got,
        Ok(Err(hellolink::capture::NO_GAME.to_string())),
        "with no game by then, the search ends without a display"
    );
    let calls = fs::read_to_string(&log).unwrap();
    assert!(
        calls.lines().all(|l| l.starts_with("--window Wow ")),
        "only the game's window was asked for, no display listed or read: {calls}"
    );
}

#[test]
fn a_game_that_ends_while_the_displays_are_listed_leaves_them_unread() {
    // review of #349, round 2: the list of the displays may wait seconds; each capture of a
    // display asks again
    let dir = folder("display-game-ended");
    let (tool, log) = window_tool(&dir, "none");
    let mut asked = 0;
    let got = hellolink::capture::locate_in(
        &tool,
        hellolink::capture::Colour::Srgb,
        true,
        &mut || {
            asked += 1;
            asked == 1 // runs when the displays are listed, then ends
        },
        &mut |_| {},
    );
    assert_eq!(
        got,
        Ok(Err(hellolink::capture::NO_GAME.to_string())),
        "the search ends without a display read"
    );
    let calls = fs::read_to_string(&log).unwrap();
    assert!(
        calls.lines().any(|l| l == "list") && !calls.lines().any(|l| l.starts_with("stream")),
        "the displays were listed, none was read: {calls}"
    );
}
