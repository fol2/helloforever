//! The live-state strip, format 2 (docs/specs/213.md): the frame, the keyframes and deltas
//! of the fast part, and the joining of objects whose chunks need not come in a row.
//! No file, no screen, no clock: values in, values out.

use crate::strip1::{Chunk, Fast, Frame, MAX_CHUNKS, check, unpack_object};
use hellolink_format::three;
use std::collections::BTreeMap;

pub const VERSION: u8 = 2;
pub const KEYFRAME: u8 = 128;
/// The longest a reader keeps a keyframe, in seconds (section 6).
pub const KEY_LIFE: f64 = 2.0;
/// The bytes of a mask: one bit a group, group 1 the most significant bit (section 6).
const MASK: usize = 3;

/// Section 6: the groups of format 1, then targettarget and pettarget.
pub const GROUPS: [(&str, &[(&str, usize)]); 16] = [
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
    (
        "targettarget",
        &[("level", 1), ("flags", 1), ("nameHash", 2)],
    ),
    ("pettarget", &[("level", 1), ("flags", 1), ("nameHash", 2)]),
];
const POSITION: usize = 8;

/// A changed group of a delta.
#[derive(Clone, Debug, PartialEq)]
pub enum Change {
    /// Unknown now.
    Gone,
    /// Its fields, as in a keyframe.
    Fields(Vec<(&'static str, u32)>),
    /// `position`: the difference from the keyframe, and the facing.
    Moved { dx: i64, dy: i64, facing: u32 },
}

/// The fast part of a format-2 frame.
#[derive(Clone, Debug, PartialEq)]
pub enum Part {
    Key(Fast),
    Delta(Vec<(&'static str, Change)>),
}

/// What a format-2 frame adds to `Frame`.
#[derive(Clone, Debug, PartialEq)]
pub struct Two {
    pub key: bool,
    pub key_seq: u8,
    pub part: Part,
}

fn be(data: &[u8]) -> u32 {
    data.iter().fold(0, |n, &b| n << 8 | b as u32)
}

fn bit(mask: &[u8], i: usize) -> bool {
    mask[i / 8] & (0x80 >> (i % 8)) != 0
}

/// A zigzag varint at `data[*at..]` (section 6).
fn varint(data: &[u8], at: &mut usize) -> Result<i64, String> {
    let mut z: u64 = 0;
    for shift in (0..21).step_by(7) {
        let b = *data.get(*at).ok_or("position cut short")?;
        *at += 1;
        z |= ((b & 0x7f) as u64) << shift;
        if b & 0x80 == 0 {
            return Ok(if z.is_multiple_of(2) {
                (z / 2) as i64
            } else {
                -((z / 2) as i64) - 1
            });
        }
    }
    Err("a varint longer than 3 bytes".into())
}

fn fields(data: &[u8], at: &mut usize, g: usize) -> Result<Vec<(&'static str, u32)>, String> {
    let mut out = Vec::new();
    for (name, size) in GROUPS[g].1 {
        let v = data.get(*at..*at + size).ok_or("fast part cut short")?;
        out.push((*name, be(v)));
        *at += size;
    }
    Ok(out)
}

/// The fast part (section 6).
pub fn unpack_part(data: &[u8], key: bool) -> Result<Part, String> {
    let mask = data.get(..MASK).ok_or("fast part cut short")?;
    let mut at = MASK;
    let part = if key {
        let mut fast = Vec::new();
        for (g, (name, _)) in GROUPS.iter().enumerate() {
            let known = bit(mask, g);
            fast.push((
                *name,
                if known {
                    Some(fields(data, &mut at, g)?)
                } else {
                    None
                },
            ));
        }
        Part::Key(fast)
    } else {
        let changed: Vec<usize> = (0..GROUPS.len()).filter(|&g| bit(mask, g)).collect();
        let gone = data
            .get(at..at + changed.len().div_ceil(8))
            .ok_or("fast part cut short")?;
        at += gone.len();
        if (changed.len()..gone.len() * 8).any(|k| bit(gone, k)) {
            return Err("gone's filling bits are not 0".into());
        }
        let mut out = Vec::new();
        for (k, &g) in changed.iter().enumerate() {
            let change = if bit(gone, k) {
                Change::Gone
            } else if g == POSITION {
                let (dx, dy) = (varint(data, &mut at)?, varint(data, &mut at)?);
                let facing = *data.get(at).ok_or("position cut short")? as u32;
                at += 1;
                Change::Moved { dx, dy, facing }
            } else {
                Change::Fields(fields(data, &mut at, g)?)
            };
            out.push((GROUPS[g].0, change));
        }
        Part::Delta(out)
    };
    if (GROUPS.len()..MASK * 8).any(|g| bit(mask, g)) {
        return Err("a group this reader does not know".into());
    }
    if at != data.len() {
        return Err("fast part longer than its groups".into());
    }
    Ok(part)
}

/// The whole frame's length once enough of it is read, else how many bytes are needed to
/// know more: (length, enough).
pub fn frame_length(prefix: &[u8]) -> (usize, bool) {
    if prefix.len() < 9 {
        return (9, false);
    }
    let oid_at = 9 + prefix[8] as usize;
    if prefix.len() <= oid_at {
        return (oid_at + 1, false);
    }
    if prefix[oid_at] == 0 {
        return (oid_at + 1 + 2, true);
    }
    let len_at = oid_at + 5;
    if prefix.len() <= len_at {
        return (len_at + 1, false);
    }
    (len_at + 1 + prefix[len_at] as usize + 2, true)
}

/// A format-2 frame (section 5), or the reason it is refused. `fast` holds a keyframe's
/// groups; a delta's are in `two` until a reader puts them over its keyframe (`apply`).
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
    let session = be(&data[1..3]) as u16;
    let dwell = data[3];
    if session == 0 || !(5..=100).contains(&dwell) {
        return Err("bad session or dwell".into());
    }
    let key = match data[6] {
        KEYFRAME => true,
        0 => false,
        k => return Err(format!("unknown kind {k}")),
    };
    if key && data[7] != data[5] {
        return Err("a keyframe whose keySeq is not its own seq".into());
    }
    let oid_at = 9 + data[8] as usize;
    let part = unpack_part(&data[9..oid_at], key)?;
    let chunk = match data[oid_at] {
        0 => None,
        oid => {
            let p = &data[oid_at..oid_at + 6];
            let (index, count, size) = (p[3], p[4], p[5] as usize);
            if !(size >= 1 && (1..=MAX_CHUNKS).contains(&count) && index < count) {
                return Err("bad object part".into());
            }
            Some(Chunk {
                oid,
                version: be(&p[1..3]) as u16,
                index,
                count,
                data: data[oid_at + 6..oid_at + 6 + size].to_vec(),
            })
        }
    };
    Ok(Frame {
        version: VERSION,
        session,
        seq: be(&data[4..6]) as u16,
        dwell,
        fast: match &part {
            Part::Key(f) => f.clone(),
            Part::Delta(_) => vec![],
        },
        chunk,
        two: Some(Two {
            key,
            key_seq: data[7],
            part,
        }),
        directory: None,
    })
}

/// A frame of any format, by its version byte.
pub fn unpack_any(data: &[u8]) -> Result<Frame, String> {
    match data.first() {
        Some(&VERSION) => unpack_frame(data),
        Some(&three::VERSION) => unpack_three(data),
        _ => crate::strip1::unpack_frame(data),
    }
}

/// Format 3's fast section (docs/specs/232.md, section 6): the mask, then every group at full
/// size; a group whose bit is 0 is unknown, whatever its bytes.
pub fn fast3(section: &[u8]) -> Result<Fast, String> {
    if section.len() != three::FAST_LEN {
        return Err("a fast section not of 67 bytes".into());
    }
    let mut at = MASK;
    let mut fast = Fast::new();
    for (g, (name, fields)) in GROUPS.iter().enumerate() {
        let mut values = vec![];
        for (field, size) in fields.iter() {
            values.push((*field, be(&section[at..at + size])));
            at += size;
        }
        fast.push((*name, bit(&section[..MASK], g).then_some(values)));
    }
    Ok(fast)
}

/// A format-3 frame (docs/specs/232.md, section 6) as the reader's `Frame`: every frame is
/// whole, so it is a keyframe of its own seq, and `Keys` takes it as format 2's keyframes. A
/// chunk whose own check failed is dropped and the frame is kept.
pub fn unpack_three(data: &[u8]) -> Result<Frame, String> {
    let (f, _dropped) = three::unpack(data)?;
    let fast = fast3(f.section(three::FAST).ok_or("no fast section")?)?;
    let directory = three::directory(f.section(three::DIRECTORY).ok_or("no directory")?)
        .collect::<Result<Vec<_>, _>>()?;
    Ok(Frame {
        version: three::VERSION,
        session: f.session,
        seq: f.seq,
        dwell: f.dwell,
        fast: fast.clone(),
        chunk: f.chunk.map(|c| Chunk {
            oid: c.oid,
            version: c.version,
            index: c.index,
            count: c.count,
            data: c.data.to_vec(),
        }),
        two: Some(Two {
            key: true,
            key_seq: (f.seq % 256) as u8,
            part: Part::Key(fast),
        }),
        directory: Some(directory),
    })
}

/// The keyframe's groups with a delta's changes put over them, or None when a position
/// difference leaves the map's range or names a position the keyframe does not hold.
pub fn apply(key: &Fast, delta: &[(&'static str, Change)]) -> Option<Fast> {
    let mut out = key.clone();
    for (name, change) in delta {
        let slot = out.iter_mut().find(|(n, _)| n == name)?;
        slot.1 = match change {
            Change::Gone => None,
            Change::Fields(f) => Some(f.clone()),
            Change::Moved { dx, dy, facing } => {
                let at = key.iter().find(|(n, _)| n == name)?.1.as_ref()?;
                let get = |f: &str| at.iter().find(|(n, _)| *n == f).map(|(_, v)| *v as i64);
                let (x, y) = (get("x")? + dx, get("y")? + dy);
                if !(0..=65535).contains(&x) || !(0..=65535).contains(&y) {
                    return None;
                }
                Some(vec![
                    ("map", get("map")? as u32),
                    ("x", x as u32),
                    ("y", y as u32),
                    ("facing", *facing),
                ])
            }
        };
    }
    Some(out)
}

/// The kept keyframe of a reader (section 6, "The reader's rules").
#[derive(Default)]
pub struct Keys {
    /// The low byte of its seq, its groups, and when it came.
    kept: Option<(u8, Fast, f64)>,
}

impl Keys {
    /// When the kept keyframe first came, or None.
    pub fn key_at(&self) -> Option<f64> {
        self.kept.as_ref().map(|k| k.2)
    }

    /// Forgets the kept keyframe: the session or the row's depth changed.
    pub fn drop_key(&mut self) {
        self.kept = None;
    }

    /// The fast state of a format-2 frame that came at `now`, or None when its keyframe is
    /// not held (lost, another, or more than KEY_LIFE old).
    pub fn resolve(&mut self, frame: &Frame, now: f64) -> Option<Fast> {
        let two = frame.two.as_ref()?;
        match &two.part {
            Part::Key(fast) => {
                // the same keyframe in a later capture keeps the time it first came (section 9)
                let first = match &self.kept {
                    Some((low, kept, at)) if *low == two.key_seq && kept == fast => *at,
                    _ => now,
                };
                self.kept = Some((two.key_seq, fast.clone(), first));
                Some(fast.clone())
            }
            Part::Delta(delta) => {
                let (low, key, at) = self.kept.as_ref()?;
                if *low != two.key_seq || now - at > KEY_LIFE {
                    return None;
                }
                apply(key, delta)
            }
        }
    }
}

/// An object whole: its id, format and text.
pub type Done = (u8, u8, Option<String>);

/// An object being joined: its version and the chunks so far, by index.
type Partial = (u16, Vec<Option<Vec<u8>>>);

/// Joins objects from chunks in any order and with frames between them (section 7). Keeps
/// the chunks of each object's newest version until it is whole; a newer version drops them.
#[derive(Default)]
pub struct Joiner {
    /// objectId -> (version, the chunks so far by index).
    partial: BTreeMap<u8, Partial>,
    /// objectId -> the version held whole, and when it was last seen whole.
    pub whole: BTreeMap<u8, (u16, f64)>,
    /// The objects whose version held is of format 253 (secret now): never `fresh-object`.
    pub secret: std::collections::BTreeSet<u8>,
    /// The last object that was whole but could not be read: id, version, why. The reader
    /// says it (`bad-object`) and takes it away.
    pub bad: Option<(u8, u16, String)>,
}

impl Joiner {
    /// Takes a chunk; returns the object when a new version of it is whole.
    pub fn feed(&mut self, c: &Chunk, now: f64) -> Option<Done> {
        if let Some((v, seen)) = self.whole.get_mut(&c.oid)
            && *v == c.version
        {
            *seen = now; // a refresh of the version held
            return None;
        }
        let entry = self
            .partial
            .entry(c.oid)
            .or_insert_with(|| (c.version, vec![None; c.count as usize]));
        if entry.0 != c.version || entry.1.len() != c.count as usize {
            *entry = (c.version, vec![None; c.count as usize]);
        }
        entry.1[c.index as usize] = Some(c.data.clone());
        if entry.1.iter().any(Option::is_none) {
            return None;
        }
        let (version, parts) = self.partial.remove(&c.oid)?;
        let bytes: Vec<u8> = parts.into_iter().flatten().flatten().collect();
        // 253: secret now (section 7): its bytes are the format byte and its check, FD FD FD
        let read = if bytes == [253, 253, 253] {
            Ok((253, None))
        } else {
            unpack_object(&bytes)
        };
        let (format, text) = match read {
            Ok(r) => r,
            Err(why) => {
                self.bad = Some((c.oid, version, why));
                return None;
            }
        };
        self.whole.insert(c.oid, (version, now));
        if format == 253 {
            self.secret.insert(c.oid);
        } else {
            self.secret.remove(&c.oid);
        }
        Some((c.oid, format, text))
    }
}
