//! Format 3's frame (docs/specs/232.md, section 6) against the hand-written vectors
//! (tests/vectors/strip3.json): each frame unpacks to the fields written by hand, and packs back
//! to the same bytes.

use hellolink_format::three::{self, Chunk, DIRECTORY, FAST};
use serde_json::Value;

fn hex(s: &str) -> Vec<u8> {
    (0..s.len())
        .step_by(2)
        .map(|i| u8::from_str_radix(&s[i..i + 2], 16).unwrap())
        .collect()
}

fn directory(bytes: &[u8]) -> Result<Vec<(u8, u16)>, String> {
    three::directory(bytes).collect()
}

#[test]
fn the_hand_written_frames() {
    let top = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../..");
    let v: Value = serde_json::from_str(
        &std::fs::read_to_string(top.join("tests/vectors/strip3.json")).unwrap(),
    )
    .unwrap();
    let frames = v["frames"].as_array().unwrap();
    assert_eq!(frames.len(), 5);
    for f in frames {
        let name = f["name"].as_str().unwrap();
        let bytes = hex(f["hex"].as_str().unwrap());
        let got = three::unpack(&bytes);
        if let Some(why) = f["refused"].as_str() {
            assert_eq!(got, Err(why.to_string()), "{name}");
            continue;
        }
        let (frame, chunk_error) = got.unwrap();
        assert_eq!((frame.session, frame.dwell), (4711, 10), "{name}");
        assert_eq!(Some(frame.seq as u64), f["seq"].as_u64(), "{name}");
        assert_eq!(chunk_error, f["chunkError"].as_str(), "{name}");
        assert_eq!(frame.section(FAST).map(<[u8]>::len), Some(67), "{name}");
        let want: Vec<(u8, u16)> = f["directory"]
            .as_array()
            .unwrap()
            .iter()
            .map(|p| (p[0].as_u64().unwrap() as u8, p[1].as_u64().unwrap() as u16))
            .collect();
        assert_eq!(
            directory(frame.section(DIRECTORY).unwrap()),
            Ok(want),
            "{name}"
        );
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
            assert_eq!(three::length(&bytes), (bytes.len(), true), "{name}");
            let sections: Vec<(u8, &[u8])> = frame.sections().collect();
            let packed = three::pack(
                frame.session,
                frame.dwell,
                frame.seq,
                &sections,
                frame.chunk.as_ref(),
            );
            assert_eq!(packed, Ok(bytes.clone()), "{name}: packs back");
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

fn frame(sections: &[(u8, &[u8])]) -> Vec<u8> {
    three::pack(1, 10, 1, sections, None).unwrap()
}

#[test]
fn a_bad_section_list_is_refused() {
    let fast = [0u8; 67];
    let good: &[(u8, &[u8])] = &[(FAST, &fast), (DIRECTORY, &[9, 0, 1])];
    assert!(three::unpack(&frame(good)).is_ok());
    let extra: &[(u8, &[u8])] = &[(FAST, &fast), (DIRECTORY, &[]), (9, &[1, 2, 3])];
    assert!(
        three::unpack(&frame(extra)).is_ok(),
        "an unknown id after them is skipped"
    );
    for (why, sections) in [
        ("no sections", &[][..]),
        ("no directory", &[(FAST, &fast[..])][..]),
        (
            "the directory first",
            &[(DIRECTORY, &[][..]), (FAST, &fast[..])][..],
        ),
        (
            "a short fast section",
            &[(FAST, &fast[..66]), (DIRECTORY, &[][..])][..],
        ),
        (
            "an id twice",
            &[
                (FAST, &fast[..]),
                (DIRECTORY, &[][..]),
                (9, &[][..]),
                (9, &[][..]),
            ][..],
        ),
        (
            "ids not rising in the directory",
            &[(FAST, &fast[..]), (DIRECTORY, &[24, 0, 1, 9, 0, 1][..])][..],
        ),
        (
            "a directory record cut",
            &[(FAST, &fast[..]), (DIRECTORY, &[24, 0][..])][..],
        ),
    ] {
        assert!(three::unpack(&frame(sections)).is_err(), "{why}");
    }
    // a section length past the fixed part: fixedLen 3, a section of 5 bytes
    let mut b = vec![3, 0, 1, 10, 0, 1, 0, 3, 9, 5, 0];
    b.extend(three::check(&b));
    b.push(0);
    assert!(three::unpack(&b).is_err());
}

#[test]
fn no_input_makes_unpack_panic() {
    let fast = [0u8; 67];
    let chunk = Chunk {
        oid: 26,
        version: 1,
        index: 0,
        count: 1,
        data: &[0xFD, 0xFD, 0xFD],
    };
    let whole = three::pack(1, 10, 1, &[(FAST, &fast), (DIRECTORY, &[])], Some(&chunk)).unwrap();
    // every prefix, and every byte changed, ends in an answer and not a panic
    for n in 0..=whole.len() {
        let _ = three::unpack(&whole[..n]);
        let _ = three::length(&whole[..n]);
    }
    for i in 0..whole.len() {
        for x in [0u8, 1, 0x7f, 0xff] {
            let mut b = whole.clone();
            b[i] = x;
            let _ = three::unpack(&b);
        }
    }
}

#[test]
fn pack_refuses_lengths_the_wire_cannot_hold() {
    let big = [0u8; 256];
    assert!(three::pack(1, 10, 1, &[(9, &big)], None).is_err());
    let chunk = |data| Chunk {
        oid: 1,
        version: 1,
        index: 0,
        count: 1,
        data,
    };
    assert!(three::pack(1, 10, 1, &[], Some(&chunk(&big))).is_err());
    assert!(three::pack(1, 10, 1, &[], Some(&chunk(&[]))).is_err());
}

#[test]
fn the_hand_written_binary_objects() {
    use hellolink_format::objects::{shape, to_json};
    let top = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../..");
    let v: Value = serde_json::from_str(
        &std::fs::read_to_string(top.join("tests/vectors/objects3.json")).unwrap(),
    )
    .unwrap();
    for o in v["objects"].as_array().unwrap() {
        let name = o["name"].as_str().unwrap();
        let id = o["id"].as_u64().unwrap() as u8;
        let payload = hex(o["payload"].as_str().unwrap());
        let json: Value = serde_json::from_str(&to_json(id, &payload).unwrap()).unwrap();
        assert_eq!(json, o["json"], "{name}: reads as written");
        let mut out = vec![];
        hellolink_format::encode(&shape(id).unwrap(), &o["json"], &mut out).unwrap();
        assert_eq!(
            out, payload,
            "{name}: the JSON packs to the bytes written by hand"
        );
    }
}
