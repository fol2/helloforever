//! Format 3's frame (docs/specs/232.md, section 6) against the hand-written vectors
//! (tests/vectors/strip3.json): each frame unpacks to the fields written by hand, and packs back
//! to the same bytes.

use hellolink_format::three::{self, DIRECTORY, FAST};
use serde_json::Value;

fn hex(s: &str) -> Vec<u8> {
    (0..s.len())
        .step_by(2)
        .map(|i| u8::from_str_radix(&s[i..i + 2], 16).unwrap())
        .collect()
}

#[test]
fn the_hand_written_frames() {
    let top = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../..");
    let v: Value = serde_json::from_str(
        &std::fs::read_to_string(top.join("tests/vectors/strip3.json")).unwrap(),
    )
    .unwrap();
    let frames = v["frames"].as_array().unwrap();
    assert_eq!(frames.len(), 4);
    for f in frames {
        let name = f["name"].as_str().unwrap();
        let bytes = hex(f["hex"].as_str().unwrap());
        assert_eq!(three::length(&bytes), (bytes.len(), true), "{name}");
        let got = three::unpack(&bytes);
        if let Some(why) = f["refused"].as_str() {
            assert_eq!(got, Err(why.to_string()), "{name}");
            continue;
        }
        let (frame, chunk_error) = got.unwrap();
        assert_eq!((frame.session, frame.dwell), (4711, 10), "{name}");
        assert_eq!(Some(frame.seq as u64), f["seq"].as_u64(), "{name}");
        assert_eq!(chunk_error.as_deref(), f["chunkError"].as_str(), "{name}");
        assert_eq!(frame.section(FAST).map(<[u8]>::len), Some(67), "{name}");
        let dir = three::directory(frame.section(DIRECTORY).unwrap()).unwrap();
        let want: Vec<(u8, u16)> = f["directory"]
            .as_array()
            .unwrap()
            .iter()
            .map(|p| (p[0].as_u64().unwrap() as u8, p[1].as_u64().unwrap() as u16))
            .collect();
        assert_eq!(dir, want, "{name}");
        match (&frame.chunk, &f["object"]) {
            (None, Value::Null) => {}
            (Some(c), o) => {
                assert_eq!(
                    (
                        c.oid as u64,
                        c.version as u64,
                        c.index as u64,
                        c.count as u64
                    ),
                    (
                        o["id"].as_u64().unwrap(),
                        o["version"].as_u64().unwrap(),
                        o["index"].as_u64().unwrap(),
                        o["count"].as_u64().unwrap()
                    ),
                    "{name}"
                );
                assert_eq!(c.data, hex(o["hex"].as_str().unwrap()), "{name}");
            }
            (c, o) => panic!("{name}: chunk {c:?}, written {o}"),
        }
        if chunk_error.is_none() {
            assert_eq!(three::pack(&frame), bytes, "{name}: packs back");
        }
    }
}

#[test]
fn the_length_is_known_from_the_fewest_bytes() {
    let one = hex(
        "0312670A1234004D0143828000D4310000000000000000000000000000000000000000238128EB000000059B75309C404000000000000000000000000000000000000000000000000000000000020609010218BEEF5E7F00",
    );
    assert_eq!(three::length(&one[..7]), (8, false));
    assert_eq!(
        three::length(&one[..8]),
        (88, false),
        "8 + 77 + 2, then objectId"
    );
    assert_eq!(three::length(&one[..88]), (88, true));
}

#[test]
fn a_bad_section_list_is_refused() {
    let frame = |sections: Vec<(u8, Vec<u8>)>| {
        three::pack(&three::Frame {
            session: 1,
            dwell: 10,
            seq: 1,
            sections,
            chunk: None,
        })
    };
    assert!(
        three::unpack(&frame(vec![(2, vec![]), (2, vec![])])).is_err(),
        "an id twice"
    );
    assert!(
        three::unpack(&frame(vec![(1, vec![0; 66])])).is_err(),
        "a short fast section"
    );
    assert!(
        three::unpack(&frame(vec![(9, vec![1, 2, 3])])).is_ok(),
        "an unknown id is skipped"
    );
    assert!(
        three::directory(&[24, 0, 1, 9, 0, 1]).is_err(),
        "ids not rising"
    );
    // a section length past the fixed part: fixedLen 3, a section of 5 bytes
    let mut b = vec![3, 0, 1, 10, 0, 1, 0, 3, 9, 5, 0];
    b.extend(three::check(&b));
    b.push(0);
    assert!(three::unpack(&b).is_err());
}
