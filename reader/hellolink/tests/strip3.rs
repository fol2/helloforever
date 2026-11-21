//! Format 3 (docs/specs/232.md, section 6) through the reader: the hand-written vectors
//! (tests/vectors/strip3.json) read as the reader's frames, the fast state as written.

use hellolink::strip2::unpack_any;
use serde_json::{Value, json};

fn hex(s: &str) -> Vec<u8> {
    (0..s.len())
        .step_by(2)
        .map(|i| u8::from_str_radix(&s[i..i + 2], 16).unwrap())
        .collect()
}

#[test]
fn the_hand_written_frames_read_as_the_reader_frames() {
    let top = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../..");
    let v: Value = serde_json::from_str(
        &std::fs::read_to_string(top.join("tests/vectors/strip3.json")).unwrap(),
    )
    .unwrap();
    for f in v["frames"].as_array().unwrap() {
        let name = f["name"].as_str().unwrap();
        let got = unpack_any(&hex(f["hex"].as_str().unwrap()));
        if let Some(why) = f["refused"].as_str() {
            assert_eq!(got.err().as_deref(), Some(why), "{name}");
            continue;
        }
        let frame = got.unwrap();
        assert_eq!(
            (frame.version, frame.session, frame.dwell),
            (3, 4711, 10),
            "{name}"
        );
        assert_eq!(Some(frame.seq as u64), f["seq"].as_u64(), "{name}");
        // every frame is whole: a keyframe of its own seq
        let two = frame.two.as_ref().unwrap();
        assert!(two.key && two.key_seq == (frame.seq % 256) as u8, "{name}");
        let want: Vec<(u8, u16)> = serde_json::from_value(f["directory"].clone()).unwrap();
        assert_eq!(frame.directory.as_ref(), Some(&want), "{name}");
        assert_eq!(frame.chunk.is_some(), !f["object"].is_null(), "{name}");
        // the known groups, with their fields; the rest unknown
        let state: serde_json::Map<String, Value> = frame
            .fast
            .iter()
            .filter_map(|(g, fields)| {
                fields.as_ref().map(|fs| {
                    let m: serde_json::Map<String, Value> =
                        fs.iter().map(|(k, v)| (k.to_string(), json!(v))).collect();
                    (g.to_string(), Value::Object(m))
                })
            })
            .collect();
        let written = json!({"clock": {"clock": 54321}, "target": {"level": 35, "flags": 129, "nameHash": 10475},
            "position": {"map": 1435, "x": 30000, "y": 40000, "facing": 64}});
        assert_eq!(Value::Object(state), written, "{name}");
        assert_eq!(frame.fast.len(), 16, "{name}: all 16 groups");
    }
}

/// A record line for a format-3 frame packed from parts.
fn line(t: f64, seq: u16, dir: &[u8], chunk: Option<(u16, &[u8])>) -> String {
    use hellolink_format::three::{self, Chunk, DIRECTORY, FAST};
    let fast = [0u8; 67];
    let c = chunk.map(|(version, data)| Chunk {
        oid: 26,
        version,
        index: 0,
        count: 1,
        data,
    });
    let bytes = three::pack(
        4711,
        10,
        seq,
        &[(FAST, &fast), (DIRECTORY, dir)],
        c.as_ref(),
    )
    .unwrap();
    let hex: String = bytes.iter().map(|b| format!("{b:02x}")).collect();
    format!(
        r#"{{"t": {t}, "frame": "{hex}", "depth": 4, "levels": [null, null, null, null], "more": []}}"#
    )
}

#[test]
fn the_directory_makes_a_held_object_old_at_once() {
    let one = hellolink::strip1::pack_object(Some("1"), false);
    let two = hellolink::strip1::pack_object(Some("2"), false);
    let record = [
        r#"{"record": 1, "started": 1}"#.to_string(),
        line(0.0, 1, &[26, 0, 1], Some((1, &one))), // version 1 whole
        line(0.1, 2, &[26, 0, 1], None),
        line(0.2, 3, &[26, 0, 2], None), // the directory names version 2
        line(0.3, 4, &[26, 0, 2], Some((2, &two))), // version 2 whole
        line(0.4, 5, &[26, 0, 2], None),
    ]
    .join("\n");
    let mut out = vec![];
    hellolink::replay::replay(record.as_bytes(), &mut out).unwrap();
    let kinds: Vec<(String, f64)> = String::from_utf8(out)
        .unwrap()
        .lines()
        .map(|l| serde_json::from_str::<Value>(l).unwrap())
        .filter(|e| e["kind"] != "state" && e["kind"] != "record")
        .map(|e| {
            (
                format!("{} {}", e["kind"].as_str().unwrap(), e["id"]),
                e["t"].as_f64().unwrap(),
            )
        })
        .collect();
    assert_eq!(
        kinds,
        [
            ("object 26".to_string(), 0.0),
            ("stale-object 26".to_string(), 0.2),
            ("object 26".to_string(), 0.3),
        ],
        "the old copy is called old when the directory names version 2, not three rounds later"
    );
}

/// A record line for a format-3 frame with object 26's chunk `index` of `count`.
fn line_part(
    t: f64,
    seq: u16,
    dir: &[u8],
    version: u16,
    index: u8,
    count: u8,
    data: &[u8],
) -> String {
    use hellolink_format::three::{self, Chunk, DIRECTORY, FAST};
    let fast = [0u8; 67];
    let c = Chunk {
        oid: 26,
        version,
        index,
        count,
        data,
    };
    let bytes = three::pack(4711, 10, seq, &[(FAST, &fast), (DIRECTORY, dir)], Some(&c)).unwrap();
    let hex: String = bytes.iter().map(|b| format!("{b:02x}")).collect();
    format!(
        r#"{{"t": {t}, "frame": "{hex}", "depth": 4, "levels": [null, null, null, null], "more": []}}"#
    )
}

fn replay_events(lines: &[String]) -> Vec<Value> {
    let record = std::iter::once(r#"{"record": 1, "started": 1}"#.to_string())
        .chain(lines.iter().cloned())
        .collect::<Vec<_>>()
        .join("\n");
    let mut out = vec![];
    hellolink::replay::replay(record.as_bytes(), &mut out).unwrap();
    String::from_utf8(out)
        .unwrap()
        .lines()
        .map(|l| serde_json::from_str::<Value>(l).unwrap())
        .collect()
}

#[test]
fn a_chunk_of_a_version_older_than_the_directory_names_is_not_taken() {
    // version 1 in two chunks; the directory names version 2 before its last chunk comes
    let obj = hellolink::strip1::pack_object(Some("\"an old text\""), false);
    let (a, b) = obj.split_at(obj.len() / 2);
    let events = replay_events(&[
        line_part(0.0, 1, &[26, 0, 1], 1, 0, 2, a),
        line(0.1, 2, &[26, 0, 2], None),
        line_part(0.2, 3, &[26, 0, 2], 1, 1, 2, b),
        line(0.3, 4, &[26, 0, 2], None),
        line(0.4, 5, &[26, 0, 2], None),
    ]);
    let kinds: Vec<String> = events
        .iter()
        .filter(|e| e["kind"] != "state" && e["kind"] != "record")
        .map(|e| format!("{} {} {}", e["kind"].as_str().unwrap(), e["id"], e["t"]))
        .collect();
    assert!(
        kinds.is_empty(),
        "version 1 is never made whole once the directory names version 2: {kinds:?}"
    );
}

#[test]
fn every_format_3_frame_is_fresh_when_it_comes() {
    // seq 1 and seq 257 share their low byte and their fast bytes; 3 s apart
    let events = replay_events(&[line(0.0, 1, &[], None), line(3.0, 257, &[], None)]);
    let ages: Vec<(f64, f64)> = events
        .iter()
        .filter(|e| e["kind"] == "state")
        .map(|e| (e["t"].as_f64().unwrap(), e["keyAge"].as_f64().unwrap()))
        .collect();
    assert_eq!(ages, [(0.0, 0.0), (3.0, 0.0)], "not the first frame's time");
}

/// The digits of a format 3 row up to its frame, at 6 bits: finder, black level triples, the
/// depth digit 5, the layout square 0, the session, the palette, `more` 0 (section 6).
fn row_squares(session: u16, frame: &[u8]) -> Vec<[f64; 3]> {
    let digit = |d: u8| [(d >> 2 & 1) as f64, (d >> 1 & 1) as f64, (d & 1) as f64];
    let colour = |i: u8| {
        [
            (i / 16) as f64 / 3.0,
            (i / 4 % 4) as f64 / 3.0,
            (i % 4) as f64 / 3.0,
        ]
    };
    let mut digits = hellolink::strip1::FINDER.to_vec();
    digits.extend([0; 12]);
    digits.extend([5, 0]);
    let s = session as u32;
    digits.extend(&hellolink::strip1::bytes_to_squares(&[0, (s >> 8) as u8, s as u8], 3)[2..]);
    let mut out: Vec<[f64; 3]> = digits.into_iter().map(digit).collect();
    out.extend((0..64).map(colour));
    out.extend([0, 0].map(digit));
    out.extend(
        hellolink::strip1::bytes_to_squares(frame, 6)
            .into_iter()
            .map(colour),
    );
    out
}

#[test]
fn a_row_cut_in_its_chunk_keeps_its_fast_state() {
    use hellolink::bitmap::{Bitmap, render};
    use hellolink_format::three::{self, Chunk, DIRECTORY, FAST};
    let mut fast = [0u8; 67];
    fast[0] = 0x80; // group 1 known: the clock
    fast[3..5].copy_from_slice(&54321u16.to_be_bytes());
    let c = Chunk {
        oid: 26,
        version: 1,
        index: 0,
        count: 1,
        data: &[0xFD, 0xFD, 0xFD],
    };
    let frame = three::pack(
        4711,
        10,
        9,
        &[(FAST, &fast), (DIRECTORY, &[26, 0, 1])],
        Some(&c),
    )
    .unwrap();
    let squares = row_squares(4711, &frame);
    let cells: String = squares
        .iter()
        .enumerate()
        .map(|(i, [r, g, b])| format!("{} 10 2 2 {r} {g} {b}\n", 10 + 2 * i))
        .collect();
    // the fixed part and objectId are 85 bytes, 114 squares; 94 head squares before the frame
    let read = |width: usize| {
        let bmp = Bitmap::new(&render(&cells, 1.0, 0, 0, width, 40).unwrap()).unwrap();
        hellolink::strip1::read_row(&bmp, None).unwrap()
    };
    let whole = read(10 + 2 * squares.len() + 20);
    let f = whole.frame.as_ref().expect("the whole row");
    assert!(f.chunk.is_some() && f.version == 3);
    let cut = read(10 + 2 * (94 + 118));
    assert_eq!(cut.why, None);
    let f = cut.frame.as_ref().expect("the fixed part of a cut row");
    assert!(f.chunk.is_none(), "the chunk is dropped");
    assert_eq!(
        f.fast[0],
        ("clock", Some(vec![("clock", 54321)])),
        "the fast state is kept"
    );
}

#[test]
fn an_object_old_after_10_minutes_is_fresh_only_when_all_of_it_came_again() {
    let obj = hellolink::strip1::pack_object(Some("\"a text\""), false);
    let (a, b) = obj.split_at(obj.len() / 2);
    let events = replay_events(&[
        line_part(0.0, 1, &[26, 0, 1], 1, 0, 2, a),
        line_part(0.1, 2, &[26, 0, 1], 1, 1, 2, b), // whole
        line(700.0, 3, &[26, 0, 1], None),          // not seen whole for 10 minutes: old
        line_part(700.1, 4, &[26, 0, 1], 1, 0, 2, a), // half of it again: still old
        line(700.2, 5, &[26, 0, 1], None),
        line_part(700.3, 6, &[26, 0, 1], 1, 1, 2, b), // all of it again: fresh
        line(700.4, 7, &[26, 0, 1], None),
    ]);
    let kinds: Vec<String> = events
        .iter()
        .filter(|e| e["kind"] != "state" && e["kind"] != "record" && e["kind"] != "stale")
        .filter(|e| e["kind"] != "relocate")
        .map(|e| format!("{} {} {}", e["kind"].as_str().unwrap(), e["id"], e["t"]))
        .collect();
    assert_eq!(
        kinds,
        [
            "object 26 0.1",
            "stale-object 26 700.0",
            "fresh-object 26 700.3"
        ]
    );
}
