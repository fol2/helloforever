//! Parity of `hellolink watch` with `hellolink_strip.py watch`, without Python: each script of
//! tests/stream/ is run by the fake capture tool (src/bin/fake_capture.rs) for the Rust
//! reader, and what the reader writes must be what the Python reader wrote on the same script
//! (reader/tests/stream_parity.sh wrote it): stdout and stderr, the capture tool's runs, the
//! record (its clock times masked) and the remembered place, byte for byte.

use std::fs;
use std::io::Read;
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
        .split_inclusive('\n')
        .map(|line| mask(&mask(line, "\"t\":", "T"), "\"started\":", "S"))
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
    // Both pipes are read in threads, as bytes; every wait below is within the run's limit.
    let pipe = |mut p: Box<dyn Read + Send>| {
        let (tx, rx) = mpsc::channel();
        thread::spawn(move || {
            let mut buf = [0; 4096];
            while let Ok(n) = p.read(&mut buf) {
                if n == 0 || tx.send(buf[..n].to_vec()).is_err() {
                    return;
                }
            }
        });
        rx
    };
    let out_rx = pipe(Box::new(reader.stdout.take().unwrap()));
    let err_rx = pipe(Box::new(reader.stderr.take().unwrap()));
    let end = Instant::now() + RUN_WAIT;
    let mut out = Vec::new();
    let done = loop {
        if out.windows(DONE.len()).any(|w| w == DONE.as_bytes()) {
            // the line that says it, whole
            if out.ends_with(b"\n") {
                break true;
            }
        }
        match out_rx.recv_timeout(end.saturating_duration_since(Instant::now())) {
            Ok(chunk) => out.extend(chunk),
            Err(_) => break false,
        }
    };
    let _ = reader.kill();
    let reaped = loop {
        if let Ok(Some(_)) = reader.try_wait() {
            break true;
        }
        if Instant::now() >= end + Duration::from_secs(5) {
            break false;
        }
        thread::sleep(Duration::from_millis(10));
    };
    // stderr to its end, within 2 s of the reap at most (one deadline, not one a chunk)
    let (mut err, err_end) = (Vec::new(), Instant::now() + Duration::from_secs(2));
    while let Ok(chunk) = err_rx.recv_timeout(err_end.saturating_duration_since(Instant::now())) {
        err.extend(chunk);
    }
    assert!(
        done,
        "{name}: no \"{DONE}\" in {RUN_WAIT:?}; the output so far:\n{}",
        String::from_utf8_lossy(&out)
    );
    assert!(
        reaped,
        "{name}: the reader was not reaped after it was killed"
    );
    let want = |ext: &str| fs::read(dir.join(format!("{name}.{ext}"))).ok();
    // As bytes: a line is compared first, for a message that shows it, then the whole file.
    let compare = |what: &str, got: Option<Vec<u8>>, want: Option<Vec<u8>>| {
        if let (Some(got), Some(want)) = (&got, &want) {
            for (n, (g, w)) in got
                .split(|b| *b == b'\n')
                .zip(want.split(|b| *b == b'\n'))
                .enumerate()
            {
                assert_eq!(
                    String::from_utf8_lossy(g),
                    String::from_utf8_lossy(w),
                    "{name}.{what}: line {n}"
                );
            }
        }
        assert!(got == want, "{name}.{what}, whole, as bytes");
    };
    compare("out", Some(out), want("out"));
    compare("err", Some(err), want("err"));
    compare("calls", fs::read(state.join("calls")).ok(), want("calls"));
    compare(
        "record",
        fs::read_to_string(&record)
            .ok()
            .map(|r| masked(&r).into_bytes()),
        want("record"),
    );
    compare("place", fs::read(&place).ok(), want("place"));
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
