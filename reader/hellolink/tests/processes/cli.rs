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
        let state = folder(name);
        fs::write(state.join("script"), script).unwrap();
        let mut child = Command::new(READER)
            .args(["watch", "--json", "--capture", FAKE])
            .env("HELLOLINK_FAKE_SCRIPT", state.join("script"))
            .env("HELLOLINK_FAKE_STATE", &state)
            .stdout(Stdio::piped())
            .stderr(Stdio::null())
            .spawn()
            .unwrap();
        let (tx, out) = mpsc::channel();
        let mut stdout = child.stdout.take().unwrap();
        thread::spawn(move || {
            let mut buf = [0; 4096];
            while let Ok(n) = stdout.read(&mut buf) {
                if n == 0 || tx.send(buf[..n].to_vec()).is_err() {
                    return;
                }
            }
        });
        Watch {
            child,
            state,
            out,
            seen: vec![],
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
    // two frames with no row ask for a new search; by then the capture has ended with exit 7
    let mut w = Watch::start(
        "left-failed",
        "list 0 2560 4\nstream 1\nstream 1 2 tiny tiny err=gone exit=7\n",
    );
    let seen = w.until("fake: done", 30.0).unwrap();
    assert!(
        seen.contains(r#"{"kind": "waiting", "why": "the capture stream does not answer (gone)"}"#),
        "a stream left for a new search whose capture had failed says so, with its reason ({seen})"
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
