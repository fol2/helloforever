//! Format 2 (docs/specs/213.md) against the hand-written vectors (tests/vectors/strip2.json)
//! and the spec's rules, not against an encoder of this crate.

use hellolink::rows::fast_json;
use hellolink::strip1::{Chunk, check};
use hellolink::strip2::*;
use serde_json::{Map, Value, json};
use std::path::PathBuf;

fn vectors() -> Vec<Value> {
    let top = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../..");
    let v: Value = serde_json::from_str(
        &std::fs::read_to_string(top.join("tests/vectors/strip2.json")).unwrap(),
    )
    .unwrap();
    v["frames"].as_array().unwrap().clone()
}

fn bytes(hex: &str) -> Vec<u8> {
    (0..hex.len())
        .step_by(2)
        .map(|i| u8::from_str_radix(&hex[i..i + 2], 16).unwrap())
        .collect()
}

/// Every group of format 2, `null` but those the vector names.
fn whole(state: &Value) -> Value {
    let mut out = Map::new();
    for (name, _) in GROUPS {
        out.insert(name.into(), state.get(name).cloned().unwrap_or(Value::Null));
    }
    Value::Object(out)
}

#[test]
fn the_hand_written_fields_make_the_hex_and_its_check() {
    for f in vectors() {
        let joined: String = f["fields"]
            .as_array()
            .unwrap()
            .iter()
            .map(|p| p[1].as_str().unwrap())
            .collect();
        assert_eq!(joined, f["hex"].as_str().unwrap(), "{}", f["name"]);
        let b = bytes(&joined);
        // s1, s2 by the spec's words: s1 = (s1 + b) mod 255, then s2 = (s2 + s1) mod 255
        let (mut s1, mut s2) = (0u32, 0u32);
        for &x in &b[..b.len() - 2] {
            s1 = (s1 + x as u32) % 255;
            s2 = (s2 + s1) % 255;
        }
        assert_eq!([s1 as u8, s2 as u8], b[b.len() - 2..], "{}", f["name"]);
    }
}

#[test]
fn the_vectors_read_to_their_state_and_object() {
    let mut keys = Keys::default();
    let mut joiner = Joiner::default();
    for (i, f) in vectors().iter().enumerate() {
        let frame = unpack_frame(&bytes(f["hex"].as_str().unwrap())).unwrap();
        assert_eq!(frame.session, 4711);
        assert_eq!(frame.dwell, 10);
        assert_eq!(
            frame.seq as u64,
            f["seq"].as_u64().unwrap(),
            "{}",
            f["name"]
        );
        let two = frame.two.as_ref().unwrap();
        assert_eq!(two.key, f["key"].as_bool().unwrap());
        assert_eq!(two.key_seq as u64, f["keySeq"].as_u64().unwrap());
        let fast = keys.resolve(&frame, i as f64 * 0.1).unwrap();
        assert_eq!(fast_json(&fast), whole(&f["state"]), "{}", f["name"]);
        let object = frame.chunk.as_ref().and_then(|c| joiner.feed(c, 0.0));
        let want = &f["object"];
        match object {
            None => assert!(want.is_null(), "{}", f["name"]),
            Some((id, format, text)) => {
                assert_eq!(json!({"id": id, "format": format, "text": text}), *want)
            }
        }
    }
}

#[test]
fn a_delta_needs_its_own_keyframe_not_older_than_two_seconds() {
    let f = vectors();
    let key = unpack_frame(&bytes(f[0]["hex"].as_str().unwrap())).unwrap();
    let delta = unpack_frame(&bytes(f[1]["hex"].as_str().unwrap())).unwrap();
    let mut keys = Keys::default();
    assert_eq!(keys.resolve(&delta, 0.0), None, "no keyframe held");
    keys.resolve(&key, 10.0).unwrap();
    assert!(keys.resolve(&delta, 12.0).is_some(), "2 s is still good");
    assert_eq!(keys.resolve(&delta, 12.01), None, "older than 2 s");
    keys.resolve(&key, 20.0).unwrap();
    keys.drop_key();
    assert_eq!(
        keys.resolve(&delta, 20.1),
        None,
        "dropped (a new session or depth)"
    );
    // a keyframe of another seq: the delta names 0x34, the kept one is 0x35
    let mut other = bytes(f[0]["hex"].as_str().unwrap());
    other[5] = 0x35;
    other[7] = 0x35;
    let n = other.len();
    let sum = check(&other[..n - 2]);
    other[n - 2..].copy_from_slice(&sum);
    keys.resolve(&unpack_frame(&other).unwrap(), 30.0).unwrap();
    assert_eq!(keys.resolve(&delta, 30.1), None, "another keyframe");
}

/// The frame with its check made again after a change.
fn edited(hex: &str, edit: impl Fn(&mut Vec<u8>)) -> Vec<u8> {
    let mut b = bytes(hex);
    edit(&mut b);
    let n = b.len();
    let sum = check(&b[..n - 2]);
    b[n - 2..].copy_from_slice(&sum);
    b
}

#[test]
fn bad_frames_are_refused() {
    let f = vectors();
    let key = f[0]["hex"].as_str().unwrap();
    let delta = f[1]["hex"].as_str().unwrap();
    let refused = |b: &[u8], why: &str| {
        let e = unpack_frame(b).unwrap_err();
        assert!(e.contains(why), "{e} (wanted {why})");
    };
    refused(&edited(key, |b| b[6] = 0x40), "unknown kind");
    refused(&edited(key, |b| b[0] = 1), "unknown version");
    refused(
        &edited(key, |b| b[1..3].copy_from_slice(&[0, 0])),
        "bad session",
    );
    refused(&edited(key, |b| b[3] = 4), "bad session or dwell");
    let mut sum = bytes(key);
    let n = sum.len();
    sum[n - 1] ^= 1;
    refused(&sum, "check failed");
    refused(&bytes(key)[..10], "cut short");
    // bit 17: a group this reader does not know
    refused(&edited(key, |b| b[11] = 0x80), "does not know");
    // a varint that never ends: dx 0x8A 0x83 0xC2, then the object part's bytes
    refused(
        &edited(delta, |b| {
            b[13] = 0x8A;
            b[14] = 0x83;
            b[15] = 0xC2
        }),
        "varint",
    );
    // fastLen one longer than the groups
    let mut long = bytes(key);
    long[8] = 0x11;
    long.insert(9 + 16, 0x00);
    let n = long.len();
    let sum = check(&long[..n - 2]);
    long[n - 2..].copy_from_slice(&sum);
    refused(&long, "longer than its groups");
    // a chunk index past its count
    refused(&edited(delta, |b| b[19] = 1), "bad object part");
}

#[test]
fn a_position_difference_outside_the_map_gives_no_state() {
    let f = vectors();
    let key = unpack_frame(&bytes(f[0]["hex"].as_str().unwrap())).unwrap();
    let Some(Two {
        part: Part::Key(k), ..
    }) = key.two
    else {
        panic!()
    };
    let far = [(
        "position",
        Change::Moved {
            dx: 40000,
            dy: 0,
            facing: 0,
        },
    )];
    assert_eq!(apply(&k, &far), None, "x 70000 is off the map");
    let near = [(
        "position",
        Change::Moved {
            dx: -30000,
            dy: 25535,
            facing: 7,
        },
    )];
    let fast = apply(&k, &near).unwrap();
    assert_eq!(
        fast_json(&fast)["position"],
        json!({"map": 1435, "x": 0, "y": 65535, "facing": 7})
    );
    // no position in the keyframe: a difference has nothing to stand on
    let mut none = k.clone();
    none.iter_mut().find(|(n, _)| *n == "position").unwrap().1 = None;
    assert_eq!(
        apply(
            &none,
            &[(
                "position",
                Change::Moved {
                    dx: 1,
                    dy: 1,
                    facing: 0
                }
            )]
        ),
        None
    );
}

fn chunk(oid: u8, version: u16, index: u8, count: u8, data: &[u8]) -> Chunk {
    Chunk {
        oid,
        version,
        index,
        count,
        data: data.to_vec(),
    }
}

#[test]
fn chunks_join_with_frames_between_and_in_any_order() {
    // the object bytes of format 0, "hi", and its check: 00 68 69 + check
    let mut obj = vec![0, b'h', b'i'];
    obj.extend(check(&obj));
    let mut j = Joiner::default();
    assert_eq!(
        j.feed(&chunk(5, 7, 1, 2, &obj[2..]), 0.0),
        None,
        "the second chunk first"
    );
    assert_eq!(
        j.feed(&chunk(5, 7, 1, 2, &obj[2..]), 0.1),
        None,
        "the same chunk again"
    );
    let done = j.feed(&chunk(5, 7, 0, 2, &obj[..2]), 3.0).unwrap();
    assert_eq!(done, (5, 0, Some("hi".into())));
    assert_eq!(
        j.feed(&chunk(5, 7, 0, 2, &obj[..2]), 9.0),
        None,
        "a refresh of the version held"
    );
    assert_eq!(j.whole[&5], (7, 9.0), "the refresh renews its time");
    // a newer version drops the chunks of the one before
    assert_eq!(j.feed(&chunk(6, 1, 0, 2, &obj[..2]), 0.0), None);
    assert_eq!(j.feed(&chunk(6, 2, 1, 2, &obj[2..]), 0.0), None);
    assert_eq!(
        j.feed(&chunk(6, 1, 1, 2, &obj[2..]), 0.0),
        None,
        "version 1's first chunk was dropped"
    );
}

// --- the row (section 4), drawn here from the spec's table, not by the reader's code ---

use hellolink::bitmap::{Bitmap, render};
use hellolink::strip1::read_row;
use hellolink::watch::Watcher;

fn digit_rgb(d: u8) -> [f64; 3] {
    [(d >> 2 & 1) as f64, (d >> 1 & 1) as f64, (d & 1) as f64]
}

/// The bytes as squares of `bits`, most significant bit first, the last filled with 0.
fn squares(data: &[u8], bits: usize) -> Vec<u8> {
    let all: Vec<u8> = data
        .iter()
        .flat_map(|b| (0..8).rev().map(move |k| b >> k & 1))
        .collect();
    all.chunks(bits)
        .map(|c| {
            c.iter()
                .enumerate()
                .fold(0, |n, (k, b)| n | b << (bits - 1 - k))
        })
        .collect()
}

/// A level triple for a per cent (the level of docs/STRIP.md, section 4), or black.
fn triple(level: Option<u8>) -> [u8; 3] {
    level.map_or([0, 0, 0], |l| {
        [l / 16, l / 2 % 8, if l % 2 == 1 { 6 } else { 2 }]
    })
}

/// A format-2 row at 1 pixel a square, from x = 40, y = 30, on render's noisy background.
fn row_image(depth_digit: u8, more: &[Option<u8>], frame: &[u8]) -> Bitmap {
    let mut sq: Vec<[f64; 3]> = [4, 2, 1, 7, 0, 6, 3, 5].map(digit_rgb).to_vec();
    for l in [Some(127), Some(64), None, Some(1)] {
        sq.extend(triple(l).map(digit_rgb));
    }
    sq.push(digit_rgb(depth_digit));
    // session 4711 as six two-level digits: 18 bits, the top two 0
    sq.extend(
        (0..6)
            .rev()
            .map(|k| digit_rgb((4711u32 >> (3 * k) & 7) as u8)),
    );
    let palette = |i: u8| {
        [
            (i / 16) as f64 / 3.0,
            (i / 4 % 4) as f64 / 3.0,
            (i % 4) as f64 / 3.0,
        ]
    };
    if depth_digit == 6 {
        sq.extend((0..64).map(palette));
    }
    sq.extend([more.len() as u8 / 8, more.len() as u8 % 8].map(digit_rgb));
    for &l in more {
        sq.extend(triple(l).map(digit_rgb));
    }
    if depth_digit == 6 {
        sq.extend(squares(frame, 6).into_iter().map(palette));
    } else {
        sq.extend(squares(frame, 3).into_iter().map(digit_rgb));
    }
    let cells: String = sq
        .iter()
        .enumerate()
        .map(|(i, [r, g, b])| format!("{} 30 1 1 {r:.6} {g:.6} {b:.6}\n", 40 + i))
        .collect();
    Bitmap::new(&render(&cells, 1.0, 0, 0, 2560, 80).unwrap()).unwrap()
}

#[test]
fn a_format_2_row_of_1_pixel_squares_is_read_at_either_depth() {
    let f = vectors();
    let frame = bytes(f[1]["hex"].as_str().unwrap());
    for (digit, depth) in [(6, 4), (3, 2)] {
        let row = read_row(&row_image(digit, &[Some(100), None, Some(3)], &frame), None)
            .unwrap_or_else(|| panic!("no row at depth digit {digit}"));
        assert_eq!(row.why, None, "depth digit {digit}");
        assert_eq!(
            (row.format, row.depth, row.session),
            (2, Some(depth), Some(4711))
        );
        assert_eq!(row.levels, [Some(100), Some(50), None, Some(1)]);
        assert_eq!(row.more, vec![Some(79), None, Some(2)]);
        assert_eq!(row.square, 1.0);
        let got = row.frame.unwrap();
        assert_eq!(got.seq, 0x1235);
        assert!(got.two.is_some());
    }
    // no further triples
    let row = read_row(&row_image(6, &[], &frame), None).unwrap();
    assert_eq!((row.more.len(), row.frame.is_some()), (0, true));
}

#[test]
fn a_frame_of_version_1_in_a_format_2_row_is_refused() {
    // the depth square says format 2: the frame must be version 2
    let mut v1 = bytes(vectors()[0]["hex"].as_str().unwrap());
    v1[0] = 1;
    let n = v1.len();
    let sum = check(&v1[..n - 2]);
    v1[n - 2..].copy_from_slice(&sum);
    let row = read_row(&row_image(6, &[], &v1), None).unwrap();
    assert!(row.frame.is_none(), "{:?}", row.why);
}

#[test]
fn the_watcher_says_state_from_keyframes_and_deltas_and_drops_a_delta_without_its_keyframe() {
    let f = vectors();
    let img = |i: usize| row_image(6, &[], &bytes(f[i]["hex"].as_str().unwrap()));
    let kinds = |ev: &[Value], k: &str| {
        ev.iter()
            .filter(|e| e["kind"] == k)
            .cloned()
            .collect::<Vec<_>>()
    };
    // a delta first: its keyframe was lost, so no state
    let mut w = Watcher::default();
    let ev = w.feed(&img(1), 0.0);
    assert!(kinds(&ev, "state").is_empty(), "{ev:?}");
    assert_eq!(
        kinds(&ev, "object").len(),
        1,
        "the object part is still good"
    );
    // the keyframe, then the delta: two states
    let mut w = Watcher::default();
    let a = w.feed(&img(0), 0.0);
    let b = w.feed(&img(1), 0.1);
    let (sa, sb) = (&kinds(&a, "state")[0], &kinds(&b, "state")[0]);
    assert_eq!(sa["format"], 2);
    assert_eq!(sa["fast"], whole(&f[0]["state"]));
    assert_eq!(sb["fast"], whole(&f[1]["state"]));
    assert_eq!(sb["seq"], 0x1235);
    assert_eq!(kinds(&b, "object")[0]["format"], 253);
    // the same delta 3 s later: its keyframe is too old
    let mut w = Watcher::default();
    w.feed(&img(0), 0.0);
    let late = w.feed(&img(2), 3.0);
    assert!(kinds(&late, "state").is_empty(), "{late:?}");
}

#[test]
fn the_api_keeps_an_object_that_goes_secret_and_marks_it() {
    use hellolink::api::Api;
    use std::time::Duration;
    let mut api = Api::start(0, Duration::from_millis(200)).unwrap();
    api.tell(&json!({"kind": "object", "id": 26, "format": 0, "text": "{\"player\": []}"}));
    api.tell(&json!({"kind": "object", "id": 26, "format": 253, "text": null}));
    let snap = api.snapshot();
    let o = &snap["objects"]["26"];
    assert_eq!(o["text"], "{\"player\": []}", "{snap}");
    assert_eq!(
        (o["stale"].clone(), o["secret"].clone()),
        (json!(true), json!(true))
    );
    api.tell(&json!({"kind": "object", "id": 26, "format": 0, "text": "{}"}));
    let snap = api.snapshot();
    assert_eq!(snap["objects"]["26"]["stale"], false);
    assert_eq!(snap["objects"]["26"].get("secret"), None);
    api.close();
}

#[test]
fn a_refresh_of_a_one_chunk_object_held_is_not_said_again() {
    let mut obj = vec![0, b'o', b'k'];
    obj.extend(check(&obj));
    let mut j = Joiner::default();
    assert!(j.feed(&chunk(8, 3, 0, 1, &obj), 0.0).is_some());
    assert_eq!(
        j.feed(&chunk(8, 3, 0, 1, &obj), 58.0),
        None,
        "the refresh round"
    );
}

#[test]
fn a_new_session_drops_the_kept_keyframe() {
    let f = vectors();
    // the delta of another session, whose keySeq happens to match the kept keyframe
    let other = edited(f[1]["hex"].as_str().unwrap(), |b| {
        b[1..3].copy_from_slice(&[0x12, 0x68])
    });
    let key = read_row(
        &row_image(6, &[], &bytes(f[0]["hex"].as_str().unwrap())),
        None,
    )
    .unwrap();
    let mut next = key.clone();
    next.session = Some(4712);
    next.frame = Some(unpack_frame(&other).unwrap());
    let mut w = Watcher::default();
    assert!(
        w.feed_row(Some(key), 0.0)
            .iter()
            .any(|e| e["kind"] == "state")
    );
    let ev = w.feed_row(Some(next), 0.1);
    assert!(ev.iter().all(|e| e["kind"] != "state"), "{ev:?}");
}

// --- review round 1 of #226 ---

#[test]
fn the_same_keyframe_seen_again_keeps_the_time_it_first_came() {
    let f = vectors();
    let key = unpack_frame(&bytes(f[0]["hex"].as_str().unwrap())).unwrap();
    let mut keys = Keys::default();
    keys.resolve(&key, 1.0);
    keys.resolve(&key, 1.9);
    assert_eq!(keys.key_at(), Some(1.0));
    let delta = unpack_frame(&bytes(f[1]["hex"].as_str().unwrap())).unwrap();
    assert_eq!(
        keys.resolve(&delta, 3.01),
        None,
        "2 s after it first came, not after it was seen last"
    );
}

#[test]
fn the_state_is_old_one_and_a_half_seconds_after_its_keyframe() {
    let f = vectors();
    let img = |i: usize| row_image(6, &[], &bytes(f[i]["hex"].as_str().unwrap()));
    let mut w = Watcher::default();
    w.feed(&img(0), 0.0);
    let early = w.feed(&img(1), 1.4);
    let state = early.iter().find(|e| e["kind"] == "state").unwrap();
    assert_eq!(state["keyAge"], 1.4);
    assert!(early.iter().all(|e| e["kind"] != "stale"), "{early:?}");
    let late = w.feed(&img(2), 1.6);
    assert!(
        late.iter().any(|e| e["kind"] == "stale"),
        "the delta came, but its keyframe is old: {late:?}"
    );
}

#[test]
fn the_api_keeps_a_new_sessions_objects_that_came_before_its_first_state() {
    use hellolink::api::Api;
    use std::time::Duration;
    let mut api = Api::start(0, Duration::from_millis(200)).unwrap();
    api.tell(&json!({"kind": "state", "session": 1, "seq": 1}));
    api.tell(&json!({"kind": "object", "id": 3, "format": 0, "text": "old", "session": 1}));
    // the UI loaded again: an object of session 2 comes before session 2's first state
    api.tell(&json!({"kind": "object", "id": 4, "format": 0, "text": "new", "session": 2}));
    api.tell(&json!({"kind": "state", "session": 2, "seq": 9}));
    let objects = &api.snapshot()["objects"];
    assert_eq!(objects.get("3"), None, "session 1's object went with it");
    assert_eq!(objects["4"]["text"], "new");
    api.close();
}

#[test]
fn an_object_secret_now_stays_old_when_its_version_is_seen_again() {
    use hellolink::api::Api;
    use std::time::Duration;
    let mut api = Api::start(0, Duration::from_millis(200)).unwrap();
    api.tell(&json!({"kind": "object", "id": 26, "format": 0, "text": "x"}));
    api.tell(&json!({"kind": "object", "id": 26, "format": 253, "text": null}));
    api.tell(&json!({"kind": "stale-object", "id": 26}));
    api.tell(&json!({"kind": "fresh-object", "id": 26}));
    assert_eq!(api.snapshot()["objects"]["26"]["stale"], true);
    api.close();
}

#[test]
fn an_object_whole_but_unreadable_is_said() {
    let mut obj = vec![0, b'h', b'i'];
    let sum = check(&obj);
    obj.extend([sum[0], sum[1] ^ 1]); // the object's own check is wrong
    let mut j = Joiner::default();
    assert_eq!(j.feed(&chunk(9, 4, 0, 1, &obj), 0.0), None);
    let (id, version, why) = j.bad.take().unwrap();
    assert_eq!((id, version), (9, 4));
    assert!(why.contains("check"), "{why}");
}

#[test]
fn a_keyframe_not_naming_itself_and_gone_bits_past_the_end_are_refused() {
    let f = vectors();
    let e = unpack_frame(&edited(f[0]["hex"].as_str().unwrap(), |b| b[7] = 0x33)).unwrap_err();
    assert!(e.contains("keySeq"), "{e}");
    // gone 0x80 | 0x01: a 1 past the two changed groups
    let e = unpack_frame(&edited(f[1]["hex"].as_str().unwrap(), |b| b[12] = 0x81)).unwrap_err();
    assert!(e.contains("filling bits"), "{e}");
}

#[test]
fn format_1_does_not_take_an_object_of_format_253() {
    assert!(hellolink::strip1::unpack_object(&[253, 253, 253]).is_err());
}

#[test]
fn replay_keeps_the_keyframe_across_a_failed_capture_and_gives_more_back() {
    let f = vectors();
    let line = |v: Value| format!("{v}\n");
    let mut record = String::from("{\"record\":1,\"started\":1.0}\n");
    record += &line(
        json!({"t": 0.0, "frame": f[0]["hex"], "depth": 4, "levels": [1, 2, 3, 4], "more": [50, null]}),
    );
    record += &line(json!({"t": 0.1, "why": "frame check failed", "bad": "0212"}));
    record += &line(json!({"t": 0.2, "frame": f[1]["hex"]}));
    let mut out = Vec::new();
    hellolink::replay::replay(record.as_bytes(), &mut out).unwrap();
    let states: Vec<Value> = String::from_utf8(out)
        .unwrap()
        .lines()
        .map(|l| serde_json::from_str::<Value>(l).unwrap())
        .filter(|e| e["kind"] == "state")
        .collect();
    assert_eq!(states.len(), 2, "{states:?}");
    assert_eq!(states[1]["seq"], 0x1235);
    assert_eq!(states[1]["more"], json!([50, null]));
}

#[test]
fn the_record_writes_more_for_a_format_2_row() {
    let f = vectors();
    let path = PathBuf::from(env!("CARGO_TARGET_TMPDIR")).join("strip2-record.jsonl");
    let _ = std::fs::remove_file(&path);
    let row = read_row(
        &row_image(6, &[Some(64), None], &bytes(f[0]["hex"].as_str().unwrap())),
        None,
    );
    let mut rec = hellolink::record::Recorder::new(&path, Some(1.0)).unwrap();
    rec.note(row.as_ref(), 10.0).unwrap();
    rec.note(row.as_ref(), 10.1).unwrap();
    let text = std::fs::read_to_string(&path).unwrap();
    let lines: Vec<Value> = text
        .lines()
        .map(|l| serde_json::from_str(l).unwrap())
        .collect();
    assert_eq!(lines[1]["more"], json!([50, null]), "{text}");
    assert_eq!(lines[2].get("more"), None, "only when it changes");
}

// --- review round 2 of #226 ---

#[test]
fn the_state_of_format_2_gives_the_keyframes_age_now_and_an_old_one_is_stale() {
    use hellolink::api::Api;
    use std::time::Duration;
    let mut api = Api::start(0, Duration::from_millis(200)).unwrap();
    api.tell(&json!({"kind": "state", "session": 1, "seq": 1, "keyAge": 0.8, "format": 2}));
    std::thread::sleep(Duration::from_millis(300));
    let snap = api.snapshot();
    assert!(snap["keyAge"].as_f64().unwrap() >= 1.1, "{snap}");
    assert_eq!(snap["condition"], "live");
    api.tell(&json!({"kind": "state", "session": 1, "seq": 2, "keyAge": 1.7, "format": 2}));
    assert_eq!(
        api.snapshot()["condition"],
        "stale",
        "a delta whose keyframe is old"
    );
    api.close();
}

#[test]
fn state_over_http_keeps_secret() {
    use hellolink::api::Api;
    use std::io::{Read, Write};
    use std::time::Duration;
    let mut api = Api::start(0, Duration::from_millis(200)).unwrap();
    let port = api.port;
    api.tell(&json!({"kind": "object", "id": 26, "format": 0, "text": "x"}));
    api.tell(&json!({"kind": "object", "id": 26, "format": 253, "text": null}));
    let mut s = std::net::TcpStream::connect(("127.0.0.1", port)).unwrap();
    s.write_all(b"GET /state HTTP/1.0\r\nHost: 127.0.0.1\r\n\r\n")
        .unwrap();
    let mut body = String::new();
    s.read_to_string(&mut body).unwrap();
    assert!(body.contains("\"secret\": true"), "{body}");
    assert!(!body.contains("keyAge"), "no format-2 state yet: {body}");
    api.close();
}

#[test]
fn a_secret_object_seen_again_is_not_said_fresh() {
    let mut obj = vec![0, b'o', b'k'];
    obj.extend(check(&obj));
    let mut w = Watcher::default();
    let f = vectors();
    // the keyframe row carries no chunk; feed object 26 by its rows: a version of format 253
    let key = read_row(
        &row_image(6, &[], &bytes(f[0]["hex"].as_str().unwrap())),
        None,
    )
    .unwrap();
    let mut with = key.clone();
    with.frame = Some(unpack_frame(&bytes(f[1]["hex"].as_str().unwrap())).unwrap());
    w.feed_row(Some(key), 0.0);
    w.feed_row(Some(with.clone()), 0.1);
    // long after: stale; then the same version again
    let later = w.idle(200.0);
    assert!(
        later.iter().any(|e| e["kind"] == "stale-object"),
        "{later:?}"
    );
    let again = w.feed_row(Some(with), 200.1);
    assert!(
        again.iter().all(|e| e["kind"] != "fresh-object"),
        "{again:?}"
    );
}

#[test]
fn an_object_event_of_format_253_says_secret() {
    // the local program keeps its last copy, marked old, on this flag (JevCompanion, 20 Nov 2026)
    let f = vectors();
    let key = read_row(
        &row_image(6, &[], &bytes(f[0]["hex"].as_str().unwrap())),
        None,
    )
    .unwrap();
    let mut with = key.clone();
    with.frame = Some(unpack_frame(&bytes(f[1]["hex"].as_str().unwrap())).unwrap());
    let mut w = Watcher::default();
    w.feed_row(Some(key), 0.0);
    let ev = w.feed_row(Some(with), 0.1);
    let object = ev.iter().find(|e| e["kind"] == "object").unwrap();
    assert_eq!(
        (object["format"].clone(), object["secret"].clone()),
        (json!(253), json!(true)),
        "{object}"
    );
}
