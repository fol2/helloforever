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
