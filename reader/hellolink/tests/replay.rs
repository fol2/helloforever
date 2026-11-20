//! `hellolink replay`: a record of `watch --record` (docs/STRIP.md, section 10) back into the
//! events `watch --json` said, each with its time `t` (#213, step 5). The frames come from the
//! committed vectors (tests/vectors/strip1.json), not from this crate's encoder.

use hellolink::replay::replay;
use serde_json::{Value, json};
use std::path::PathBuf;
use std::process::Command;

fn vector() -> Value {
    let top = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../..");
    serde_json::from_str(&std::fs::read_to_string(top.join("tests/vectors/strip1.json")).unwrap())
        .unwrap()
}

fn run(record: &str) -> Result<Vec<Value>, String> {
    let mut out = Vec::new();
    replay(record.as_bytes(), &mut out)?;
    Ok(String::from_utf8(out)
        .unwrap()
        .lines()
        .map(|l| serde_json::from_str(l).unwrap())
        .collect())
}

fn kinds(events: &[Value], kind: &str) -> Vec<Value> {
    events
        .iter()
        .filter(|e| e["kind"] == kind)
        .cloned()
        .collect()
}

/// A record: its header, then the lines given.
fn record(lines: &[Value]) -> String {
    let mut text = String::from("{\"record\":1,\"started\":1795189523.0}\n");
    for l in lines {
        text += &format!("{l}\n");
    }
    text
}

#[test]
fn the_vectors_frames_give_their_state_and_objects() {
    let v = vector();
    let mut lines =
        vec![json!({"t": 0.0, "frame": v["frame"], "depth": 4, "levels": [76, 100, null, 50]})];
    for (i, o) in v["objects"].as_array().unwrap().iter().enumerate() {
        lines.push(json!({"t": 0.1 * (i + 1) as f64, "frame": o["frame"]}));
    }
    let events = run(&record(&lines)).unwrap();
    let states = kinds(&events, "state");
    assert_eq!(states.len(), lines.len(), "one state a new seq");
    assert_eq!(states[0]["session"], v["session"]);
    assert_eq!(states[0]["seq"], v["seq"]);
    assert_eq!(states[0]["depth"], 4);
    assert_eq!(states[0]["fast"], v["state"]);
    assert_eq!(states[0]["t"], 0.0);
    assert_eq!(
        states[0]["levels"],
        json!({"health": 76, "power": 100, "targetHealth": null, "petHealth": 50})
    );
    let mut want = vec![
        json!({"id": v["object"]["id"], "format": v["object"]["format"], "text": v["object"]["text"]}),
    ];
    for o in v["objects"].as_array().unwrap() {
        want.push(json!({"id": o["id"], "format": o["format"], "text": o["text"]}));
    }
    let got: Vec<Value> = kinds(&events, "object")
        .iter()
        .map(|e| json!({"id": e["id"], "format": e["format"], "text": e["text"]}))
        .collect();
    assert_eq!(got, want);
    assert_eq!(kinds(&events, "object")[1]["t"], 0.1);
}

#[test]
fn a_capture_with_no_change_repeats_the_frame_and_levels_alone_are_a_levels_event() {
    let v = vector();
    let events = run(&record(&[
        json!({"t": 0.0, "frame": v["frame"], "depth": 4, "levels": [76, 100, null, 50]}),
        json!({"t": 0.05}),
        json!({"t": 0.1, "levels": [70, 100, null, 50]}),
        json!({"t": 0.15}),
    ]))
    .unwrap();
    assert_eq!(kinds(&events, "state").len(), 1, "no new seq");
    assert_eq!(
        kinds(&events, "object").len(),
        1,
        "the object is not said twice"
    );
    let levels = kinds(&events, "levels");
    assert_eq!(levels.len(), 1);
    assert_eq!(levels[0]["levels"]["health"], 70);
    assert_eq!(levels[0]["t"], 0.1);
}

#[test]
fn captures_with_no_frame_are_misses_and_a_new_run_starts_again() {
    let v = vector();
    let mut text = record(&[
        json!({"t": 0.0, "frame": v["frame"], "depth": 4, "levels": [76, 100, null, 50]}),
        json!({"t": 0.05, "why": "no row"}),
        json!({"t": 0.1, "why": "frame check failed", "bad": "0112"}),
    ]);
    // the reader started again, appending to the same file: the object is new to it
    text += &record(&[
        json!({"t": 0.0, "frame": v["frame"], "depth": 4, "levels": [76, 100, null, 50]}),
    ]);
    let events = run(&text).unwrap();
    let relocate = kinds(&events, "relocate");
    assert_eq!(
        relocate.len(),
        1,
        "two misses in a row ask for a new search"
    );
    assert_eq!(relocate[0]["why"], "frame check failed");
    assert_eq!(
        kinds(&events, "record").len(),
        2,
        "each run's header is said"
    );
    assert_eq!(kinds(&events, "object").len(), 2);
}

#[test]
fn a_line_that_is_not_a_record_line_is_refused_with_its_number() {
    let text = record(&[json!({"t": 0.0, "why": "no row"})]) + "not json\n";
    let err = run(&text).unwrap_err();
    assert!(err.contains("line 3"), "{err}");
    let err = run("{\"t\": 0.0}\n").unwrap_err();
    assert!(err.contains("line 1") && err.contains("header"), "{err}");
    let err = run(&record(&[json!({"t": 0.0, "frame": "zz"})])).unwrap_err();
    assert!(err.contains("line 2"), "{err}");
}

#[test]
fn the_command_reads_a_record_file() {
    let v = vector();
    let path = PathBuf::from(env!("CARGO_TARGET_TMPDIR")).join("replay-command.jsonl");
    std::fs::write(
        &path,
        record(&[
            json!({"t": 0.0, "frame": v["frame"], "depth": 4, "levels": [76, 100, null, 50]}),
        ]),
    )
    .unwrap();
    let out = Command::new(env!("CARGO_BIN_EXE_hellolink"))
        .args(["replay", path.to_str().unwrap()])
        .output()
        .unwrap();
    assert!(
        out.status.success(),
        "{}",
        String::from_utf8_lossy(&out.stderr)
    );
    let text = String::from_utf8(out.stdout).unwrap();
    assert!(
        text.lines().any(|l| l.contains("\"kind\": \"object\"")),
        "{text}"
    );
    let out = Command::new(env!("CARGO_BIN_EXE_hellolink"))
        .args(["replay", "/no/such/record"])
        .output()
        .unwrap();
    assert!(!out.status.success());
}
