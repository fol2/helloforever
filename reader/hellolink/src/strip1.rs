//! The live-state strip, format 1 (docs/STRIP.md): the format and the row reader.
//! A port of tools/strip1.py; every function behaves as its Python namesake.
//! No file, no screen, no clock: values in, values out.

use crate::bitmap::Bitmap;
use std::f64::consts::PI;

pub const VERSION: u8 = 1;
pub const FINDER: [u8; 8] = [4, 2, 1, 7, 0, 6, 3, 5];
pub const LEVEL_NAMES: [&str; 4] = ["health", "power", "targetHealth", "petHealth"];
const LEVELS_AT: usize = 8;
const DEPTH_AT: usize = 20;
const SESSION_AT: usize = 21;
const PALETTE_AT: usize = 27;
pub const MAX_CHUNKS: u8 = 12;
pub const MAX_CHUNK: usize = 255;
/// Pixels a square in the capture, below which a reader refuses the row.
const MIN_SQUARE: f64 = 2.0;
/// Two colours less than this apart (the largest channel difference) count as too close.
pub const NEAR: i32 = 12;

/// Section 5: the groups of the fast block in order, each with its fields and their bytes.
pub const GROUPS: [(&str, &[(&str, usize)]); 14] = [
    ("clock", &[("clock", 2)]),
    ("health", &[("healthMax", 3)]),
    ("power", &[("powerMax", 3), ("powerType", 1)]),
    ("level", &[("level", 1), ("xp", 3), ("xpMax", 3)]),
    ("state", &[("flags", 2)]),
    ("cast", &[("spell", 3), ("tenths", 1)]),
    ("target", &[("level", 1), ("flags", 1), ("nameHash", 2)]),
    ("pet", &[("healthMax", 3)]),
    ("position", &[("map", 2), ("x", 2), ("y", 2), ("facing", 1)]),
    ("purse", &[("money", 4), ("bagFree", 1)]),
    ("hand", &[("item", 3), ("enchant", 2)]),
    ("loot", &[("counter", 1), ("item", 3), ("quantity", 1)]),
    ("uiError", &[("error", 2), ("counter", 1)]),
    ("threat", &[("player", 1), ("pet", 1)]),
];
pub const FAST_LEN: usize = 58;

/// The fast block: each group in the order of GROUPS, with its fields, or None when unknown.
pub type Fast = Vec<(&'static str, Option<Vec<(&'static str, u32)>>)>;

/// An object's chunk: objectId, objectVersion, chunkIndex, chunkCount and the bytes.
#[derive(Clone, Debug, PartialEq)]
pub struct Chunk {
    pub oid: u8,
    pub version: u16,
    pub index: u8,
    pub count: u8,
    pub data: Vec<u8>,
}

#[derive(Clone, Debug, PartialEq)]
pub struct Frame {
    pub version: u8,
    pub session: u16,
    pub seq: u16,
    pub dwell: u8,
    pub fast: Fast,
    pub chunk: Option<Chunk>,
}

/// Section 7: two sums modulo 255, written s1 then s2.
pub fn check(data: &[u8]) -> [u8; 2] {
    let (mut s1, mut s2) = (0u32, 0u32);
    for &b in data {
        s1 = (s1 + b as u32) % 255;
        s2 = (s2 + s1) % 255;
    }
    [s1 as u8, s2 as u8]
}

fn be(data: &[u8]) -> u32 {
    data.iter().fold(0, |n, &b| n << 8 | b as u32)
}

// --- the fast block (section 5) ---

/// `state` names the known groups and their fields; a group not named is unknown. A number
/// larger than its field holds is sent as the field's largest value.
pub fn pack_fast(state: &[(&str, &[(&str, i64)])]) -> Vec<u8> {
    let mut known = 0u16;
    let mut body = Vec::new();
    for (i, (name, fields)) in GROUPS.iter().enumerate() {
        let values = state.iter().find(|(n, _)| n == name).map(|(_, v)| *v);
        if values.is_some() {
            known |= 0x8000 >> i;
        }
        for (field, size) in fields.iter() {
            let value = values
                .and_then(|v| v.iter().find(|(f, _)| f == field))
                .map_or(0, |(_, v)| *v);
            let value = value.clamp(0, (1i64 << (8 * size)) - 1) as u64;
            body.extend_from_slice(&value.to_be_bytes()[8 - size..]);
        }
    }
    let mut out = known.to_be_bytes().to_vec();
    out.extend(body);
    out
}

/// The groups this reader knows; bytes after them (a later version's) are skipped.
pub fn unpack_fast(data: &[u8]) -> Result<Fast, String> {
    if data.len() < FAST_LEN {
        return Err(format!(
            "fast block of {} bytes, version 1 has {}",
            data.len(),
            FAST_LEN
        ));
    }
    let known = be(&data[..2]);
    let mut at = 2;
    let mut out = Vec::new();
    for (i, (name, fields)) in GROUPS.iter().enumerate() {
        let mut values = Vec::new();
        for (field, size) in fields.iter() {
            values.push((*field, be(&data[at..at + size])));
            at += size;
        }
        out.push((*name, (known & (0x8000 >> i) != 0).then_some(values)));
    }
    Ok(out)
}

// --- the frame (section 3) ---

pub fn pack_frame(
    session: u16,
    seq: u32,
    dwell: u8,
    fast: &[u8],
    chunk: Option<&Chunk>,
) -> Result<Vec<u8>, String> {
    let mut body = vec![VERSION];
    body.extend(session.to_be_bytes());
    body.push(dwell);
    body.extend(((seq % 65536) as u16).to_be_bytes());
    body.push(fast.len() as u8);
    body.extend(fast);
    match chunk {
        None => body.extend([0; 6]),
        Some(c) => {
            if !((1..=MAX_CHUNK).contains(&c.data.len())
                && (1..=MAX_CHUNKS).contains(&c.count)
                && c.index < c.count
                && c.oid >= 1)
            {
                return Err("bad chunk".into());
            }
            body.push(c.oid);
            body.extend(c.version.to_be_bytes());
            body.extend([c.index, c.count, c.data.len() as u8]);
            body.extend(&c.data);
        }
    }
    let sum = check(&body);
    body.extend(sum);
    Ok(body)
}

/// The whole frame's length once enough of it is read, else how many bytes are needed to
/// know more: (length, enough).
pub fn frame_length(prefix: &[u8]) -> (usize, bool) {
    if prefix.len() < 7 {
        return (7, false);
    }
    let at = 7 + prefix[6] as usize + 6; // the end of the object header
    if prefix.len() < at {
        return (at, false);
    }
    (at + prefix[at - 1] as usize + 2, true)
}

/// The frame's fields, or the reason it is refused: a reader reports nothing from it.
pub fn unpack_frame(data: &[u8]) -> Result<Frame, String> {
    let (length, enough) = frame_length(data);
    if !enough || data.len() < length {
        return Err("frame cut short".into());
    }
    let data = &data[..length];
    if data[0] != VERSION {
        return Err(format!("unknown version {}", data[0]));
    }
    if check(&data[..length - 2]) != data[length - 2..] {
        return Err("frame check failed".into());
    }
    let at = 7 + data[6] as usize;
    let part = &data[at..at + 6];
    let (oid, index, count, size) = (part[0], part[3], part[4], part[5] as usize);
    let chunk = if oid == 0 {
        if part.iter().any(|&b| b != 0) {
            return Err("object id 0 with other fields set".into());
        }
        None
    } else {
        if !(size >= 1 && (1..=MAX_CHUNKS).contains(&count) && index < count) {
            return Err("bad object part".into());
        }
        Some(Chunk {
            oid,
            version: be(&part[1..3]) as u16,
            index,
            count,
            data: data[at + 6..at + 6 + size].to_vec(),
        })
    };
    let session = be(&data[1..3]) as u16;
    let dwell = data[3];
    if session == 0 || !(5..=100).contains(&dwell) {
        return Err("bad session or dwell".into());
    }
    Ok(Frame {
        version: data[0],
        session,
        seq: be(&data[4..6]) as u16,
        dwell,
        fast: unpack_fast(&data[7..at])?,
        chunk,
    })
}

// --- objects (section 6) ---

/// The object bytes for a text; None gives format 255 (the addon cannot read it now).
pub fn pack_object(text: Option<&str>, compress: bool) -> Vec<u8> {
    let mut body = match text {
        None => vec![255],
        Some(t) if compress => {
            let mut b = vec![1];
            b.extend(miniz_oxide::deflate::compress_to_vec(t.as_bytes(), 9));
            b
        }
        Some(t) => {
            let mut b = vec![0];
            b.extend(t.as_bytes());
            b
        }
    };
    let sum = check(&body);
    body.extend(sum);
    body
}

/// (format, text): the text for formats 0 and 1, None for 254 and 255.
pub fn unpack_object(obj: &[u8]) -> Result<(u8, Option<String>), String> {
    if obj.len() < 3 || check(&obj[..obj.len() - 2]) != obj[obj.len() - 2..] {
        return Err("object check failed".into());
    }
    let (kind, content) = (obj[0], &obj[1..obj.len() - 2]);
    let text =
        |raw: Vec<u8>| String::from_utf8(raw).map_err(|e| format!("object is not UTF-8: {e}"));
    match kind {
        254 | 255 if content.is_empty() => Ok((kind, None)),
        254 | 255 => Err(format!("format {kind} with content")),
        0 => Ok((0, Some(text(content.to_vec())?))),
        1 => {
            // A raw Deflate stream, or one with a zlib header.
            let raw = miniz_oxide::inflate::decompress_to_vec(content)
                .or_else(|_| miniz_oxide::inflate::decompress_to_vec_zlib(content))
                .map_err(|e| format!("object does not inflate: {e}"))?;
            Ok((1, Some(text(raw)?)))
        }
        _ => Err(format!("unknown object format {kind}")),
    }
}

/// An object made whole: its id, format and text.
pub type Done = (u8, u8, Option<String>);

/// An object held whole: version, format, text, and when it was last seen whole.
pub type Held = (u16, u8, Option<String>, f64);

/// An object being joined: (objectId, objectVersion, chunkCount), the chunks so far, and
/// the time by which the next chunk must come.
type Partial = ((u8, u16, u8), Vec<Vec<u8>>, f64);

/// Section 6, "Joining": builds objects from consecutive chunks.
#[derive(Default)]
pub struct Assembler {
    session: Option<u16>,
    partial: Option<Partial>,
    /// The object part accepted last, to know a repeat.
    last: Option<Option<Chunk>>,
    pub objects: std::collections::BTreeMap<u8, Held>,
    /// objectId -> the chunk that completed the object now held.
    tails: std::collections::BTreeMap<u8, Chunk>,
}

impl Assembler {
    /// Takes a frame that passed its check; returns the object when a new version of it
    /// completes. A version seen whole again only renews its time in `objects`.
    pub fn feed(&mut self, frame: &Frame, now: f64) -> Option<Done> {
        if self.session != Some(frame.session) {
            *self = Assembler {
                session: Some(frame.session),
                ..Assembler::default()
            };
        }
        // The limit was set when the last chunk was accepted, from that frame's dwell.
        let limit = now + (5 * frame.dwell as u32) as f64 / 100.0;
        if self.partial.as_ref().is_some_and(|p| now > p.2) {
            self.partial = None;
        }
        let chunk = &frame.chunk;
        // Python starts with `last = None`, which equals a frame with no chunk.
        if self.last.as_ref().unwrap_or(&None) == chunk {
            // The very chunk that completed an object held whole renews that object's time.
            if let Some(c) = chunk
                && self.tails.get(&c.oid) == Some(c)
                && let Some(held) = self.objects.get_mut(&c.oid)
            {
                held.3 = now;
            }
            return None;
        }
        self.last = Some(chunk.clone());
        let c = match chunk {
            None => {
                self.partial = None;
                return None;
            }
            Some(c) => c,
        };
        let key = (c.oid, c.version, c.count);
        let mut parts = match self.partial.take() {
            _ if c.index == 0 => vec![],
            Some((k, parts, _)) if k == key && parts.len() == c.index as usize => parts,
            _ => return None,
        };
        parts.push(c.data.clone());
        if parts.len() < c.count as usize {
            self.partial = Some((key, parts, limit));
            return None;
        }
        let (kind, text) = unpack_object(&parts.concat()).ok()?;
        let fresh = self.objects.get(&c.oid).is_none_or(|h| h.0 != c.version);
        self.objects
            .insert(c.oid, (c.version, kind, text.clone(), now));
        self.tails.insert(c.oid, c.clone());
        fresh.then_some((c.oid, kind, text))
    }
}

// --- bytes and squares (section 2, "Bytes from squares") ---

pub fn bytes_to_squares(data: &[u8], bits: usize) -> Vec<u8> {
    let total = data.len() * 8;
    (0..total.div_ceil(bits))
        .map(|s| {
            (0..bits).fold(0u8, |n, k| {
                let at = s * bits + k;
                let bit = at < total && data[at / 8] >> (7 - at % 8) & 1 == 1;
                n << 1 | bit as u8
            })
        })
        .collect()
}

pub fn squares_to_bytes(squares: &[u8], bits: usize, count: usize) -> Vec<u8> {
    let bit = |at: usize| squares[at / bits] >> (bits - 1 - at % bits) & 1;
    (0..count)
        .map(|i| (0..8).fold(0u8, |n, k| n << 1 | bit(i * 8 + k)))
        .collect()
}

pub fn squares_for(count: usize, bits: usize) -> usize {
    (count * 8).div_ceil(bits)
}

fn digit_colour(d: u8) -> [f64; 3] {
    [(d >> 2 & 1) as f64, (d >> 1 & 1) as f64, (d & 1) as f64]
}

fn palette_colour(i: u8) -> [f64; 3] {
    [
        (i / 16) as f64 / 3.0,
        (i / 4 % 4) as f64 / 3.0,
        (i % 4) as f64 / 3.0,
    ]
}

/// The three digits of a level square triple for a per cent (0 to 1), or black for None.
fn level_digits(per_cent: Option<f64>) -> [u8; 3] {
    match per_cent {
        None => [0, 0, 0],
        Some(p) => {
            let level = (p * 128.0).floor().min(127.0) as u8;
            [
                level / 16,
                level / 2 % 8,
                if level % 2 == 1 { 6 } else { 2 },
            ]
        }
    }
}

/// The row as (red, green, blue) from 0 to 1 a square: what the addon draws (section 2).
pub fn row_colours(
    session: u16,
    depth: u8,
    levels: [Option<f64>; 4],
    frame: &[u8],
) -> Vec<[f64; 3]> {
    let mut digits = FINDER.to_vec();
    for value in levels {
        digits.extend(level_digits(value));
    }
    digits.push(depth);
    let s = session as u32;
    digits.extend(bytes_to_squares(&[(s >> 16) as u8, (s >> 8) as u8, s as u8], 3)[2..].iter());
    let mut out: Vec<[f64; 3]> = digits.into_iter().map(digit_colour).collect();
    if depth == 4 {
        out.extend((0..64).map(palette_colour));
        out.extend(bytes_to_squares(frame, 6).into_iter().map(palette_colour));
    } else {
        out.extend(bytes_to_squares(frame, 3).into_iter().map(digit_colour));
    }
    out
}

// --- reading a row from a bitmap (sections 1 to 5) ---

/// What `read_row` found. A row whose squares are under 2 pixels has only `why` and `square`.
#[derive(Clone, Debug, PartialEq)]
pub struct Row {
    /// From the two-level squares.
    pub session: Option<u32>,
    pub depth: Option<u8>,
    /// Per cent, 0 to 100, or None, for each of LEVEL_NAMES.
    pub levels: [Option<i64>; 4],
    /// None when no width gave a frame that passes its check.
    pub frame: Option<Frame>,
    /// The reason when `frame` is None.
    pub why: Option<String>,
    /// Depth 4: how far apart the nearest two palette colours came back.
    pub apart: Option<i32>,
    /// The square's side in pixels.
    pub square: f64,
    /// Left, top, right, bottom of what was read, for later captures.
    pub r#box: Option<(i64, i64, i64, i64)>,
    /// The row's left edge, its top and the square's side: pass it back as the hint.
    pub grid: Option<(f64, i64, f64)>,
    /// The frame's bytes as read, also when they fail.
    pub raw: Option<Vec<u8>>,
    pub palette: Option<Vec<[u8; 3]>>,
}

/// A finder's match: the eight runs of digits, each (start, end).
type Match = [(usize, usize); 8];

/// The finder's matches in a line of digits, left to right, as Python's FINDER_RE.finditer:
/// eight runs in a row with the finder's digits; each run is whole.
fn finder_matches(line: &[u8]) -> Vec<Match> {
    let mut runs = Vec::new();
    let mut start = 0;
    for x in 1..=line.len() {
        if x == line.len() || line[x] != line[start] {
            runs.push((line[start], start, x));
            start = x;
        }
    }
    let mut out = Vec::new();
    let mut i = 0;
    while i + 8 <= runs.len() {
        if (0..8).all(|k| runs[i + k].0 == FINDER[k]) {
            out.push(std::array::from_fn(|k| (runs[i + k].1, runs[i + k].2)));
            i += 8;
        } else {
            i += 1;
        }
    }
    out
}

/// Python's round() on a float: halves go to the even number.
fn round(x: f64) -> f64 {
    x.round_ties_even()
}

/// The first row found in the bitmap, or None. `hint` is the `grid` of an earlier read of
/// the same place: it is tried first, which saves the search.
pub fn read_row(bmp: &Bitmap, hint: Option<(f64, i64, f64)>) -> Option<Row> {
    if let Some((x0, top, w)) = hint
        && let Some(found) = row_at(bmp, x0, top, w)
        && found.frame.is_some()
    {
        return Some(found);
    }
    for y in 0..bmp.height {
        for m in finder_matches(bmp.digits(y)) {
            let start = m[1].0 as f64;
            let measured = (m[7].0 - m[1].0) as f64 / 6.0;
            if measured < 1.0
                || m[1..7]
                    .iter()
                    .any(|r| ((r.1 - r.0) as f64 - measured).abs() > f64::max(1.0, measured / 4.0))
            {
                continue;
            }
            let mut top = y as i64;
            while top > 0
                && (0..8).all(|i| {
                    bmp.digit(start + (i as f64 - 0.5) * measured, (top - 1) as f64)
                        == Some(FINDER[i])
                })
            {
                top -= 1;
            }
            let refused = Row {
                session: None,
                depth: None,
                levels: [None; 4],
                frame: None,
                why: Some(format!(
                    "squares of about {measured:.1} pixels: under {MIN_SQUARE} pixels a square the row is not read"
                )),
                apart: None,
                square: measured,
                r#box: None,
                grid: None,
                raw: None,
                palette: None,
            };
            // A square under 2 pixels is refused, not guessed (strip1.py says why).
            if measured < MIN_SQUARE - 0.25 {
                return Some(refused);
            }
            // First the grid that fits the edges along the whole row; then the widths and
            // origins around the measured one, nearest first.
            let line = (top as f64 + measured / 2.0) as i64;
            let mut tries = if line < bmp.height as i64 {
                fit(&edges(bmp, line as usize, m[1].0), &m)
            } else {
                vec![]
            };
            for k in 0..61i32 {
                let sign = if k % 2 == 1 { 1.0 } else { -1.0 };
                let wide = measured + ((k + 1) / 2) as f64 * 0.01 * sign;
                tries.extend([0.0, -0.5, 0.5].map(|shift| (start - wide + shift, wide)));
            }
            let mut best = None;
            for (x0, w) in tries {
                if w < MIN_SQUARE - 0.005 {
                    continue;
                }
                let Some(found) = row_at(bmp, x0, top, w) else {
                    continue;
                };
                if found.frame.is_some() {
                    return Some(found);
                }
                best = best.or(Some(found));
            }
            if best.is_some() {
                return best;
            }
            if measured < MIN_SQUARE {
                return Some(refused);
            }
        }
    }
    None
}

/// Where the colour changes along a line, from `start` on: the pixels whose red, green or
/// blue differs from the pixel before by NEAR or more.
fn edges(bmp: &Bitmap, line: usize, start: usize) -> Vec<usize> {
    let y = line as f64;
    let mut before = if start > 0 {
        bmp.rgb((start - 1) as f64, y)
    } else {
        None
    };
    let mut out = Vec::new();
    for x in start..bmp.width {
        let now = bmp.rgb(x as f64, y);
        if let (Some(a), Some(b)) = (now, before)
            && (0..3).any(|i| (a[i] as i32 - b[i] as i32).abs() >= NEAR)
        {
            out.push(x);
        }
        before = now;
    }
    out
}

/// A running sum with Neumaier's compensation, as CPython 3.14's sum() adds the parts of
/// complex numbers (`cs_add`, `cs_to_double` in Python/bltinmodule.c). Python 3.12 and 3.13
/// add them plainly, so their last bits can differ from this.
fn add(sum: (f64, f64), x: f64) -> (f64, f64) {
    let (hi, lo) = sum;
    let t = hi + x;
    let lo = if hi.abs() >= x.abs() {
        lo + ((hi - t) + x)
    } else {
        lo + ((x - t) + hi)
    };
    (t, lo)
}

fn total(sum: (f64, f64)) -> f64 {
    if sum.1 != 0.0 && sum.1.is_finite() {
        sum.0 + sum.1
    } else {
        sum.0
    }
}

/// The sum of the edges as unit vectors at this width, as Python sums complex numbers.
fn turns(some: &[usize], width: f64) -> (f64, f64) {
    let turn = 2.0 * PI / width;
    let (re, im) = some.iter().fold(((0.0, 0.0), (0.0, 0.0)), |(re, im), &x| {
        let a = turn * x as f64;
        (add(re, a.cos()), add(im, a.sin()))
    });
    (total(re), total(im))
}

/// How well the edges share one position within a square of this width: 1 when they all do.
fn lined_up(some: &[usize], width: f64) -> f64 {
    let (re, im) = turns(some, width);
    re.hypot(im) / some.len() as f64
}

/// The width within `reach` of `w` for which the edges line up best, and the step searched.
fn best_width(some: &[usize], w: f64, reach: f64) -> (f64, f64) {
    let span = (some[some.len() - 1] - some[0]).max(1);
    let step = w * w / (4 * span) as f64;
    let (mut best, mut best_w) = (-1.0, w);
    let steps = (reach / step) as i64 + 1;
    for n in -steps..=steps {
        let cand = w + n as f64 * step;
        if cand > 0.0 {
            let score = lined_up(some, cand);
            if score > best {
                (best, best_w) = (score, cand);
            }
        }
    }
    (best_w, step)
}

/// The origins and square widths (two candidates) that best fit the edges between squares
/// along a line. Fewer than eight edges give nothing. strip1.py's `_fit` explains the method.
fn fit(edges: &[usize], m: &Match) -> Vec<(f64, f64)> {
    if edges.len() < 8 {
        return vec![];
    }
    let w = (m[7].0 - m[1].0) as f64 / 6.0;
    let mut kept = edges[..edges.len().min(40)].to_vec();
    let (mut w, mut step) = best_width(&kept, w, 0.2 * w);
    let (mut at, mut refit) = (40, 160);
    while at < edges.len() {
        let run = &edges[at..edges.len().min(at + 40)];
        if (run[0] - kept[kept.len() - 1]) as f64 > 40.0 * w {
            break;
        }
        if lined_up(run, w) < 0.4 {
            // The row ended, or the width is not fine enough yet for a run this far out.
            let mut both = kept.clone();
            both.extend(run);
            let (sharper, sharper_step) = best_width(&both, w, 6.0 * step);
            if lined_up(run, sharper) < 0.4 {
                break;
            }
            (w, step) = (sharper, sharper_step);
        }
        kept.extend(run);
        at += 40;
        if kept.len() >= refit {
            (w, step) = best_width(&kept, w, 6.0 * step);
            refit *= 4;
        }
    }
    let (w, _) = best_width(&kept, w, 6.0 * step);
    // A width w and the width w / (w - 1) line the edges up equally well: both are returned.
    let other = if w > 1.0 { w / (w - 1.0) } else { w };
    [w, other]
        .iter()
        .map(|&width| {
            let turn = 2.0 * PI / width;
            let (re, im) = turns(&kept, width);
            let phase = im.atan2(re) / turn;
            let near = m[1].0 as f64 - width;
            (phase + round((near - phase) / width) * width, width)
        })
        .collect()
}

/// The digits of the six session squares as one number, most significant first.
fn octal(digits: &[u8]) -> u32 {
    digits.iter().fold(0, |n, &d| n << 3 | d as u32)
}

fn row_at(bmp: &Bitmap, x0: f64, top: i64, w: f64) -> Option<Row> {
    let mid = top as f64 + w / 2.0;
    let digit = |i: usize| bmp.digit(x0 + (i as f64 + 0.5) * w, mid);
    let head: Vec<u8> = (0..PALETTE_AT).map(digit).collect::<Option<_>>()?;
    if head[..8] != FINDER || !matches!(head[DEPTH_AT], 2 | 4) {
        return None;
    }
    let depth = head[DEPTH_AT];
    let session = octal(&head[SESSION_AT..PALETTE_AT]);
    let levels = std::array::from_fn(|v| {
        let [a, b, c] = [0, 1, 2].map(|k| head[LEVELS_AT + 3 * v + k] as i64);
        matches!(c, 2 | 6)
            .then(|| round(100.0 * (a * 16 + b * 2 + (c == 6) as i64) as f64 / 127.0) as i64)
    });
    if session == 0 {
        return None;
    }
    let mut out = Row {
        session: Some(session),
        depth: Some(depth),
        levels,
        frame: None,
        why: None,
        apart: None,
        square: w,
        r#box: None,
        grid: Some((x0, top, w)),
        raw: None,
        palette: None,
    };
    let (bits, first) = if depth == 4 {
        (6, PALETTE_AT + 64)
    } else {
        (3, PALETTE_AT)
    };
    let palette: Vec<[u8; 3]> = if depth == 4 {
        // No palette, no frame: not a row.
        let p: Vec<_> = (0..64)
            .map(|i| bmp.rgb(x0 + ((PALETTE_AT + i) as f64 + 0.5) * w, mid))
            .collect::<Option<_>>()?;
        let gap = |a: &[u8; 3], b: &[u8; 3]| {
            (0..3)
                .map(|k| (a[k] as i32 - b[k] as i32).abs())
                .max()
                .unwrap_or(0)
        };
        out.apart = (0..64)
            .flat_map(|i| (i + 1..64).map(move |j| (i, j)))
            .map(|(i, j)| gap(&p[i], &p[j]))
            .min();
        out.palette = Some(p.clone());
        p
    } else {
        vec![]
    };
    let square = |i: usize| -> Option<u8> {
        if depth != 4 {
            return digit(first + i);
        }
        let c = bmp.rgb(x0 + ((first + i) as f64 + 0.5) * w, mid)?;
        let dist = |p: &[u8; 3]| {
            (0..3)
                .map(|k| (c[k] as i32 - p[k] as i32).pow(2))
                .sum::<i32>()
        };
        // The first of the nearest, as Python's min().
        (0..64u8).min_by_key(|&n| dist(&palette[n as usize]))
    };
    let mut have: Vec<u8> = Vec::new();
    let mut need = 7;
    let fail = |out: &mut Row, why: &str, have: &[u8]| {
        out.why = Some(why.into());
        out.raw = Some(squares_to_bytes(have, bits, have.len() * bits / 8));
    };
    loop {
        while have.len() < squares_for(need, bits) {
            match square(have.len()) {
                Some(s) => have.push(s),
                None => {
                    fail(&mut out, "the row runs off the image", &have);
                    return Some(out);
                }
            }
        }
        let enough;
        (need, enough) = frame_length(&squares_to_bytes(&have, bits, need));
        if enough {
            break;
        }
        if need > 7 + 255 + 6 {
            fail(&mut out, "frame check failed", &have);
            return Some(out);
        }
    }
    if need > 7 + 255 + 6 + MAX_CHUNK + 2 {
        fail(&mut out, "frame check failed", &have);
        return Some(out);
    }
    while have.len() < squares_for(need, bits) {
        match square(have.len()) {
            Some(s) => have.push(s),
            None => {
                fail(&mut out, "the row runs off the image", &have);
                return Some(out);
            }
        }
    }
    let raw = squares_to_bytes(&have, bits, need);
    out.raw = Some(raw.clone());
    let frame = match unpack_frame(&raw) {
        Ok(f) => f,
        Err(e) => {
            out.why = Some(e);
            return Some(out);
        }
    };
    if frame.session as u32 != session {
        out.why = Some("the frame's session is not the row's".into());
        return Some(out);
    }
    out.frame = Some(frame);
    out.r#box = Some((
        round(x0) as i64,
        top,
        round(x0 + (first + have.len()) as f64 * w) as i64 + 1,
        round(top as f64 + w) as i64 + 1,
    ));
    Some(out)
}
