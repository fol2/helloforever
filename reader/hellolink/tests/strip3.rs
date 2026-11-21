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
