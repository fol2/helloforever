//! The checks of tests/strip_watch_test.py on the stream's framing, the Watcher and the
//! request to fall back. Each assert's message is the Python check's name, word for word.
//! The checks of the capture processes, the slot writer and HTTP are not here (step 2b).

mod common;

use common::*;
use hellolink::bitmap::{Bitmap, frames_from};
use hellolink::strip1::{Chunk, chunks_of, pack_fast, pack_frame, pack_object, read_row};
use hellolink::watch::{Event, Watcher};
use serde_json::json;
use std::io::Cursor;

fn framed(raw: &[u8], width: u32, height: u32) -> Vec<u8> {
    let mut out = b"HLC1".to_vec();
    out.extend(width.to_le_bytes());
    out.extend(height.to_le_bytes());
    out.extend(raw);
    out
}

fn kinds(events: &[Event]) -> Vec<&str> {
    events.iter().filter_map(|e| e["kind"].as_str()).collect()
}

fn one() -> Vec<u8> {
    capture(4711, 4, LEVELS, &frame(1), None, WIDE)
}

#[test]
fn the_streams_framing() {
    let one = one();
    let both = [framed(&one, 2560, 4), framed(&one, 2560, 4)].concat();
    let frames: Vec<Bitmap> = frames_from(Cursor::new(both))
        .collect::<Result<_, _>>()
        .unwrap();
    assert!(
        frames.len() == 2 && (frames[0].width, frames[0].height) == (2560, 4),
        "two frames on the pipe are two bitmaps of the size the header gives"
    );
    let cut = [framed(&one, 2560, 4), framed(&one, 2560, 4)[..500].to_vec()].concat();
    assert_eq!(
        frames_from(Cursor::new(cut)).count(),
        1,
        "a frame cut short by the end of the pipe is dropped"
    );
    assert!(
        frames_from(Cursor::new(b"JUNKJUNKJUNKJUNK")).any(|f| f.is_err()),
        "bytes that are not a frame are refused"
    );
    let absurd = framed(&[], 1_000_000_000, 4);
    assert!(
        frames_from(Cursor::new(absurd)).any(|f| f.is_err()),
        "a frame that claims an absurd size is refused"
    );
    let row = read_row(&frames[0], None).unwrap();
    let fast = &row.frame.as_ref().unwrap().fast;
    assert!(
        row.session == Some(4711)
            && row.levels == [Some(76), Some(100), None, None]
            && fast[1] == ("health", Some(vec![("healthMax", 1158)])),
        "a raw frame reads like an image: the session, the levels, the frame"
    );
    assert!(
        Bitmap::from_bgra(2560, 4, &one[..one.len() - 1]).is_err(),
        "a raw frame with too few bytes is refused"
    );
}

#[test]
fn the_watcher() {
    let mut w = Watcher::default();
    let first = w.feed(&seq(1), 0.0);
    assert!(
        kinds(&first) == ["state"]
            && first[0]["session"] == 4711
            && first[0]["seq"] == 1
            && first[0]["depth"] == 4
            && first[0]["levels"]
                == json!({"health": 76, "power": 100, "targetHealth": null, "petHealth": null})
            && first[0]["fast"]["health"] == json!({"healthMax": 1158}),
        "the first capture gives the state: session, seq, depth, levels by name, the fast block"
    );
    assert!(
        w.feed(&seq(1), 0.02).is_empty(),
        "the same capture again gives nothing"
    );
    let moved = w.feed(
        &shot(Shot {
            levels: [Some(0.5), Some(1.0), None, None],
            ..Shot::default()
        }),
        0.04,
    );
    assert!(
        kinds(&moved) == ["levels"] && moved[0]["levels"]["health"] == 50,
        "level squares that changed with no new seq give a levels event"
    );
    assert_eq!(
        kinds(&w.feed(&seq(2), 0.06)),
        ["state"],
        "a new seq gives a state event"
    );
    assert!(
        w.hint.is_some(),
        "the place of the row is remembered after a good read"
    );
    let text = r#"{"map": 1437, "zone": "Wetlands", "sub": ""}"#;
    let parts = chunks_of(&pack_object(Some(text), false), 20);
    let mut events = vec![];
    for (i, part) in parts.iter().enumerate() {
        let image = shot(Shot {
            seq: 3 + i as u32,
            chunk: Some(Chunk {
                oid: 3,
                version: 500,
                index: i as u8,
                count: parts.len() as u8,
                data: part.clone(),
            }),
            ..Shot::default()
        });
        for _ in 0..3 {
            // each chunk is seen three times
            events.extend(w.feed(&image, 0.1 + i as f64 * 0.1));
        }
    }
    let objects: Vec<_> = events.iter().filter(|e| e["kind"] == "object").collect();
    assert_eq!(
        objects,
        [&json!({"kind": "object", "id": 3, "format": 0, "text": text})],
        "an object in several chunks, each seen three times, comes out once and whole"
    );

    let mut w = Watcher::default();
    w.feed(&seq(1), 0.0);
    let blank = blank();
    let mut events = vec![];
    for i in 0..40 {
        events.extend(w.feed(&blank, 0.1 + i as f64 * 0.02));
    }
    assert!(
        kinds(&events) == ["relocate", "lost"] && w.hint.is_none(),
        "two captures with no row ask for a new search, and 30 say the row is lost; each once"
    );
    assert_eq!(
        kinds(&w.feed(&seq(2), 2.0)),
        ["state"],
        "after that the row is found again by searching"
    );
    let other = w.feed(
        &shot(Shot {
            session: 4712,
            ..Shot::default()
        }),
        2.1,
    );
    assert!(
        kinds(&other) == ["state"] && other[0]["session"] == 4712,
        "another session is a new state, even with a seq seen before"
    );
}

fn stale_objects(events: &[Event]) -> Vec<&Event> {
    events
        .iter()
        .filter(|e| e["kind"] == "stale-object")
        .collect()
}

fn idles(w: &mut Watcher, times: &[f64]) -> Vec<Event> {
    times.iter().flat_map(|&t| w.idle(t)).collect()
}

fn single() -> Chunk {
    Chunk {
        oid: 3,
        version: 9,
        index: 0,
        count: 1,
        data: pack_object(Some("{}"), false),
    }
}

#[test]
fn what_time_makes_old() {
    let mut w = Watcher::default();
    w.feed(&seq(1), 0.0);
    let image = seq(1);
    let quiet: Vec<Event> = (0..30)
        .flat_map(|i| w.feed(&image, 0.1 * i as f64))
        .collect();
    assert!(
        quiet.is_empty(),
        "the same seq read again for 3 s gives nothing"
    );
    let mut old = w.feed(&image, 3.2);
    old.extend(w.feed(&image, 3.4));
    old.extend(w.idle(4.0));
    assert_eq!(
        kinds(&old),
        ["stale"],
        "after 3 s without a new seq the state is called stale, once; frames still decode there, so no new search"
    );
    assert!(
        kinds(&w.feed(&seq(2), 5.0)) == ["state"] && kinds(&w.idle(8.5)) == ["stale", "relocate"],
        "a new seq is fresh again, and can go stale again"
    );
    let mut w = Watcher::default();
    w.feed(&seq(1), 0.0);
    assert_eq!(
        kinds(&idles(&mut w, &[1.0, 3.5, 4.0, 9.0])),
        ["stale", "relocate", "relocate"],
        "with no capture at all (the row moved away, the old place stands still), time alone says stale, once, and asks for a search every 3 s"
    );

    let mut w = Watcher::default();
    w.feed(
        &shot(Shot {
            chunk: Some(single()),
            ..Shot::default()
        }),
        0.0,
    );
    for (times, name) in [
        (
            &[21.0, 22.0][..],
            "after three rounds of six objects (21.6 s) an object is not yet stale: there are eight (#62)",
        ),
        (
            &[30.0, 32.0],
            "after three rounds of eight objects (28.8 s) it is not yet stale either: there are nine (#64)",
        ),
        (
            &[33.0, 35.5],
            "after three rounds of nine objects (32.4 s) it is not yet stale either: there are ten (#68)",
        ),
        (
            &[36.5, 39.0],
            "after three rounds of ten objects (36 s) it is not yet stale either: there are eleven (#74)",
        ),
        (
            &[40.0, 42.5],
            "after three rounds of eleven objects (39.6 s) it is not yet stale either: there are twelve (#109)",
        ),
        (
            &[44.0, 46.5],
            "after three rounds of twelve objects (43.2 s) it is not yet stale either: there are thirteen (#127)",
        ),
        (
            &[47.0, 50.0, 51.0, 53.5, 54.5, 57.0],
            "after three rounds of thirteen, fourteen and fifteen objects (46.8, 50.4, 54 s) it is not yet stale: there are sixteen (#138)",
        ),
        (
            &[58.0, 61.0, 64.5],
            "after three rounds of sixteen and seventeen objects (57.6, 61.2 s) it is not yet stale: there are eighteen (#180)",
        ),
        (
            &[65.0, 68.5, 72.0, 75.5, 79.0, 82.5],
            "after three rounds of eighteen to twenty-two objects (64.8 to 79.2 s) it is not yet stale: there are twenty-three (0.8.0)",
        ),
    ] {
        assert!(stale_objects(&idles(&mut w, times)).is_empty(), "{name}");
    }
    assert_eq!(
        stale_objects(&idles(&mut w, &[83.0, 83.5])),
        [&json!({"kind": "stale-object", "id": 3})],
        "an object not seen whole for three largest rounds (82.8 s at a dwell of 0.1 s) is called stale, once"
    );
    let again = w.feed(
        &shot(Shot {
            seq: 2,
            chunk: Some(single()),
            ..Shot::default()
        }),
        84.0,
    );
    let object_kinds = |events: &[Event]| -> Vec<String> {
        kinds(events)
            .into_iter()
            .filter(|k| k.contains("object"))
            .map(String::from)
            .collect()
    };
    assert!(
        object_kinds(&again) == ["fresh-object"]
            && object_kinds(&w.idle(168.0)) == ["stale-object"],
        "seen whole again in the same version, it is called fresh, and can go stale again"
    );

    let mut w = Watcher::default();
    w.feed(
        &shot(Shot {
            chunk: Some(single()),
            dwell: 20,
            ..Shot::default()
        }),
        0.0,
    );
    assert!(
        stale_objects(&idles(&mut w, &[43.5, 165.4])).is_empty(),
        "at a dwell of 0.2 s the time doubles: not stale after 165.4 s ..."
    );
    assert_eq!(
        stale_objects(&w.idle(165.8)),
        [&json!({"kind": "stale-object", "id": 3})],
        "... and stale after 165.6 s (3 x 23 x 12 x 0.2 s)"
    );

    let mut w = Watcher::default();
    w.feed(
        &shot(Shot {
            chunk: Some(single()),
            ..Shot::default()
        }),
        0.0,
    );
    let stale_now = w.idle(83.0); // past 82.8 s: the object is stale now
    let mut wrong = single();
    *wrong.data.last_mut().unwrap() ^= 1; // the same version, but its object check fails
    let other = Chunk {
        oid: 2,
        version: 1,
        index: 0,
        count: 1,
        data: pack_object(Some("null"), false),
    };
    let mut events = w.feed(
        &shot(Shot {
            seq: 2,
            chunk: Some(other),
            ..Shot::default()
        }),
        84.0,
    );
    for (s, t) in [(3, 84.2), (4, 84.4)] {
        events.extend(w.feed(
            &shot(Shot {
                seq: s,
                chunk: Some(wrong.clone()),
                ..Shot::default()
            }),
            t,
        ));
    }
    assert!(
        stale_objects(&stale_now) == [&json!({"kind": "stale-object", "id": 3})]
            && !kinds(&events).contains(&"fresh-object")
            && w.joiner.objects[&3].3 == 0.0,
        "a chunk that fails the object check, seen twice, does not make the old object fresh"
    );

    let mut never = Watcher::default(); // a row that was found but never decoded, and then moved away
    assert_eq!(
        kinds(&idles(&mut never, &[0.0, 2.0, 3.5, 5.0, 7.0, 60.0])),
        ["relocate", "relocate", "relocate"],
        "with no frame ever decoded and no capture coming, a search is still asked for every 3 s, and nothing is called stale"
    );
}

#[test]
fn one_watcher_for_the_whole_run() {
    let mut w = Watcher::default();
    let wrong = pack_frame(4999, 1, 10, &pack_fast(STATE), None).unwrap();
    let mismatch = bitmap(&capture(4711, 4, LEVELS, &wrong, None, WIDE), WIDE);
    // the palette is fine, but no frame is ever right: 200 of them must add up
    let events: Vec<Event> = (0..205)
        .flat_map(|i| w.feed(&mismatch, i as f64 * 0.02))
        .collect();
    let kinds = kinds(&events);
    let at = |k: &str| kinds.iter().position(|x| *x == k);
    assert!(
        kinds.iter().filter(|k| **k == "ask").count() == 1
            && at("relocate").is_some()
            && at("relocate") < at("ask"),
        "frames that keep failing ask for the fall-back after 200, though the row was searched for again on the way"
    );
}

#[test]
fn asking_for_the_fall_back() {
    let asks = |events: Vec<Event>| -> Vec<Event> {
        events.into_iter().filter(|e| e["kind"] == "ask").collect()
    };
    let mut w = Watcher::default();
    let events: Vec<Event> = (0..5u32)
        .flat_map(|i| {
            let image = shot(Shot {
                seq: 1 + i,
                bend: Some(crush),
                ..Shot::default()
            });
            w.feed(&image, i as f64 * 0.02)
        })
        .collect();
    assert_eq!(
        asks(events),
        [json!({"kind": "ask", "session": 4711})],
        "a palette that cannot be told apart asks for depth 2, once, with the session from the two-level squares"
    );
    let events: Vec<Event> = (0..5u32)
        .flat_map(|i| {
            let image = shot(Shot {
                seq: 1 + i,
                bend: Some(crush),
                session: 4712,
                ..Shot::default()
            });
            w.feed(&image, 1.0 + i as f64 * 0.02)
        })
        .collect();
    assert_eq!(
        asks(events),
        [json!({"kind": "ask", "session": 4712})],
        "a new session that is as bad asks again"
    );
    let mut w = Watcher::default();
    let images = [seq(1), seq(2), seq(3)];
    let events: Vec<Event> = (0..250)
        .flat_map(|i| w.feed(&images[i % 3], i as f64 * 0.02))
        .collect();
    assert!(
        asks(events).is_empty(),
        "250 good captures at depth 4 never ask"
    );
}
