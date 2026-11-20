//! `hellolink watch` as a program: its arguments, Ctrl-C, and what a stream's end says. The
//! capture tool is the fake one, on a script (src/bin/fake_capture.rs).

use std::fs;
use std::io::Read;
use std::path::{Path, PathBuf};
use std::process::{Child, Command, Stdio};
use std::sync::mpsc::{self, Receiver};
use std::thread;
use std::time::{Duration, Instant};

const READER: &str = env!("CARGO_BIN_EXE_hellolink");
const FAKE: &str = env!("CARGO_BIN_EXE_fake_capture");

fn folder(name: &str) -> PathBuf {
    let dir = Path::new(env!("CARGO_TARGET_TMPDIR")).join(format!("cli-{name}"));
    let _ = fs::remove_dir_all(&dir);
    fs::create_dir_all(&dir).unwrap();
    dir
}

fn running(pid: u32) -> bool {
    Command::new("kill")
        .args(["-0", &pid.to_string()])
        .stderr(Stdio::null())
        .status()
        .is_ok_and(|s| s.success())
}

/// `hellolink watch --json --capture FAKE` on `script`, its stdout read as it comes.
struct Watch {
    child: Child,
    state: PathBuf,
    out: Receiver<Vec<u8>>,
    seen: Vec<u8>,
}

impl Watch {
    fn start(name: &str, script: &str) -> Watch {
        Watch::with(name, script, &["--capture", FAKE], &[], true)
    }

    /// `hellolink watch --json ARGS` with ENV added; with `read`, its stdout is read as it
    /// comes, else never. stderr goes to STATE/err.
    fn with(name: &str, script: &str, args: &[&str], env: &[(&str, String)], read: bool) -> Watch {
        let state = folder(name);
        fs::write(state.join("script"), script).unwrap();
        let mut child = Command::new(READER)
            .args(["watch", "--json"])
            .args(args)
            .env("HELLOLINK_FAKE_SCRIPT", state.join("script"))
            .env("HELLOLINK_FAKE_STATE", &state)
            .envs(env.iter().map(|(k, v)| (k, v)))
            .stdout(Stdio::piped())
            .stderr(fs::File::create(state.join("err")).unwrap())
            .spawn()
            .unwrap();
        let (tx, out) = mpsc::channel();
        let stdout = child.stdout.take().unwrap();
        if read {
            let mut stdout = stdout;
            thread::spawn(move || {
                let mut buf = [0; 4096];
                while let Ok(n) = stdout.read(&mut buf) {
                    if n == 0 || tx.send(buf[..n].to_vec()).is_err() {
                        return;
                    }
                }
            });
        } else {
            // never read: the pipe fills; it is closed with the test
            thread::spawn(move || {
                let _held = stdout;
                let _tx = tx;
                thread::sleep(Duration::from_secs(60));
            });
        }
        Watch {
            child,
            state,
            out,
            seen: vec![],
        }
    }

    /// SIGINT, then up to `seconds` for the end: its status, None when it did not end.
    fn interrupt(&mut self, seconds: f64) -> Option<std::process::ExitStatus> {
        Command::new("kill")
            .args(["-INT", &self.child.id().to_string()])
            .status()
            .unwrap();
        let end = Instant::now() + Duration::from_secs_f64(seconds);
        loop {
            if let Some(status) = self.child.try_wait().unwrap() {
                return Some(status);
            }
            if Instant::now() > end {
                return None;
            }
            thread::sleep(Duration::from_millis(20));
        }
    }

    /// Waits up to `seconds` for `text` in the output; the output so far.
    fn until(&mut self, text: &str, seconds: f64) -> Result<String, String> {
        let end = Instant::now() + Duration::from_secs_f64(seconds);
        loop {
            let seen = String::from_utf8_lossy(&self.seen).into_owned();
            if seen.contains(text) {
                return Ok(seen);
            }
            let left = end.saturating_duration_since(Instant::now());
            match self.out.recv_timeout(left) {
                Ok(bytes) => self.seen.extend(bytes),
                Err(_) => return Err(format!("no {text:?} in {seconds} s; the output:\n{seen}")),
            }
        }
    }

    /// The process ids of the capture's runs.
    fn captures(&self) -> Vec<u32> {
        fs::read_to_string(self.state.join("pids"))
            .unwrap_or_default()
            .lines()
            .map(|l| l.parse().unwrap())
            .collect()
    }
}

impl Drop for Watch {
    fn drop(&mut self) {
        let _ = self.child.kill();
        let _ = self.child.wait();
        for pid in self.captures() {
            let _ = Command::new("kill")
                .args(["-KILL", &pid.to_string()])
                .status();
        }
        let _ = fs::remove_dir_all(&self.state);
    }
}

#[test]
fn ctrl_c_stops_the_capture_and_ends_cleanly() {
    let mut w = Watch::start("ctrl-c", "list 0 2560 4\nstream 1\nstream 1 2 hold\n");
    w.until("\"seq\": 2", 30.0).unwrap();
    let capture = *w.captures().last().unwrap();
    Command::new("kill")
        .args(["-INT", &w.child.id().to_string()])
        .status()
        .unwrap();
    let end = Instant::now() + Duration::from_secs(8);
    let status = loop {
        if let Some(status) = w.child.try_wait().unwrap() {
            break Some(status);
        }
        if Instant::now() > end {
            break None;
        }
        thread::sleep(Duration::from_millis(20));
    };
    assert!(
        status.is_some_and(|s| s.success()),
        "Ctrl-C ends watch within 8 s, cleanly, as Python's KeyboardInterrupt (got {status:?})"
    );
    assert!(
        !running(capture),
        "... and the capture it was streaming from is stopped, not left running"
    );
}

#[test]
fn a_capture_that_failed_while_the_stream_was_left_is_a_failure() {
    // Two frames with no row ask for a new search; by then the capture has ended with exit 7.
    // It is a race: under load (CI, 20 Nov 2026) the reader left the stream before the capture
    // ended, and stopping it is no failure. So the case runs up to three times, and one run that
    // ends as meant passes; a reader that never reports the failure still fails.
    let mut runs = Vec::new();
    for n in 0..3 {
        let mut w = Watch::start(
            &format!("left-failed-{n}"),
            "list 0 2560 4\nstream 1\nstream 1 2 tiny tiny err=gone exit=7\n",
        );
        let seen = w.until("fake: done", 30.0).unwrap();
        if seen
            .contains(r#"{"kind": "waiting", "why": "the capture stream does not answer (gone)"}"#)
        {
            return;
        }
        runs.push(seen);
    }
    panic!(
        "a stream left for a new search whose capture had failed says so, with its reason, \
         in one run of three ({runs:?})"
    );
}

fn watch(args: &[&str], dir: &Path) -> (bool, String, String) {
    let out = Command::new(READER)
        .arg("watch")
        .args(args)
        .current_dir(dir)
        .output()
        .unwrap();
    let text = |b: &[u8]| String::from_utf8_lossy(b).into_owned();
    (out.status.success(), text(&out.stdout), text(&out.stderr))
}

#[test]
fn an_option_without_its_value_is_refused() {
    let dir = folder("missing");
    let (ok, _, err) = watch(&["--remember", "--json", "--fps", "0"], &dir);
    assert!(
        !ok && err.contains("--remember") && !dir.join("--json").exists(),
        "an option without its value is refused before anything is done, as argparse does ({err})"
    );
    let (ok, _, err) = watch(&["--fps"], &dir);
    assert!(!ok && err.contains("--fps"), "... also at the end ({err})");
    fs::remove_dir_all(&dir).unwrap();
}

#[test]
fn watch_help() {
    let dir = folder("help");
    for flag in ["--help", "-h"] {
        let (ok, out, _) = watch(&[flag], &dir);
        assert!(
            ok && out.contains("--record") && out.contains("--remember"),
            "watch {flag} prints the options and ends cleanly ({out})"
        );
    }
    fs::remove_dir_all(&dir).unwrap();
}

// --- review round 2 of #198 ---

#[test]
fn a_child_of_the_stream_outside_its_group_is_reported() {
    // two frames with no row ask for a new search; the capture left a child, in a process
    // group of its own, that keeps its output open
    let mut w = Watch::start(
        "escape",
        "list 0 2560 4\nstream 1\nstream 1 2 escape=30 tiny tiny hold\n",
    );
    let end = Instant::now() + Duration::from_secs(40);
    let status = loop {
        match w.child.try_wait().unwrap() {
            Some(status) => break Some(status),
            None if Instant::now() > end => break None,
            None => thread::sleep(Duration::from_millis(50)),
        }
    };
    let err = fs::read_to_string(w.state.join("err")).unwrap_or_default();
    assert!(
        status.is_some_and(|s| !s.success()) && err.contains("kept its output open"),
        "a stream whose capture left a child outside its group with its output open ends watch with a failure that says so: a reader thread is left at most once a run, not once a try (got {status:?}; stderr: {err})"
    );
}

#[test]
fn ctrl_c_while_stdout_is_full() {
    let frames: Vec<String> = (1..=400).map(|n| n.to_string()).collect();
    let script = format!(
        "list 0 2560 4\nstream 1\nstream {} hold\n",
        frames.join(" ")
    );
    let mut w = Watch::with("full", &script, &["--capture", FAKE], &[], false);
    // the stream has started, and its states have filled the pipe that nobody reads
    let end = Instant::now() + Duration::from_secs(30);
    while w.captures().len() < 3 && Instant::now() < end {
        thread::sleep(Duration::from_millis(50));
    }
    thread::sleep(Duration::from_secs(4));
    let capture = *w.captures().last().unwrap();
    let status = w.interrupt(8.0);
    assert!(
        status.is_some_and(|s| s.success()),
        "Ctrl-C while nobody reads stdout still ends watch within 8 s, cleanly (got {status:?})"
    );
    assert!(!running(capture), "... and stops its capture");
}

#[test]
fn ctrl_c_while_the_capture_tool_is_built() {
    let dir = folder("build-bin");
    let script = |name: &str, body: &str| {
        let path = dir.join(name);
        crate::common::executable(&path, &format!("#!/bin/sh\n{body}\n"));
    };
    script("swiftc", "exec sleep 60");
    script(
        "screencapture",
        "touch \"$HELLOLINK_TEST_MARK\"\nexec sleep 60",
    );
    let home = folder("build-home");
    let mark = home.join("screencapture-ran");
    let env = [
        ("HOME", home.to_string_lossy().into_owned()),
        ("PATH", format!("{}:/usr/bin:/bin", dir.display())),
        ("HELLOLINK_TEST_MARK", mark.to_string_lossy().into_owned()),
    ];
    let mut w = Watch::with("build", "", &[], &env, true);
    w.until("looking for the row", 10.0).unwrap();
    thread::sleep(Duration::from_millis(1500)); // swiftc is running
    let status = w.interrupt(8.0);
    let err = fs::read_to_string(w.state.join("err")).unwrap_or_default();
    assert!(
        status.is_some_and(|s| s.success())
            && !mark.exists()
            && !err.contains("one screencapture a frame"),
        "Ctrl-C while the capture tool is built ends watch cleanly, before the fall-back starts screencapture (got {status:?}; stderr: {err})"
    );
}

#[test]
fn watch_serves_the_api_and_asks_through_the_slots() {
    let addons = folder("serve-addons");
    for i in 1..=2 {
        let slot = addons.join(format!("HelloLink_S{i:03}"));
        fs::create_dir_all(&slot).unwrap();
        fs::write(
            slot.join("Inbox.lua"),
            hellolink::slots::inbox_file(0, "", 2, None, None, 0),
        )
        .unwrap();
    }
    let port = std::net::TcpListener::bind("127.0.0.1:0")
        .unwrap()
        .local_addr()
        .unwrap()
        .port();
    let crushed: Vec<String> = (2..=40).map(|n| format!("{n}:crush")).collect();
    let script = format!(
        "list 0 2560 4\nstream 1\nstream 1 {} hold\n",
        crushed.join(" ")
    );
    let (port_s, dir) = (port.to_string(), addons.to_string_lossy().into_owned());
    let mut w = Watch::with(
        "serve",
        &script,
        &["--capture", FAKE, "--serve", &port_s, "--addons", &dir],
        &[],
        true,
    );
    let printed = w.until("\"kind\": \"ask\"", 30.0).unwrap();
    // every complete line, an empty one too, up to the request
    for line in printed.split_inclusive('\n').filter(|l| l.ends_with('\n')) {
        assert!(
            serde_json::from_str::<serde_json::Value>(line.trim_end_matches('\n')).is_ok(),
            "a quiet write prints nothing (the reader's own output stays clean JSON): {line:?}"
        );
    }
    // stderr has a writer thread of its own: its note may come after the stdout line
    let asked = "asked the strip of session 4711 to fall back to 3 bits a square";
    let end = Instant::now() + Duration::from_secs(5);
    let mut err = String::new();
    while Instant::now() < end && !err.contains(asked) {
        thread::sleep(Duration::from_millis(50));
        err = fs::read_to_string(w.state.join("err")).unwrap_or_default();
    }
    assert!(
        err.contains(&format!(
            "the local API is at http://127.0.0.1:{port} (GET /state, GET /events)"
        )) && err.contains("asked the strip of session 4711 to fall back to 3 bits a square"),
        "it says where the API is, and that it asked ({err})"
    );
    assert!(
        (1..=2).all(
            |i| fs::read_to_string(addons.join(format!("HelloLink_S{i:03}/Inbox.lua")))
                .unwrap()
                .contains("strip = { session = 4711, depth = 2 }")
        ),
        "the request is in every slot"
    );
    let mut s = std::net::TcpStream::connect(("127.0.0.1", port)).unwrap();
    use std::io::Write;
    write!(s, "GET /state HTTP/1.1\r\nHost: localhost:{port}\r\n\r\n").unwrap();
    let mut answer = String::new();
    s.read_to_string(&mut answer).unwrap();
    assert!(
        answer.starts_with("HTTP/1.0 200 OK") && answer.contains("\"session\": 4711"),
        "/state has the state watch read ({answer})"
    );
    let status = w.interrupt(8.0);
    assert!(
        status.is_some_and(|s| s.success()),
        "Ctrl-C ends it cleanly ({status:?})"
    );
    assert!(
        std::net::TcpStream::connect(("127.0.0.1", port)).is_err(),
        "... and frees the port"
    );
}

#[test]
fn ctrl_c_while_the_slots_are_locked() {
    let addons = folder("locked-addons");
    let slot = addons.join("HelloLink_S001");
    fs::create_dir_all(&slot).unwrap();
    fs::write(
        slot.join("Inbox.lua"),
        hellolink::slots::inbox_file(0, "", 1, None, None, 0),
    )
    .unwrap();
    let held = fs::File::create(slot.join(".lock")).unwrap();
    held.lock().unwrap(); // another writer holds the slots
    let crushed: Vec<String> = (2..=40).map(|n| format!("{n}:crush")).collect();
    let script = format!(
        "list 0 2560 4\nstream 1\nstream 1 {} hold\n",
        crushed.join(" ")
    );
    let dir = addons.to_string_lossy().into_owned();
    let mut w = Watch::with(
        "locked",
        &script,
        &["--capture", FAKE, "--addons", &dir],
        &[],
        true,
    );
    w.until("\"kind\": \"state\"", 30.0).unwrap();
    thread::sleep(Duration::from_secs(2)); // the request waits for the lock
    let status = w.interrupt(5.0);
    let err = fs::read_to_string(w.state.join("err")).unwrap_or_default();
    assert!(
        status.is_some_and(|s| s.success()) && !err.contains("held it"),
        "Ctrl-C while the request waits for the slots' lock ends watch cleanly, at once (got {status:?}; stderr: {err})"
    );
}
