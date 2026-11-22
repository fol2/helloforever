//! Format 3 rows with the computed palette (docs/specs/232.md, part C, "The computed palette"):
//! the hand-written rows of tests/vectors/ramp3.json, as captured colours with the game around
//! them, read by the reader; the fall-back rule for ramp rows; the record and the lines.

use hellolink::bitmap::Bitmap;
use hellolink::capture::Colour;
use hellolink::record::Recorder;
use hellolink::rows::row_line;
use hellolink::strip1::{Row, read_row, wide_to_bytes};
use hellolink::watch::{Quality, Watcher, failed};
use serde_json::{Value, json};

fn vector() -> Value {
    let top = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../..");
    serde_json::from_str(&std::fs::read_to_string(top.join("tests/vectors/ramp3.json")).unwrap())
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

/// Each square's (red, green, blue) levels from the vector's `codes`: at 6 bits a base64 digit
/// (the alphabet written out here), at 9 bits three octal digits.
fn levels_of(codes: &str, depth: u64) -> Vec<[usize; 3]> {
    const BASE64: &str = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    if depth == 4 {
        codes
            .chars()
            .map(|c| {
                let n = BASE64.find(c).unwrap();
                [n >> 4, n >> 2 & 3, n & 3]
            })
            .collect()
    } else {
        codes
            .split(' ')
            .map(|t| {
                let d: Vec<usize> = t.chars().map(|c| c.to_digit(8).unwrap() as usize).collect();
                [d[0], d[1], d[2]]
            })
            .collect()
    }
}

/// The capture of a case: 3 lines; the row on line 1 from x = 40, 1 pixel a square.
fn capture(v: &Value, case: &Value) -> Bitmap {
    let around: Vec<[u8; 3]> = v["around"].as_array().unwrap().iter().map(colour).collect();
    let digit = |d: &Value| {
        let d = d.as_u64().unwrap();
        [d >> 2 & 1, d >> 1 & 1, d & 1].map(|b| 255 * b as u8)
    };
    let paint: Vec<Vec<u8>> = serde_json::from_value(case["paint"].clone()).unwrap();
    let mut row: Vec<[u8; 3]> = case["head"].as_array().unwrap().iter().map(digit).collect();
    row.extend(case["ramp"].as_array().unwrap().iter().map(colour));
    row.extend(case["more"].as_array().unwrap().iter().map(digit));
    let codes = levels_of(
        case["codes"].as_str().unwrap(),
        case["depth"].as_u64().unwrap(),
    );
    row.extend(codes.iter().map(|l| [0, 1, 2].map(|c| paint[c][l[c]])));
    row.extend([[0, 0, 0]; 4]);
    let width = 40 + row.len() + 30;
    let mut raw = Vec::new();
    for y in 0..3 {
        for x in 0..width {
            let c = if y == 1 && (40..40 + row.len()).contains(&x) {
                row[x - 40]
            } else {
                around[(x + 5 * y) % around.len()]
            };
            raw.extend([c[2], c[1], c[0], 255]);
        }
    }
    Bitmap::from_bgra(width, 3, &raw).unwrap()
}

#[test]
fn the_hand_written_ramp_rows_read_as_written() {
    let v = vector();
    for case in v["cases"].as_array().unwrap() {
        let name = case["name"].as_str().unwrap();
        let row = read_row(&capture(&v, case), None).expect(name);
        let ramp = row.ramp.as_ref().expect(name);
        let want: Vec<[u8; 3]> = serde_json::from_value(case["ramp"].clone()).unwrap();
        assert_eq!(ramp.colours, want, "{name}: the ramp as read");
        assert_eq!(
            (ramp.gap as i64, ramp.leak as i64),
            (
                case["gap"].as_i64().unwrap(),
                case["leak"].as_i64().unwrap()
            ),
            "{name}: gap and leak"
        );
        assert_eq!(
            (row.format, row.depth.map(u64::from), row.session),
            (3, case["depth"].as_u64(), Some(4711)),
            "{name}"
        );
        assert_eq!(row.why.as_deref(), case["why"].as_str(), "{name}: why");
        match case["frame"].as_str() {
            Some(frame) => {
                assert_eq!(
                    row.raw.as_deref(),
                    Some(&hex(frame)[..]),
                    "{name}: the frame's bytes"
                );
                assert_eq!(
                    row.frame.as_ref().map(|f| f.seq),
                    Some(0x1234),
                    "{name}: the frame"
                );
            }
            None => assert!(row.frame.is_none() && row.raw.is_none(), "{name}"),
        }
        assert_eq!(
            failed(&row),
            case["failed"].as_bool().unwrap(),
            "{name}: failed"
        );
        assert_eq!(row.palette, None, "{name}: no drawn palette");
        assert_eq!(row.apart, None, "{name}: gap and leak replace apart");
        // the grid of that read, given back as the hint, reads the same row
        assert_eq!(
            read_row(&capture(&v, case), row.grid).as_ref(),
            Some(&row),
            "{name}"
        );
    }
}

#[test]
fn bytes_from_squares_at_9_bits_as_written_by_hand() {
    let v = vector();
    let squares: Vec<u16> = serde_json::from_value(v["nine"]["squares"].clone()).unwrap();
    assert_eq!(
        wide_to_bytes(&squares, 9, 3),
        hex(v["nine"]["bytes"].as_str().unwrap())
    );
}

/// The case's row with its levels square changed: a reader refuses another. At 1 pixel a square
/// a refused row is the refusal of squares under 2 pixels, as a layout other than 0.
#[test]
fn a_levels_square_other_than_3_or_7_is_no_row() {
    let v = vector();
    let mut case = v["cases"][1].clone();
    for other in [0, 1, 2, 4, 5, 6] {
        case["head"][28] = json!(other);
        let row = read_row(&capture(&v, &case), None).unwrap();
        assert_eq!(
            (row.depth, row.grid, row.frame),
            (None, None, None),
            "levels square {other}"
        );
    }
}

fn case_row(n: usize) -> Row {
    let v = vector();
    read_row(&capture(&v, &v["cases"][n]), None).unwrap()
}

#[test]
fn a_ramp_row_asks_for_fewer_bits_when_more_than_2_in_100_of_200_failed() {
    let (good, leaky, flat) = (case_row(1), case_row(5), case_row(4));
    assert!(!failed(&good) && failed(&leaky) && failed(&flat));
    // every `every`th of n frames bad: whether the last one asks
    let asks = |bad: &Row, every: usize, n: usize| {
        let mut q = Quality::default();
        (0..n)
            .map(|i| q.note(if i % every == every - 1 { bad } else { &good }))
            .collect::<Vec<bool>>()
    };
    for bad in [&leaky, &flat] {
        // 4 of 200 failed: no ask; 5 of 200: ask, at the 200th frame and not before
        assert!(!asks(bad, 50, 200).contains(&true), "4 in 200");
        let five = asks(bad, 40, 200);
        assert!(!five[..199].contains(&true) && five[199], "5 in 200");
    }
    // one bad frame does not ask at once (a drawn palette under 12 apart does)
    assert!(!asks(&leaky, 1, 199).contains(&true));
}

#[test]
fn the_watcher_says_gap_and_leak_and_the_bits_of_a_ramp_row_that_asks() {
    let v = vector();
    let mut w = Watcher::default();
    let events = w.feed(&capture(&v, &v["cases"][1]), 0.0);
    let state = events.iter().find(|e| e["kind"] == "state").unwrap();
    assert_eq!(
        (&state["gap"], &state["leak"], &state["depth"]),
        (&json!(34), &json!(0), &json!(4))
    );
    // a new Watcher: the 9-bit row's frame has the same seq
    let nine = Watcher::default().feed(&capture(&v, &v["cases"][6]), 0.1);
    let state = nine.iter().find(|e| e["kind"] == "state").unwrap();
    assert_eq!((&state["gap"], &state["depth"]), (&json!(26), &json!(8)));
    assert_eq!(case_row(6).bits(), Some(9));
    assert_eq!(case_row(1).bits(), Some(6));
    // 200 frames whose ramp does not rise: an ask for one step fewer bits (6 to 3)
    let mut w = Watcher::default();
    let flat = capture(&v, &v["cases"][4]);
    let asks: Vec<Value> = (0..200)
        .flat_map(|i| w.feed(&flat, i as f64 * 0.02))
        .filter(|e| e["kind"] == "ask")
        .collect();
    assert_eq!(asks, [json!({"kind": "ask", "session": 4711, "bits": 3})]);
}

#[test]
fn the_record_has_the_ramp_and_the_rows_line_gap_and_leak() {
    let dir = std::path::Path::new(env!("CARGO_TARGET_TMPDIR")).join("ramp3-record");
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    let path = dir.join("play.jsonl");
    let mut rec = Recorder::new(&path, Some(0.0), Colour::Srgb).unwrap();
    let (good, flat) = (case_row(1), case_row(4));
    rec.note(Some(&good), 0.0).unwrap();
    rec.note(Some(&good), 0.1).unwrap();
    rec.note(Some(&flat), 0.2).unwrap();
    let lines: Vec<Value> = std::fs::read_to_string(&path)
        .unwrap()
        .lines()
        .map(|l| serde_json::from_str(l).unwrap())
        .collect();
    let ramp = |n: usize| json!(vector()["cases"][n]["ramp"]);
    assert_eq!(lines[1]["ramp"], ramp(1));
    assert!(lines[1].get("palette").is_none());
    assert!(lines[2].get("ramp").is_none(), "only when it changed");
    assert_eq!(
        (&lines[3]["ramp"], &lines[3]["why"]),
        (&ramp(4), &json!("ramp"))
    );
    let line: Value = serde_json::from_str(&row_line(0, Some(&good), None)).unwrap();
    assert_eq!((&line["gap"], &line["leak"]), (&json!(34), &json!(0)));
    // a replay of the record feeds the ramp to the Watcher: its state says gap and leak
    let mut out = Vec::new();
    hellolink::replay::replay(std::fs::read(&path).unwrap().as_slice(), &mut out).unwrap();
    let out = String::from_utf8(out).unwrap();
    let state: Value = out
        .lines()
        .map(|l| serde_json::from_str::<Value>(l).unwrap())
        .find(|e| e["kind"] == "state")
        .unwrap();
    assert_eq!((&state["gap"], &state["leak"]), (&json!(34), &json!(0)));
}

// review of #291: a session that changes from a drawn palette to a ramp starts the count again, so
// good drawn frames do not hide bad ramp frames, nor the other way round
#[test]
fn a_change_between_a_drawn_palette_and_a_ramp_starts_the_count_again() {
    let mut drawn = case_row(1);
    drawn.ramp = None; // a drawn row at depth 4 (6 bits), its colours far apart
    drawn.apart = Some(60);
    let bad = case_row(4); // a ramp that does not rise: a failed frame
    assert!(failed(&bad) && !failed(&drawn) && drawn.bits() == Some(6) && bad.bits() == Some(6));
    let mut q = Quality::default();
    assert_eq!((0..195).filter(|_| q.note(&drawn)).count(), 0);
    assert_eq!(
        (0..5).filter(|_| q.note(&bad)).count(),
        0,
        "5 bad ramp frames after 195 drawn ones ask"
    );
}

// The 9-bit item (docs/specs/232.md, part C, "The fall-back stays"): the addon keeps its session at
// a step, so the reader asks once for each step, and the count of 200 frames starts again at it.
#[test]
fn a_9_bit_row_asks_for_6_and_the_6_bit_row_then_for_3_in_the_same_session() {
    let leaky = |n: usize| {
        let mut row = case_row(n);
        row.ramp.as_mut().unwrap().leak = 99; // read, but each frame counts as failed
        row
    };
    let (nine, six) = (leaky(6), leaky(1));
    assert!(failed(&nine) && failed(&six) && nine.frame.is_some() && six.frame.is_some());
    assert_eq!(
        (nine.session, six.session, nine.bits(), six.bits()),
        (Some(4711), Some(4711), Some(9), Some(6))
    );
    let mut w = Watcher::default();
    let mut asks = |row: &Row, t0: f64| -> Vec<(usize, Value)> {
        (0..200)
            .flat_map(|i| {
                w.feed_row(Some(row.clone()), t0 + i as f64 * 0.02)
                    .into_iter()
                    .filter(|e| e["kind"] == "ask")
                    .map(move |e| (i, e))
            })
            .collect()
    };
    assert_eq!(
        asks(&nine, 0.0),
        [(199, json!({"kind": "ask", "session": 4711, "bits": 6}))],
        "200 failed frames at 9 bits ask for 6"
    );
    assert_eq!(
        asks(&six, 10.0),
        [(199, json!({"kind": "ask", "session": 4711, "bits": 3}))],
        "at 6 bits the count starts again, and the same session asks for 3 after 200 more"
    );
    assert!(asks(&six, 20.0).is_empty(), "once for each step");
}
