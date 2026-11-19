//! Parity of `hellolink watch` with `hellolink_strip.py watch`, without Python: each script of
//! tests/stream/ is run by the fake capture tool (src/bin/fake_capture.rs) for the Rust
//! reader, and what the reader writes must be what the Python reader wrote on the same script
//! (reader/tests/stream_parity.sh wrote it): stdout and stderr, the capture tool's runs, the
//! record (its clock times masked) and the remembered place, byte for byte.

use std::fs;
use std::io::{BufRead, BufReader, Read};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::mpsc;
use std::thread;
use std::time::{Duration, Instant};

/// The run's end: the script is over.
const DONE: &str = "fake: done";
/// The limit of a run.
const RUN_WAIT: Duration = Duration::from_secs(60);

/// `"t"` and `"started"` hold clock times: their values become T and S, as the script's sed.
fn masked(record: &str) -> String {
    let mask = |line: &str, key: &str, by: &str| match line.find(key) {
        Some(at) => {
            let from = at + key.len();
            let end = line[from..]
                .find([',', '}'])
                .map_or(line.len(), |n| from + n);
            format!("{}{by}{}", &line[..from], &line[end..])
        }
        None => line.to_string(),
    };
    record
        .lines()
        .map(|line| mask(&mask(line, "\"t\":", "T"), "\"started\":", "S") + "\n")
        .collect()
}

fn run(name: &str) {
    let dir = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("tests/stream");
    let script = dir.join(format!("{name}.script"));
    let text = fs::read_to_string(&script).unwrap();
    let state = Path::new(env!("CARGO_TARGET_TMPDIR")).join(format!("stream-parity-{name}"));
    let _ = fs::remove_dir_all(&state);
    fs::create_dir_all(&state).unwrap();
    let head = |key: &str| {
        text.lines()
            .find_map(|l| l.strip_prefix(key))
            .unwrap_or("")
            .to_string()
    };
    let (record, place) = (state.join("record"), state.join("place"));
    if !head("# place: ").is_empty() {
        fs::write(&place, head("# place: ")).unwrap();
    }
    let args: Vec<String> = head("# args: ")
        .split_whitespace()
        .map(|a| match a {
            "RECORD" => record.to_string_lossy().into_owned(),
            "PLACE" => place.to_string_lossy().into_owned(),
            a => a.to_string(),
        })
        .collect();
    let mut reader = Command::new(env!("CARGO_BIN_EXE_hellolink"))
        .args(["watch", "--capture", env!("CARGO_BIN_EXE_fake_capture")])
        .args(&args)
        .env("HELLOLINK_FAKE_SCRIPT", &script)
        .env("HELLOLINK_FAKE_STATE", &state)
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .unwrap();
    let (tx, lines) = mpsc::channel();
    let stdout = reader.stdout.take().unwrap();
    thread::spawn(move || {
        for line in BufReader::new(stdout).lines() {
            let Ok(line) = line else { return };
            if tx.send(line).is_err() {
                return;
            }
        }
    });
    let mut stderr = reader.stderr.take().unwrap();
    let errors = thread::spawn(move || {
        let mut all = String::new();
        let _ = stderr.read_to_string(&mut all);
        all
    });
    let (mut out, began) = (String::new(), Instant::now());
    loop {
        let left = RUN_WAIT.saturating_sub(began.elapsed());
        let Ok(line) = lines.recv_timeout(left) else {
            let _ = reader.kill();
            panic!("{name}: no \"{DONE}\" in {RUN_WAIT:?}; the output so far:\n{out}");
        };
        out += &line;
        out += "\n";
        if line.contains(DONE) {
            break;
        }
    }
    reader.kill().unwrap();
    reader.wait().unwrap();
    let err = errors.join().unwrap();
    let want = |ext: &str| fs::read_to_string(dir.join(format!("{name}.{ext}"))).ok();
    let compare = |what: &str, got: Option<String>, want: Option<String>| {
        if let (Some(got), Some(want)) = (&got, &want) {
            for (n, (g, w)) in got.lines().zip(want.lines()).enumerate() {
                assert_eq!(g, w, "{name}.{what}: line {n}");
            }
        }
        assert_eq!(got, want, "{name}.{what}, whole");
    };
    compare("out", Some(out), want("out"));
    compare("err", Some(err), want("err"));
    compare(
        "calls",
        fs::read_to_string(state.join("calls")).ok(),
        want("calls"),
    );
    compare(
        "record",
        fs::read_to_string(&record).ok().map(|r| masked(&r)),
        want("record"),
    );
    compare("place", fs::read_to_string(&place).ok(), want("place"));
    fs::remove_dir_all(&state).unwrap();
}

#[test]
fn the_python_readers_watch_on_the_basics() {
    run("basics");
}

#[test]
fn the_python_readers_watch_as_text() {
    run("text");
}

#[test]
fn the_python_readers_watch_from_a_remembered_place() {
    run("remembered");
}

#[test]
fn every_script_has_a_test() {
    let dir = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("tests/stream");
    let mut names: Vec<String> = fs::read_dir(dir)
        .unwrap()
        .filter_map(|e| {
            let name = e.unwrap().file_name().into_string().unwrap();
            name.strip_suffix(".script").map(String::from)
        })
        .collect();
    names.sort();
    assert_eq!(names, ["basics", "remembered", "text"]);
}
