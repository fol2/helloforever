//! The format-1 codec against the spec (docs/STRIP.md) and the committed vectors
//! (tests/vectors/ at the repository's top), not against its own encoder alone.

use hellolink::bitmap::{Bitmap, render};
use hellolink::rows::fast_json;
use hellolink::strip1::*;
use serde_json::{Value, json};
use std::path::PathBuf;

fn top() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../..")
}

fn vector() -> Value {
    let text = std::fs::read_to_string(top().join("tests/vectors/strip1.json")).unwrap();
    serde_json::from_str(&text).unwrap()
}

fn hex(s: &Value) -> Vec<u8> {
    let s = s.as_str().unwrap();
    (0..s.len())
        .step_by(2)
        .map(|i| u8::from_str_radix(&s[i..i + 2], 16).unwrap())
        .collect()
}

/// The check of section 3 by another formula than the code's: s1 is the sum of the bytes,
/// s2 the sum of each byte times how many bytes from it to the end, both modulo 255.
fn check_by_hand(data: &[u8]) -> [u8; 2] {
    let s1 = data.iter().map(|&b| b as u64).sum::<u64>() % 255;
    let s2 = data
        .iter()
        .enumerate()
        .map(|(i, &b)| (data.len() - i) as u64 * b as u64)
        .sum::<u64>()
        % 255;
    [s1 as u8, s2 as u8]
}

#[test]
fn spec_examples() {
    assert_eq!(check(b"abcde"), [0xF0, 0xC8]);
    assert_eq!(check_by_hand(b"abcde"), [0xF0, 0xC8]);
    assert_eq!(bytes_to_squares(&[1, 0, 0x2A], 6), [0, 16, 0, 42]);
    assert_eq!(bytes_to_squares(&[1, 0, 0x2A], 3), [0, 0, 2, 0, 0, 0, 5, 2]);
    assert_eq!(
        squares_to_bytes(&[0, 0, 2, 0, 0, 0, 5, 2], 3, 3),
        [1, 0, 0x2A]
    );
}

/// A frame written out by hand from the tables of sections 3, 5 and 6.
#[rustfmt::skip]
fn by_hand() -> Vec<u8> {
    let mut f = vec![
        0x01,               // version 1
        0x12, 0x67,         // session 4711
        0x0A,               // dwell 10
        0x00, 0x09,         // seq 9
        0x3A,               // fastLen 58
        0xC8, 0x04,         // known: clock (group 1), health (2), state (5), threat (14)
        0xD4, 0x31,         // clock 54321
        0x00, 0x04, 0x86,   // health: healthMax 1158
        0, 0, 0, 0,         // power, unknown
        0, 0, 0, 0, 0, 0, 0, // level, unknown
        0x00, 0x83,         // state: flags 131 (in combat, has target, has pet)
        0, 0, 0, 0,         // cast
        0, 0, 0, 0,         // target
        0, 0, 0,            // pet
        0, 0, 0, 0, 0, 0, 0, // position
        0, 0, 0, 0, 0,      // purse
        0, 0, 0, 0, 0,      // hand
        0, 0, 0, 0, 0,      // loot
        0, 0, 0,            // uiError
        0x3A, 0x64,         // threat: player 58, pet 100
        0x03,               // objectId 3
        0x01, 0xF4,         // objectVersion 500
        0x00, 0x01,         // chunkIndex 0 of chunkCount 1
        0x07,               // chunkLen 7
        0x00, b'n', b'u', b'l', b'l', 0xBC, 0x5F, // format 0, "null", the object's check
    ];
    let sum = check_by_hand(&f);
    f.extend(sum);
    f
}

#[test]
fn a_frame_written_by_hand() {
    let raw = by_hand();
    assert_eq!(raw.len(), 7 + 58 + 6 + 7 + 2);
    assert_eq!(check(&raw[..raw.len() - 2]), raw[raw.len() - 2..]);
    let f = unpack_frame(&raw).unwrap();
    assert_eq!((f.version, f.session, f.dwell, f.seq), (1, 4711, 10, 9));
    assert_eq!(
        fast_json(&f.fast),
        json!({"clock": {"clock": 54321}, "health": {"healthMax": 1158}, "power": null, "level": null,
               "state": {"flags": 131}, "cast": null, "target": null, "pet": null, "position": null,
               "purse": null, "hand": null, "loot": null, "uiError": null, "threat": {"player": 58, "pet": 100}})
    );
    let chunk = f.chunk.clone().unwrap();
    assert_eq!(
        (chunk.oid, chunk.version, chunk.index, chunk.count),
        (3, 500, 0, 1)
    );
    let mut joiner = Assembler::default();
    assert_eq!(joiner.feed(&f, 0.0), Some((3, 0, Some("null".into()))));
    assert_eq!(
        joiner.feed(&f, 0.1),
        None,
        "the same chunk again is no new object"
    );
    // And the encoder writes the same bytes.
    let fast = pack_fast(&[
        ("clock", &[("clock", 54321)]),
        ("health", &[("healthMax", 1158)]),
        ("state", &[("flags", 131)]),
        ("threat", &[("player", 58), ("pet", 100)]),
    ]);
    assert_eq!(pack_frame(4711, 9, 10, &fast, Some(&chunk)).unwrap(), raw);
}

#[test]
fn a_frame_that_breaks_a_rule_is_refused() {
    let raw = by_hand();
    let mut bad = raw.clone();
    bad[20] ^= 1;
    assert_eq!(unpack_frame(&bad).unwrap_err(), "frame check failed");
    assert_eq!(
        unpack_frame(&raw[..raw.len() - 1]).unwrap_err(),
        "frame cut short"
    );
    let mut v2 = raw.clone();
    v2[0] = 2;
    let n = v2.len();
    let sum = check_by_hand(&v2[..n - 2]);
    v2[n - 2..].copy_from_slice(&sum);
    assert_eq!(unpack_frame(&v2).unwrap_err(), "unknown version 2");
    let mut dwell = raw.clone();
    dwell[3] = 101;
    let sum = check_by_hand(&dwell[..n - 2]);
    dwell[n - 2..].copy_from_slice(&sum);
    assert_eq!(unpack_frame(&dwell).unwrap_err(), "bad session or dwell");
}

#[test]
fn objects() {
    let text = r#"{"free": 12, "items": [[2318, 14], [4234, 3]]}"#;
    assert_eq!(
        unpack_object(&pack_object(Some(text), true)).unwrap(),
        (1, Some(text.into()))
    );
    assert_eq!(
        unpack_object(&pack_object(Some("點解我呢區升得咁慢？"), false))
            .unwrap()
            .1
            .unwrap(),
        "點解我呢區升得咁慢？"
    );
    assert_eq!(
        unpack_object(&pack_object(None, true)).unwrap(),
        (255, None)
    );
    // A Deflate stream with a zlib header is read too.
    let mut wrapped = vec![1];
    wrapped.extend(miniz_oxide::deflate::compress_to_vec_zlib(
        text.as_bytes(),
        6,
    ));
    let sum = check(&wrapped);
    wrapped.extend(sum);
    assert_eq!(unpack_object(&wrapped).unwrap().1.unwrap(), text);
    let mut broken = vec![1, 0xFF, 1, 2];
    let sum = check(&broken);
    broken.extend(sum);
    assert!(
        unpack_object(&broken)
            .unwrap_err()
            .starts_with("object does not inflate")
    );
}

#[test]
fn the_committed_vectors() {
    let v = vector();
    let raw = hex(&v["frame"]);
    assert_eq!(raw.len() as u64, v["frameBytes"].as_u64().unwrap());
    let f = unpack_frame(&raw).unwrap();
    assert_eq!((f.session, f.seq, f.dwell), (4711, 9, 10));
    assert_eq!(fast_json(&f.fast), v["state"]);
    let o = &v["object"];
    let c = f.chunk.clone().unwrap();
    assert_eq!((c.oid, c.version, c.index, c.count), (3, 500, 0, 1));
    assert_eq!(c.data, hex(&o["bytes"]));
    assert_eq!(
        unpack_object(&c.data).unwrap(),
        (0, Some(o["text"].as_str().unwrap().into()))
    );
    let squares = |k: &str| {
        v[k].as_array()
            .unwrap()
            .iter()
            .map(|s| s.as_u64().unwrap() as u8)
            .collect::<Vec<_>>()
    };
    assert_eq!(bytes_to_squares(&raw, 3), squares("squaresDepth2"));
    assert_eq!(bytes_to_squares(&raw, 6), squares("squaresDepth4"));
    for o in v["objects"].as_array().unwrap() {
        let f = unpack_frame(&hex(&o["frame"])).unwrap();
        assert_eq!(f.seq as u64, o["seq"].as_u64().unwrap());
        let mut joiner = Assembler::default();
        let (id, format, text) = joiner.feed(&f, 0.0).unwrap();
        assert_eq!((id as u64, format), (o["id"].as_u64().unwrap(), 0));
        assert_eq!(text.as_deref(), o["text"].as_str());
        assert_eq!(pack_object(text.as_deref(), false), hex(&o["bytes"]));
    }
}

#[test]
fn the_committed_images() {
    let v = vector();
    for (name, how) in v["images"].as_object().unwrap() {
        let bmp =
            Bitmap::new(&std::fs::read(top().join("tests/vectors").join(name)).unwrap()).unwrap();
        let row = read_row(&bmp, None).unwrap();
        assert_eq!(row.depth.map(u64::from), how["depth"].as_u64(), "{name}");
        assert_eq!(row.session, Some(4711), "{name}");
        assert_eq!(row.levels, [Some(76), Some(83), Some(12), None], "{name}");
        assert_eq!(row.square, 2.0, "{name}");
        let (x0, top, _) = row.grid.unwrap();
        assert_eq!((x0.round(), top), (0.0, 0), "{name}");
        let f = row.frame.unwrap();
        assert_eq!(
            (f.seq, fast_json(&f.fast)),
            (9, v["state"].clone()),
            "{name}"
        );
        let mut joiner = Assembler::default();
        assert_eq!(
            joiner.feed(&f, 0.0).unwrap().2.as_deref(),
            v["object"]["text"].as_str(),
            "{name}"
        );
    }
}

#[test]
fn a_rendered_row_at_both_depths() {
    let raw = by_hand();
    for depth in [2, 4] {
        let cells: String = row_colours(4711, depth, [Some(0.5), None, Some(1.0), Some(0.0)], &raw)
            .iter()
            .enumerate()
            .map(|(i, c)| format!("{} 3 3 3 {:.6} {:.6} {:.6}\n", 10 + 3 * i, c[0], c[1], c[2]))
            .collect();
        let bmp = Bitmap::new(&render(&cells, 1.0, 0, 0, 2560, 12).unwrap()).unwrap();
        let row = read_row(&bmp, None).unwrap();
        assert_eq!(
            row.frame.as_ref().map(|f| f.seq),
            Some(9),
            "depth {depth}: {:?}",
            row.why
        );
        assert_eq!(row.levels, [Some(50), None, Some(100), Some(0)]);
        assert_eq!(row.apart.is_some(), depth == 4);
        // The grid of that read, given back as the hint, reads the same row.
        assert_eq!(read_row(&bmp, row.grid), Some(row));
    }
}

#[test]
fn a_row_with_squares_under_two_pixels_is_refused() {
    let raw = by_hand();
    let cells: String = row_colours(4711, 2, [None; 4], &raw)
        .iter()
        .enumerate()
        .map(|(i, c)| format!("{} 0 1 1 {:.6} {:.6} {:.6}\n", 10 + i, c[0], c[1], c[2]))
        .collect();
    let bmp = Bitmap::new(&render(&cells, 1.0, 0, 0, 2560, 12).unwrap()).unwrap();
    let row = read_row(&bmp, None).unwrap();
    assert_eq!(
        row.why.as_deref(),
        Some("squares of about 1.0 pixels: under 2 pixels a square the row is not read")
    );
    assert!(row.frame.is_none() && row.grid.is_none());
}
