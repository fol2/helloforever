//! The checks of tests/strip1_test.py that tests/vectors.rs and tests/watch.rs do not hold:
//! the fast block, the frame's limits, objects, joining chunks (section 6), the row through
//! an image and the request to fall back. Each assert's message is the Python check's name,
//! word for word.

mod common;

use common::{Bend, crush};
use hellolink::bitmap::{Bitmap, render};
use hellolink::rows::fast_json;
use hellolink::strip1::*;
use hellolink::watch::Quality;
use serde_json::{Value, json};

type State<'a> = &'a [(&'a str, &'a [(&'a str, i64)])];

const STATE: State<'static> = &[
    ("clock", &[("clock", 54321)]),
    ("health", &[("healthMax", 1158)]),
    ("power", &[("powerMax", 1335), ("powerType", 0)]),
    ("level", &[("level", 29), ("xp", 2004), ("xpMax", 64000)]),
    ("state", &[("flags", 128 + 4 + 2 + 1 + 256)]),
    ("cast", &[("spell", 19434), ("tenths", 17)]),
    (
        "target",
        &[("level", 23), ("flags", 128 + 1), ("nameHash", 0xF0C8)],
    ),
    ("pet", &[("healthMax", 1355)]),
    (
        "position",
        &[("map", 1437), ("x", 32768), ("y", 16384), ("facing", 64)],
    ),
    ("purse", &[("money", 7800), ("bagFree", 12)]),
    ("hand", &[("item", 2504), ("enchant", 599)]),
    ("loot", &[("counter", 255), ("item", 2318), ("quantity", 2)]),
    ("uiError", &[("error", 50), ("counter", 3)]),
    ("threat", &[("player", 58), ("pet", 100)]),
];

/// What `fast_json(unpack_fast(..))` must give for a state: the groups it does not name are null.
fn as_json(state: State) -> Value {
    GROUPS
        .iter()
        .map(|(g, _)| {
            let fields = state.iter().find(|s| s.0 == *g);
            let v = fields.map_or(Value::Null, |(_, f)| {
                f.iter().map(|(k, v)| (*k, json!(v))).collect()
            });
            (*g, v)
        })
        .collect()
}

fn fast() -> Vec<u8> {
    pack_fast(STATE)
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

/// `plain` of the Python test: no object.
fn plain() -> Vec<u8> {
    pack_frame(4711, 9, 10, &fast(), None).unwrap()
}

/// `frame` of the Python test: a chunk, and a seq that wraps.
fn with_chunk() -> Vec<u8> {
    let c = chunk(4, 65535, 1, 3, b"\x00some bytes");
    pack_frame(4711, 65536 + 9, 10, &fast(), Some(&c)).unwrap()
}

/// Writes the frame's check again after a change.
fn resum(f: &mut [u8]) {
    let n = f.len();
    let sum = check(&f[..n - 2]);
    f[n - 2..].copy_from_slice(&sum);
}

#[test]
fn the_fast_block() {
    assert!(
        FAST_LEN == 58 && fast().len() == 58,
        "section 5: the fast block is 58 bytes"
    );
    let back = |state: State| fast_json(&unpack_fast(&pack_fast(state)).unwrap());
    assert_eq!(
        back(STATE),
        as_json(STATE),
        "every field of every group comes back"
    );
    let some: Vec<_> = STATE
        .iter()
        .copied()
        .filter(|(g, _)| !["target", "pet", "threat"].contains(g))
        .collect();
    assert_eq!(
        back(&some),
        as_json(&some),
        "an unknown group comes back as unknown, not as zeros"
    );
    let with = |purse: &'static [(&str, i64)], level: &'static [(&str, i64)]| -> Vec<_> {
        STATE
            .iter()
            .map(|&(g, f)| match g {
                "purse" => (g, purse),
                "level" => (g, level),
                _ => (g, f),
            })
            .collect()
    };
    let big = with(
        &[("money", 1 << 40), ("bagFree", 999)],
        &[("level", 300), ("xp", 1 << 30), ("xpMax", 1)],
    );
    let largest = with(
        &[("money", u32::MAX as i64), ("bagFree", 255)],
        &[("level", 255), ("xp", (1 << 24) - 1), ("xpMax", 1)],
    );
    assert_eq!(
        back(&big),
        as_json(&largest),
        "a number too large for its field is the field's largest value"
    );
    let mut later = fast();
    later.extend([7, 7]);
    assert_eq!(
        fast_json(&unpack_fast(&later).unwrap()),
        as_json(STATE),
        "bytes a later version adds at the end are skipped"
    );
    assert!(
        unpack_fast(&fast()[..FAST_LEN - 1]).is_err(),
        "a fast block shorter than version 1's is refused"
    );
}

#[test]
fn the_frame() {
    let plain = plain();
    assert!(
        plain.len() == 73
            && bytes_to_squares(&plain, 3).len() == 195
            && bytes_to_squares(&plain, 6).len() == 98,
        "section 3: a frame with no chunk is 73 bytes, 195 squares at depth 2 and 98 at depth 4"
    );
    assert!(
        [3, 6]
            .iter()
            .all(|&bits| squares_to_bytes(&bytes_to_squares(&plain, bits), bits, 73) == plain),
        "squares back to bytes drop the filling of the last square"
    );
    let frame = with_chunk();
    let got = unpack_frame(&frame).unwrap();
    assert!(
        (got.session, got.seq, got.dwell) == (4711, 9, 10)
            && fast_json(&got.fast) == as_json(STATE)
            && got.chunk == Some(chunk(4, 65535, 1, 3, b"\x00some bytes")),
        "a frame with a chunk comes back: session, seq (wrapped), dwell, fast block, chunk"
    );
    assert_eq!(
        unpack_frame(&plain).unwrap().chunk,
        None,
        "a frame with no object comes back with no chunk"
    );
    assert!(
        frame_length(&frame[..6]) == (7, false)
            && frame_length(&frame[..7]) == (7 + 58 + 6, false)
            && frame_length(&frame[..71]) == (frame.len(), true),
        "frame_length asks for more until it knows"
    );
    let mut bad = frame.clone();
    bad[20] ^= 1;
    assert!(
        unpack_frame(&bad).is_err(),
        "a changed byte fails the frame check"
    );
    let mut v2 = plain.clone();
    v2[0] = 2;
    resum(&mut v2);
    assert!(unpack_frame(&v2).is_err(), "an unknown version is refused");
    assert!(
        unpack_frame(&frame[..frame.len() - 1]).is_err(),
        "a frame cut short is refused"
    );
    let packs = |c: Chunk| pack_frame(1, 1, 10, b"", Some(&c)).is_err();
    assert!(
        packs(chunk(1, 1, 0, 1, b""))
            && packs(chunk(1, 1, 0, 13, b"x"))
            && packs(chunk(1, 1, 0, 1, &[0; 256])),
        "a chunk of 0 bytes, 13 chunks or 256 bytes cannot be packed"
    );
    let mut odd = plain.clone();
    odd[7 + 58 + 3] = 1;
    resum(&mut odd);
    assert!(
        unpack_frame(&odd).is_err(),
        "object id 0 with another object field set is refused"
    );
}

const TEXT: &str = r#"{"free": 12, "items": [[2318, 14], [4234, 3]]}"#;

#[test]
fn objects() {
    let mut spoiled = pack_object(Some(TEXT), true);
    spoiled[3] ^= 1;
    assert!(
        unpack_object(&spoiled).is_err(),
        "a changed byte fails the object check"
    );
    // Does not compress to 12 chunks.
    let long: String = (0..3000u32)
        .map(|i| char::from_u32(0x4E00 + i * 7919 % 20000).unwrap())
        .collect();
    let parts = chunks_of(&pack_object(Some(&long), true), 100);
    assert!(
        parts.len() == 1 && unpack_object(&parts[0]) == Ok((254, None)),
        "an object of more than 12 chunks is sent as format 254"
    );
    let mut latin = vec![0, 0xFF, 0xFE];
    latin.extend(check(&latin));
    assert!(
        unpack_object(&latin).is_err(),
        "an object that is not UTF-8 is refused as a ValueError"
    );
}

// --- joining chunks (section 6) ---

/// The frames that carry `text` as object 4 in chunks of 10 bytes, at a dwell of 0.1 s.
fn frames_for(text: &str, version: u16, session: u16) -> Vec<Frame> {
    let parts = chunks_of(&pack_object(Some(text), false), 10);
    let n = parts.len() as u8;
    parts
        .iter()
        .enumerate()
        .map(|(i, part)| {
            let c = chunk(4, version, i as u8, n, part);
            unpack_frame(&pack_frame(session, i as u32, 10, &fast(), Some(&c)).unwrap()).unwrap()
        })
        .collect()
}

/// The frames fed `step` seconds apart: the objects made, and the assembler.
fn run(frames: &[Frame], step: f64) -> (Vec<Done>, Assembler) {
    let mut a = Assembler::default();
    let out = frames
        .iter()
        .enumerate()
        .filter_map(|(i, f)| a.feed(f, i as f64 * step))
        .collect();
    (out, a)
}

fn made(text: &str) -> Done {
    (4, 0, Some(text.into()))
}

#[test]
fn joining_chunks() {
    let seq = frames_for(TEXT, 7, 4711);
    let text13 = TEXT.replace("12", "13");
    let other = frames_for(&text13, 8, 4711);
    let nothing: Vec<Done> = vec![];
    assert_eq!(
        run(&seq, 0.1).0,
        [made(TEXT)],
        "chunks in order make the object"
    );
    let thrice: Vec<Frame> = seq
        .iter()
        .flat_map(|f| [f.clone(), f.clone(), f.clone()])
        .collect();
    assert_eq!(
        run(&thrice, 0.1).0,
        [made(TEXT)],
        "the same chunk seen several times is ignored"
    );
    assert_eq!(
        run(&[&seq[..2], &seq[3..]].concat(), 0.1).0,
        nothing,
        "a gap drops the partial object"
    );
    let swapped = [&[seq[1].clone(), seq[0].clone()][..], &seq[2..]].concat();
    assert_eq!(
        run(&swapped, 0.1).0,
        nothing,
        "chunks out of order make nothing"
    );
    assert_eq!(
        run(&[&seq[..2], &other[2..]].concat(), 0.1).0,
        nothing,
        "chunks of two versions never mix"
    );
    let bare = unpack_frame(&plain()).unwrap();
    assert_eq!(
        run(&[&seq[..2], &[bare], &seq[2..]].concat(), 0.1).0,
        nothing,
        "a frame with no object in between drops the partial"
    );
    assert_eq!(
        run(&seq, 0.6).0,
        nothing,
        "a chunk that comes later than 5 x dwell after the last one does not join"
    );
    let mut stretch = frames_for(TEXT, 7, 4711);
    stretch[1].dwell = 100; // the next chunk comes 1 s later and claims a long dwell
    let mut a = Assembler::default();
    a.feed(&stretch[0], 0.0);
    let late: Vec<Done> = stretch[1..]
        .iter()
        .enumerate()
        .filter_map(|(i, f)| a.feed(f, 1.0 + i as f64 * 0.1))
        .collect();
    assert_eq!(
        late, nothing,
        "a later frame's longer dwell does not stretch the limit set when the last chunk was accepted"
    );
    let (twice, a) = run(&[&seq[..], &seq[..]].concat(), 0.1);
    assert!(
        twice == [made(TEXT)] && a.objects[&4].3 > 0.5,
        "a version seen whole again is not reported twice, but its time is renewed"
    );
    assert_eq!(
        run(&[&seq[..], &other[..]].concat(), 0.1).0,
        [made(TEXT), made(&text13)],
        "a new version is reported"
    );
    // Python reads the assembler's session; here it shows in what comes out: the partial of
    // the old session is not finished by the new one's chunks, and its object is new again.
    let changed = frames_for(TEXT, 7, 4712);
    assert!(
        run(&[&seq[..2], &changed[..]].concat(), 0.1).0 == [made(TEXT)]
            && run(&[&seq[..2], &changed[2..]].concat(), 0.1).0 == nothing
            && run(&[&seq[..], &changed[..]].concat(), 0.1).0 == [made(TEXT), made(TEXT)],
        "a new session forgets what was held and starts again"
    );
}

// --- the row through an image (sections 3 and 5) ---

/// Levels 96, 127 and 11 of 127: they read 76, 100 and 9 per cent.
const LEVELS: [Option<f64>; 4] = [Some(0.75), Some(1.0), Some(0.09), None];
const READ: [Option<i64>; 4] = [Some(76), Some(100), Some(9), None];

/// How the Python test's `image` draws a row.
struct At {
    square: usize,
    scale: f64,
    bend: Option<Bend>,
    dx: i64,
    dy: i64,
    /// Pixels of noise after the row.
    beyond: usize,
}

impl Default for At {
    fn default() -> Self {
        At {
            square: 2,
            scale: 1.0,
            bend: None,
            dx: 0,
            dy: 0,
            beyond: 40,
        }
    }
}

fn scaled(scale: f64) -> At {
    At {
        scale,
        ..At::default()
    }
}

/// The row drawn into a 60-line image whose background is noise, then read.
fn image(session: u16, depth: u8, levels: [Option<f64>; 4], frame: &[u8], at: At) -> Option<Row> {
    let colours = row_colours(session, depth, levels, frame);
    let cells: String = colours
        .iter()
        .enumerate()
        .map(|(i, [r, g, b])| {
            format!(
                "{} 0 {s} {s} {r:.6} {g:.6} {b:.6}\n",
                i * at.square,
                s = at.square
            )
        })
        .collect();
    let drawn = (colours.len() as f64 * at.square as f64 * at.scale) as usize;
    let width = 400.max(drawn + at.dx as usize + at.beyond);
    let mut data = render(&cells, at.scale, at.dx, at.dy, width, 60).unwrap();
    if let Some(bend) = at.bend {
        // After the 14 + 124 bytes of the header: blue, green, red, alpha.
        for p in data[138..].as_chunks_mut::<4>().0 {
            let [r, g, b] = bend([p[2], p[1], p[0]]);
            p[..3].copy_from_slice(&[b, g, r]);
        }
    }
    read_row(&Bitmap::new(&data).unwrap(), None)
}

fn frame_of(row: &Option<Row>) -> Option<&Frame> {
    row.as_ref().and_then(|r| r.frame.as_ref())
}

/// Blue leaks into green, as on the display of 12 Nov 2026.
fn leak([r, g, b]: [u8; 3]) -> [u8; 3] {
    [r, (g as u32 + b as u32 * 46 / 255).min(255) as u8, b]
}

/// A display that darkens the levels: each channel to the power 2.5.
fn dark(c: [u8; 3]) -> [u8; 3] {
    c.map(|v| (255.0 * (v as f64 / 255.0).powf(2.5)).round_ties_even() as u8)
}

#[test]
fn rows_in_images() {
    let frame = with_chunk();
    let got = unpack_frame(&frame).unwrap();
    for depth in [4, 2] {
        for square in [2, 3, 4] {
            let row = image(
                4711,
                depth,
                LEVELS,
                &frame,
                At {
                    square,
                    ..At::default()
                },
            )
            .unwrap();
            assert!(
                row.frame.as_ref() == Some(&got)
                    && row.session == Some(4711)
                    && row.depth == Some(depth)
                    && row.levels == READ,
                "depth {depth}, {square} pixels a square: the frame, the session and the level squares come back"
            );
        }
    }
    let row = image(
        4711,
        4,
        LEVELS,
        &frame,
        At {
            dx: 13,
            dy: 7,
            ..At::default()
        },
    )
    .unwrap();
    let (left, top, _, _) = row.r#box.unwrap();
    assert!(
        row.frame.as_ref() == Some(&got) && (left, top) == (13, 7),
        "the row is found away from the corner, and its box is reported"
    );
    assert_eq!(
        row.apart,
        Some(85),
        "at depth 4 the nearest two palette colours are reported: 85 apart on a clean image"
    );
    let leaky = image(
        4711,
        4,
        LEVELS,
        &frame,
        At {
            bend: Some(leak),
            ..At::default()
        },
    )
    .unwrap();
    assert!(
        leaky.frame.as_ref() == Some(&got) && leaky.apart.unwrap() < 85,
        "depth 4 reads through the blue-into-green leak, by the palette"
    );
    let levels = [Some(1.0), Some(0.0), Some(0.999), Some(0.004)];
    assert_eq!(
        image(1, 2, levels, &plain(), At::default()).unwrap().levels,
        [Some(100), Some(0), Some(100), Some(0)],
        "a full level reads 100 and an empty one 0"
    );
}

/// The longest frame, 328 bytes.
fn longest() -> Vec<u8> {
    let all: Vec<u8> = (0..255).collect();
    pack_frame(4711, 9, 10, &fast(), Some(&chunk(4, 7, 0, 1, &all))).unwrap()
}

#[test]
fn the_longest_frame_at_every_scale() {
    let full = longest();
    let want = unpack_frame(&full).unwrap();
    for depth in [2, 4] {
        let reads =
            |scale: f64| frame_of(&image(4711, depth, LEVELS, &full, scaled(scale))) == Some(&want);
        // Squares of 2.003 to 6.6 pixels.
        for scale in [1.0015, 1.1, 1.25, 1.37, 1.5, 2.0, 3.3] {
            assert!(
                reads(scale),
                "depth {depth} at a scale of {scale}: the longest frame comes back"
            );
        }
        let missed: Vec<f64> = (100..300)
            .step_by(13)
            .map(|k| k as f64 / 100.0)
            .filter(|&s| !reads(s))
            .collect();
        assert_eq!(
            missed,
            Vec::<f64>::new(),
            "depth {depth}: every scale from 1.00 to 2.95 in steps of 0.13 reads the longest frame"
        );
    }
}

#[test]
fn hard_rows_at_1_0015() {
    let a252 = "A".repeat(252);
    let letter = pack_object(Some(&a252), false);
    let same = pack_frame(4711, 9, 10, &fast(), Some(&chunk(4, 7, 0, 1, &letter))).unwrap();
    let clock: State = &[("clock", &[("clock", 1)])];
    let sparse = pack_frame(
        4711,
        9,
        10,
        &pack_fast(clock),
        Some(&chunk(1, 7, 0, 1, &letter)),
    )
    .unwrap();
    let plain = plain();
    for depth in [2, 4] {
        let row = image(4711, depth, LEVELS, &same, scaled(1.0015));
        assert!(
            frame_of(&row) == Some(&unpack_frame(&same).unwrap()),
            "depth {depth} at 1.0015: a chunk of one repeated letter, whose squares differ less than two-level digits show"
        );
        let darkened = image(
            4711,
            depth,
            LEVELS,
            &same,
            At {
                bend: Some(dark),
                ..scaled(1.0015)
            },
        );
        assert!(
            frame_of(&darkened) == Some(&unpack_frame(&same).unwrap())
                && (depth == 2 || darkened.unwrap().apart == Some(16)),
            "depth {depth} at 1.0015 on a display that darkens the levels (the nearest colours 16 apart): still read"
        );
        for beyond in [40, 2200] {
            let row = image(
                4711,
                depth,
                LEVELS,
                &sparse,
                At {
                    beyond,
                    ..scaled(1.0015)
                },
            );
            assert!(
                frame_of(&row) == Some(&unpack_frame(&sparse).unwrap()),
                "depth {depth} at 1.0015, {beyond} pixels beyond: a frame of long black stretches (only the clock known) and a repeated letter"
            );
        }
        for scale in [1.0, 1.0015, 1.37] {
            let wide = image(
                4711,
                depth,
                LEVELS,
                &plain,
                At {
                    beyond: 2200,
                    ..scaled(scale)
                },
            );
            assert!(
                frame_of(&wide) == Some(&unpack_frame(&plain).unwrap()),
                "depth {depth} at {scale}: a short row with 2200 pixels of the game beyond its end is read"
            );
        }
    }
}

#[test]
fn squares_under_2_pixels() {
    let clock: State = &[("clock", &[("clock", 1)])];
    let short = pack_frame(4711, 9, 10, &pack_fast(clock), None).unwrap();
    let full = longest();
    let refused = |row: &Row| {
        row.frame.is_none()
            && row
                .why
                .as_deref()
                .is_some_and(|w| w.contains("under 2 pixels"))
    };
    for depth in [2, 4] {
        let row = image(4711, depth, LEVELS, &short, scaled(0.9)).unwrap();
        assert!(
            refused(&row),
            "depth {depth} with squares of 1.8 pixels: refused too, though a short frame could be guessed"
        );
        let small = image(4711, depth, LEVELS, &full, scaled(0.75)).unwrap();
        assert!(
            refused(&small) && !Quality::default().note(&small),
            "depth {depth} with squares of 1.5 pixels: refused with the reason, not misread"
        );
    }
}

#[test]
fn rows_that_are_not_read() {
    let frame = with_chunk();
    let lost = image(
        4711,
        4,
        LEVELS,
        &frame,
        At {
            bend: Some(crush),
            ..At::default()
        },
    )
    .unwrap();
    assert!(
        lost.frame.is_none()
            && lost.session == Some(4711)
            && lost.levels == READ
            && lost.apart == Some(0)
            && lost.why.is_some(),
        "when six bits cannot be read, the session and the levels still can, and the reason is given"
    );
    assert!(
        Quality::default().note(&lost),
        "a palette whose colours came back too close asks for depth 2 at once"
    );
    // The row's first line is the image's last.
    let cut = image(
        4711,
        2,
        LEVELS,
        &frame,
        At {
            dy: 59,
            ..At::default()
        },
    );
    assert!(
        cut.is_none_or(|r| r.frame.is_none()),
        "a row cut off by the image's edge is not read, and nothing breaks"
    );
    let wrong = pack_frame(4712, 9, 10, &fast(), None).unwrap();
    assert!(
        image(4711, 2, LEVELS, &wrong, At::default())
            .unwrap()
            .frame
            .is_none(),
        "a frame whose session is not the row's is refused"
    );
    let empty = Bitmap::new(&render("", 1.0, 0, 0, 400, 60).unwrap()).unwrap();
    assert!(
        read_row(&empty, None).is_none(),
        "an image without a row gives nothing"
    );
}

// --- asking for the fall-back (section 3) ---

#[test]
fn the_fall_back_thresholds() {
    let frame = with_chunk();
    let good = image(4711, 4, LEVELS, &frame, At::default()).unwrap();
    let far = Row {
        frame: None,
        apart: Some(85),
        ..good.clone()
    };
    // Whether each of `n` frames asks, when every `every`th one failed.
    let asked = |every: usize, n: usize| -> Vec<bool> {
        let mut q = Quality::default();
        (0..n)
            .map(|i| q.note(if i % every == 0 { &far } else { &good }))
            .collect()
    };
    let mut q = Quality::default();
    assert!(
        (0..300).all(|_| !q.note(&good)),
        "frames that pass never ask"
    );
    assert!(
        asked(20, 400).contains(&true),
        "more than 2 failed frames in 100, over the last 200, asks"
    );
    assert!(
        !asked(100, 400).contains(&true),
        "1 failed frame in 100 does not"
    );
    let never = asked(1, 200);
    assert!(
        never[199] && !never[..199].contains(&true),
        "a reader that never read a depth-4 frame asks after 200 frames, not before"
    );
    let depth2 = image(4711, 2, LEVELS, &frame, At::default()).unwrap();
    assert!(
        !Quality::default().note(&depth2),
        "a row at depth 2 never asks"
    );
}
