//! Parity of the Watcher and the Recorder with the Python ones, without Python: each sequence
//! of tests/watch/ (written by reader/tests/watch_parity.py, which says what a step is) is fed
//! to a Watcher with a Recorder. Every event must be the line Python wrote, byte for byte, and
//! the record the file Python's Recorder wrote.

mod common;

use common::*;
use hellolink::bitmap::{Bitmap, render};
use hellolink::record::Recorder;
use hellolink::rows::dumps;
use hellolink::strip1::read_row;
use hellolink::watch::Watcher;
use serde_json::Value;
use std::fs;
use std::path::{Path, PathBuf};

const STARTED: f64 = 1794516378.25;

fn image(step: &Value, fixtures: &Path) -> Bitmap {
    if step.get("blank").is_some() {
        return blank();
    }
    if let Some(cells) = step["cells"].as_str() {
        let text = fs::read_to_string(fixtures.join(cells)).unwrap();
        let scale = step["scale"].as_f64().unwrap();
        return Bitmap::new(&render(&text, scale, 0, 0, 2560, 12).unwrap()).unwrap();
    }
    let s = &step["shot"];
    let levels: Vec<Option<f64>> = s["levels"]
        .as_array()
        .unwrap()
        .iter()
        .map(Value::as_f64)
        .collect();
    let frame: Vec<u8> = (0..s["frame"].as_str().unwrap().len() / 2)
        .map(|i| u8::from_str_radix(&s["frame"].as_str().unwrap()[2 * i..2 * i + 2], 16).unwrap())
        .collect();
    let bend: Option<Bend> = match s["bend"].as_str() {
        None => None,
        Some("crush") => Some(crush),
        Some("darker") => Some(darker),
        Some(other) => panic!("unknown bend {other}"),
    };
    let width = s["width"].as_u64().unwrap() as usize;
    let raw = capture(
        s["session"].as_u64().unwrap() as u16,
        s["depth"].as_u64().unwrap() as u8,
        levels.try_into().unwrap(),
        &frame,
        bend,
        width,
    );
    bitmap(&raw, width)
}

#[test]
fn the_python_watchers_events_and_record() {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("tests");
    let dir = root.join("watch");
    let out = Path::new(env!("CARGO_TARGET_TMPDIR")).join("watch-parity");
    let _ = fs::remove_dir_all(&out);
    fs::create_dir_all(&out).unwrap();
    let mut names: Vec<String> = fs::read_dir(&dir)
        .unwrap()
        .filter_map(|e| {
            let name = e.unwrap().file_name().into_string().unwrap();
            name.strip_suffix(".steps.jsonl").map(String::from)
        })
        .collect();
    names.sort();
    assert!(names.len() >= 7, "the sequences are missing");
    let (mut steps_fed, mut events_compared) = (0, 0);
    for name in &names {
        let steps = fs::read_to_string(dir.join(format!("{name}.steps.jsonl"))).unwrap();
        let path = out.join(format!("{name}.record.jsonl"));
        let mut record = Recorder::new(&path, Some(STARTED)).unwrap();
        let mut w = Watcher::default();
        let mut got = String::new();
        for (i, line) in steps.lines().enumerate() {
            let step: Value = serde_json::from_str(line).unwrap();
            let t = step["t"].as_f64().unwrap();
            let events = if step.get("idle").is_some() {
                w.idle(t)
            } else {
                let row = read_row(&image(&step, &root.join("fixtures")), w.hint);
                record.note(row.as_ref(), t).unwrap();
                w.feed_row(row, t)
            };
            for e in &events {
                got += &format!("{i} {}\n", dumps(e));
            }
            steps_fed += 1;
            events_compared += events.len();
        }
        drop(record);
        let want = fs::read_to_string(dir.join(format!("{name}.events"))).unwrap();
        for (n, (g, w)) in got.lines().zip(want.lines()).enumerate() {
            assert_eq!(g, w, "{name}: event {n}");
        }
        assert_eq!(
            got.lines().count(),
            want.lines().count(),
            "{name}: the number of events"
        );
        let want = fs::read_to_string(dir.join(format!("{name}.record.jsonl"))).unwrap();
        let got = fs::read_to_string(&path).unwrap();
        for (n, (g, w)) in got.lines().zip(want.lines()).enumerate() {
            assert_eq!(g, w, "{name}: record line {n}");
        }
        assert_eq!(got, want, "{name}: the record");
    }
    fs::remove_dir_all(&out).unwrap();
    println!(
        "{} sequences, {steps_fed} steps, {events_compared} events: all equal",
        names.len()
    );
}
