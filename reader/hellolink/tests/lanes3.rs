//! Format 3 rows with lanes (docs/specs/232.md, part C, "Lanes"; section 6, the layout square):
//! the hand-written rows of tests/vectors/lanes3.json, as captured colours with the game before,
//! after and under them, read by the reader; a layout over 3 refused; the lanes in the rows line
//! and the record.

use hellolink::bitmap::Bitmap;
use hellolink::capture::Colour;
use hellolink::record::Recorder;
use hellolink::rows::row_line;
use hellolink::strip1::read_row;
use serde_json::{Value, json};

const BASE64: &str = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

fn vector() -> Value {
    let top = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../..");
    serde_json::from_str(&std::fs::read_to_string(top.join("tests/vectors/lanes3.json")).unwrap())
        .unwrap()
}

fn hex(s: &str) -> Vec<u8> {
    (0..s.len())
        .step_by(2)
        .map(|i| u8::from_str_radix(&s[i..i + 2], 16).unwrap())
        .collect()
}

fn colour(v: &Value) -> [u8; 3] {
    serde_json::from_value(v.clone()).unwrap()
}

fn digit(d: u64) -> [u8; 3] {
    [d >> 2 & 1, d >> 1 & 1, d & 1].map(|b| 255 * b as u8)
}

/// The frame's squares as colours: at 3 bits a digit a square, at 6 bits a base64 digit.
fn squares(case: &Value) -> Vec<[u8; 3]> {
    let codes = case["codes"].as_str().unwrap();
    if case["depth"] == 2 {
        return codes
            .chars()
            .map(|c| digit(c.to_digit(8).unwrap().into()))
            .collect();
    }
    let paint: Vec<u8> = serde_json::from_value(case["paint"].clone()).unwrap();
    codes
        .chars()
        .map(|c| {
            let n = BASE64.find(c).unwrap();
            [n >> 4, n >> 2 & 3, n & 3].map(|k| paint[k])
        })
        .collect()
}

/// The capture of a case: the row's head and lane 1 on line 1 from x = 40, lane k on line k
/// from x = 40 + `first`, 1 pixel a square; the game around it.
fn capture(v: &Value, case: &Value) -> Bitmap {
    let around: Vec<[u8; 3]> = v["around"].as_array().unwrap().iter().map(colour).collect();
    let mut head: Vec<[u8; 3]> = case["head"]
        .as_array()
        .unwrap()
        .iter()
        .map(|d| digit(d.as_u64().unwrap()))
        .collect();
    head.extend(case["ramp"].as_array().unwrap().iter().map(colour));
    head.extend(
        case["more"]
            .as_array()
            .unwrap()
            .iter()
            .map(|d| digit(d.as_u64().unwrap())),
    );
    let first = case["first"].as_u64().unwrap() as usize;
    assert_eq!(head.len(), first, "the head's squares");
    let (lanes, per) = (
        case["lanes"].as_u64().unwrap() as usize,
        case["per"].as_u64().unwrap() as usize,
    );
    let mut frame = squares(case);
    frame.extend([[0, 0, 0]; 4]); // black after the frame's end
    let width = 40 + first + per;
    let mut raw = Vec::new();
    for y in 0..lanes + 2 {
        for x in 0..width {
            let game = around[(x + 5 * y) % around.len()];
            let c = match (y, x) {
                (1, x) if (40..40 + first).contains(&x) => head[x - 40],
                (y, x) if (1..=lanes).contains(&y) && x >= 40 + first => {
                    let k = (y - 1) * per + x - 40 - first;
                    frame.get(k).copied().unwrap_or(game)
                }
                _ => game,
            };
            raw.extend([c[2], c[1], c[0], 255]);
        }
    }
    Bitmap::from_bgra(width, lanes + 2, &raw).unwrap()
}

#[test]
fn the_hand_written_lane_rows_read_as_written() {
    let v = vector();
    for case in v["cases"].as_array().unwrap() {
        let name = case["name"].as_str().unwrap();
        // the boundaries worked by hand are the squares of `codes` there
        let codes: Vec<char> = case["codes"].as_str().unwrap().chars().collect();
        for c in case["cross"].as_array().unwrap() {
            let at = c["at"].as_u64().unwrap() as usize;
            let as_written = |x: &Value| x.as_str().map_or_else(|| x.to_string(), String::from);
            assert_eq!(
                (codes[at - 1].to_string(), codes[at].to_string()),
                (as_written(&c["before"]), as_written(&c["after"])),
                "{name}: the squares at {at}"
            );
            assert_eq!(at % case["per"].as_u64().unwrap() as usize, 0, "{name}");
        }
        let row = read_row(&capture(&v, case), None);
        assert!(
            row.as_ref().is_some_and(|r| r.frame.is_some()),
            "{name}: a row with a frame ({row:?})"
        );
        let row = row.unwrap();
        assert_eq!(row.why, None, "{name}");
        assert_eq!(
            (row.format, row.depth.map(u64::from), row.session),
            (3, case["depth"].as_u64(), Some(4711)),
            "{name}"
        );
        assert_eq!(
            row.raw.as_deref(),
            Some(&hex(case["frame"].as_str().unwrap())[..]),
            "{name}: the frame's bytes, joined in lane order"
        );
        assert_eq!(row.frame.as_ref().map(|f| f.seq), Some(0x1234), "{name}");
        // the rows line says the lanes; the grid of that read, given back as the hint, reads
        // the same row
        let line: Value = serde_json::from_str(&row_line(0, Some(&row), None)).unwrap();
        assert_eq!(line["lanes"], case["lanes"], "{name}: the rows line");
        assert_eq!(
            read_row(&capture(&v, case), row.grid).as_ref(),
            Some(&row),
            "{name}: by the hint"
        );
    }
}

/// The first case with its lanes in the wrong order (lane 2 above lane 1) gives no frame: the
/// order of the lanes is the order of the bytes.
#[test]
fn lanes_read_in_another_order_give_no_frame() {
    let v = vector();
    let case = &v["cases"][0];
    let good = capture(&v, case);
    let (w, first) = (good.width, 30);
    let mut raw = Vec::new();
    for y in 0..good.height {
        for x in 0..w {
            // lines 1 and 2 swapped where the frame is
            let from = match y {
                1 if x >= 40 + first => 2,
                2 if x >= 40 + first => 1,
                y => y,
            };
            let c = good.rgb(x as f64, from as f64).unwrap();
            raw.extend([c[2], c[1], c[0], 255]);
        }
    }
    let row = read_row(&Bitmap::from_bgra(w, good.height, &raw).unwrap(), None);
    assert!(row.is_none_or(|r| r.frame.is_none()));
}

/// A layout square over 3 (more than 4 lanes) is refused: at 1 pixel a square a refused row is
/// the refusal of squares under 2 pixels.
#[test]
fn a_layout_over_3_is_no_row() {
    let v = vector();
    let mut case = v["cases"][0].clone();
    for other in v["refused"].as_array().unwrap() {
        case["head"][21] = other.clone();
        let row = read_row(&capture(&v, &case), None).unwrap();
        assert_eq!(
            (row.depth, row.grid, row.frame),
            (None, None, None),
            "layout {other}"
        );
    }
}

#[test]
fn the_record_has_the_lanes_when_they_change() {
    let v = vector();
    let dir = std::path::Path::new(env!("CARGO_TARGET_TMPDIR")).join("lanes3-record");
    let _ = std::fs::remove_file(&dir);
    let mut record = Recorder::new(&dir, Some(1.0), Colour::Srgb).unwrap();
    let two = read_row(&capture(&v, &v["cases"][0]), None).unwrap();
    let four = read_row(&capture(&v, &v["cases"][1]), None).unwrap();
    for (t, row) in [(0.0, &two), (0.1, &two), (0.2, &four)] {
        record.note(Some(row), t).unwrap();
    }
    let lines: Vec<Value> = std::fs::read_to_string(&dir)
        .unwrap()
        .lines()
        .map(|l| serde_json::from_str(l).unwrap())
        .collect();
    assert_eq!(
        lines[1..]
            .iter()
            .map(|l| l.get("lanes").cloned())
            .collect::<Vec<_>>(),
        [Some(json!(2)), None, Some(json!(4))]
    );
}
