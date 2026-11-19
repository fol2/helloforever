//! The checks of tests/strip_record_test.py on the Recorder's lines. Each assert's message is
//! the Python check's name. The checks through the command line (`watch --record`, the slow
//! fall-back) are not here (step 2b).

mod common;

use common::*;
use hellolink::bitmap::Bitmap;
use hellolink::record::Recorder;
use hellolink::strip1::{bytes_to_squares, read_row, squares_to_bytes};
use hellolink::watch::Watcher;
use serde_json::{Value, json};
use std::fs;
use std::path::Path;

fn lines(path: &Path) -> Vec<Value> {
    fs::read_to_string(path)
        .unwrap()
        .lines()
        .map(|l| serde_json::from_str(l).unwrap())
        .collect()
}

fn hex(data: &[u8]) -> String {
    data.iter().map(|b| format!("{b:02x}")).collect()
}

/// The `shot` of tests/strip_record_test.py: session 4711, `width` of the 2560 columns.
fn shot(
    frame: &[u8],
    levels: [Option<f64>; 4],
    depth: u8,
    bend: Option<Bend>,
    width: usize,
) -> Bitmap {
    bitmap(&capture(4711, depth, levels, frame, bend, width), width)
}

/// A capture through the Watcher with the record noting its row, as `on_row` does.
fn feed(w: &mut Watcher, rec: &mut Recorder, image: &Bitmap, now: f64) -> Vec<Value> {
    let row = read_row(image, w.hint);
    rec.note(row.as_ref(), now).unwrap();
    w.feed_row(row, now)
}

#[test]
fn the_recorder_on_the_watcher_capture_by_capture() {
    let dir = Path::new(env!("CARGO_TARGET_TMPDIR")).join("record-test");
    let _ = fs::remove_dir_all(&dir);
    fs::create_dir_all(&dir).unwrap();
    let path = dir.join("play.jsonl");
    let palette: Vec<Value> = (0..64)
        .map(|i| json!([85 * (i / 16), 85 * (i / 4 % 4), 85 * (i % 4)]))
        .collect();
    let darker_palette: Vec<Value> = (0..64)
        .map(|i: i32| {
            json!([
                (85 * (i / 16) - 6).max(0),
                (85 * (i / 4 % 4) - 6).max(0),
                (85 * (i % 4) - 6).max(0)
            ])
        })
        .collect();
    let (one, two) = (frame(1), frame(2));
    let mut bad = two.clone();
    bad[8] ^= 0x01; // a byte of the fast block read wrong: the check fails
    let half = [Some(0.5), Some(1.0), None, None];

    let mut w = Watcher::default();
    let mut rec = Recorder::new(&path, Some(1794516378.25)).unwrap();
    let captures = [
        shot(&one, LEVELS, 4, None, WIDE),
        shot(&one, LEVELS, 4, None, WIDE),
        shot(&one, half, 4, None, WIDE),
        shot(&two, LEVELS, 4, None, WIDE),
        shot(&two, LEVELS, 4, Some(darker), WIDE),
        shot(&bad, LEVELS, 4, None, WIDE),
        shot(&bad, [Some(0.25), Some(1.0), None, None], 2, None, WIDE),
        shot(&two, LEVELS, 4, None, 300), // 149 squares: 58 of the frame, 43 bytes
        shot(&two, half, 4, None, 100),   // the palette cut short: no row, as before
        blank(),
    ];
    let mut events = vec![];
    for (i, image) in captures.iter().enumerate() {
        events.extend(feed(&mut w, &mut rec, image, 100.0 + i as f64 * 0.016));
    }
    drop(rec);
    let kinds: Vec<&str> = events.iter().filter_map(|e| e["kind"].as_str()).collect();
    assert_eq!(
        kinds[..3],
        ["state", "levels", "state"],
        "the Watcher's events are as without a record"
    );
    let got = lines(&path);
    let want = [
        json!({"record": 1, "started": 1794516378.25}),
        json!({"t": 0.0, "frame": hex(&one), "depth": 4, "levels": [76, 100, null, null], "palette": palette}),
        json!({"t": 0.016}),
        json!({"t": 0.032, "levels": [50, 100, null, null]}),
        json!({"t": 0.048, "frame": hex(&two), "levels": [76, 100, null, null]}),
        json!({"t": 0.064, "palette": darker_palette}),
        json!({"t": 0.08, "why": "frame check failed", "bad": hex(&bad), "palette": palette}),
        json!({"t": 0.096, "why": "frame check failed",
               "bad": hex(&squares_to_bytes(&bytes_to_squares(&bad, 3), 3, bad.len())),
               "depth": 2, "levels": [25, 100, null, null]}),
        json!({"t": 0.112, "why": "the row runs off the image", "bad": hex(&two[..43]), "depth": 4,
               "levels": [76, 100, null, null]}),
        json!({"t": 0.128, "why": "no row"}),
        json!({"t": 0.144, "why": "no row"}),
    ];
    assert_eq!(got.len(), want.len(), "a header and one line a capture");
    for (i, (g, w)) in got.iter().zip(&want).enumerate() {
        assert_eq!(g, w, "line {i} is whole and right");
    }

    // A record continues the file: two runs, two headers.
    let mut rec = Recorder::new(&path, Some(1794516400.0)).unwrap();
    let mut w2 = Watcher::default();
    feed(&mut w2, &mut rec, &shot(&one, LEVELS, 4, None, WIDE), 7.0);
    drop(rec);
    let headers = lines(&path).iter().filter(|l| l["record"] == 1).count();
    assert_eq!(
        headers, 2,
        "a second run appends to the file with a header of its own"
    );
    fs::remove_dir_all(&dir).unwrap();
}
