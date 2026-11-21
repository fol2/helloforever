//! The frame of strip format 3 (docs/specs/232.md, section 6): its bytes in, its parts out, and
//! back. No screen, no file, no clock. The squares and the row are the reader's.
//!
//! `unpack` asks for no memory: a frame borrows the bytes it was read from (section 4 B).

/// The frame's version byte.
pub const VERSION: u8 = 3;
/// Section ids.
pub const FAST: u8 = 1;
pub const DIRECTORY: u8 = 2;
/// The fast section's length: the mask and the 16 groups of format 2 at full size.
pub const FAST_LEN: usize = 67;
/// The most chunks of one version (as format 2).
pub const MAX_CHUNKS: u8 = 12;
/// The head before the sections: version, session, dwell, seq, fixedLen.
const HEAD: usize = 8;

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Chunk<'a> {
    pub oid: u8,
    pub version: u16,
    pub index: u8,
    pub count: u8,
    pub data: &'a [u8],
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Frame<'a> {
    pub session: u16,
    pub dwell: u8,
    pub seq: u16,
    /// The sections as sent (id, length, bytes, ...), checked by `unpack`.
    sections: &'a [u8],
    pub chunk: Option<Chunk<'a>>,
}

impl<'a> Frame<'a> {
    /// Each section's id and bytes, in the frame's order.
    pub fn sections(&self) -> impl Iterator<Item = (u8, &'a [u8])> {
        let s = self.sections;
        let mut at = 0;
        std::iter::from_fn(move || {
            let (&id, &n) = (s.get(at)?, s.get(at + 1)?);
            let bytes = s.get(at + 2..at + 2 + n as usize)?;
            at += 2 + n as usize;
            Some((id, bytes))
        })
    }

    /// The bytes of the section `id`, when the frame has it.
    pub fn section(&self, id: u8) -> Option<&'a [u8]> {
        self.sections().find(|(i, _)| *i == id).map(|(_, b)| b)
    }
}

/// docs/STRIP.md, section 3: two sums modulo 255, written s1 then s2.
pub fn check(data: &[u8]) -> [u8; 2] {
    let (mut s1, mut s2) = (0u32, 0u32);
    for &b in data {
        s1 = (s1 + b as u32) % 255;
        s2 = (s2 + s1) % 255;
    }
    [s1 as u8, s2 as u8]
}

/// A frame's bytes, both checks included, or why the parts do not fit the wire format.
pub fn pack(
    session: u16,
    dwell: u8,
    seq: u16,
    sections: &[(u8, &[u8])],
    chunk: Option<&Chunk>,
) -> Result<Vec<u8>, String> {
    let mut out = vec![VERSION];
    out.extend(session.to_be_bytes());
    out.push(dwell);
    out.extend(seq.to_be_bytes());
    let fixed: usize = sections.iter().map(|(_, b)| 2 + b.len()).sum();
    out.extend(
        u16::try_from(fixed)
            .map_err(|_| "the sections pass 65,535 bytes")?
            .to_be_bytes(),
    );
    for (id, b) in sections {
        out.push(*id);
        out.push(u8::try_from(b.len()).map_err(|_| format!("section {id} passes 255 bytes"))?);
        out.extend(*b);
    }
    out.extend(check(&out));
    match chunk {
        None => out.push(0),
        Some(c) => {
            let len = u8::try_from(c.data.len())
                .ok()
                .filter(|n| *n >= 1)
                .ok_or("a chunk holds 1 to 255 bytes")?;
            let at = out.len();
            out.push(c.oid);
            out.extend(c.version.to_be_bytes());
            out.extend([c.index, c.count, len]);
            out.extend(c.data);
            let sum = check(&out[at..]);
            out.extend(sum);
        }
    }
    Ok(out)
}

/// The whole frame's length once enough of it is known, else how many bytes are needed to know
/// more: (length, enough).
pub fn length(prefix: &[u8]) -> (usize, bool) {
    if prefix.len() < HEAD {
        return (HEAD, false);
    }
    let oid_at = HEAD + usize::from(u16::from_be_bytes([prefix[6], prefix[7]])) + 2;
    if prefix.len() <= oid_at {
        return (oid_at + 1, false);
    }
    if prefix[oid_at] == 0 {
        return (oid_at + 1, true);
    }
    let len_at = oid_at + 5;
    if prefix.len() <= len_at {
        return (len_at + 1, false);
    }
    (len_at + 1 + prefix[len_at] as usize + 2, true)
}

/// A frame, and why its chunk was dropped (None when it had none or it was good); or why the
/// whole frame is refused. The fixed part is judged first: a chunk cut short or damaged leaves
/// it good.
pub fn unpack(data: &[u8]) -> Result<(Frame<'_>, Option<&'static str>), String> {
    if data.len() < HEAD {
        return Err("frame cut short".into());
    }
    if data[0] != VERSION {
        return Err(format!("unknown version {}", data[0]));
    }
    let fixed_end = HEAD + usize::from(u16::from_be_bytes([data[6], data[7]]));
    let sum = data
        .get(fixed_end..fixed_end + 2)
        .ok_or("frame cut short")?;
    if check(&data[..fixed_end]) != sum {
        return Err("frame check failed".into());
    }
    let session = u16::from_be_bytes([data[1], data[2]]);
    let dwell = data[3];
    if session == 0 || !(5..=100).contains(&dwell) {
        return Err("bad session or dwell".into());
    }
    let mut frame = Frame {
        session,
        dwell,
        seq: u16::from_be_bytes([data[4], data[5]]),
        sections: &data[HEAD..fixed_end],
        chunk: None,
    };
    // the sections: they fill the fixed part exactly; fast first, the directory second
    let (mut at, mut seen) = (0, 0usize);
    for (k, (id, bytes)) in frame.sections().enumerate() {
        match (k, id) {
            (0, FAST) if bytes.len() == FAST_LEN => {}
            (0, _) => return Err("the first section is not a fast section of 67 bytes".into()),
            (1, DIRECTORY) => {
                directory(bytes).try_for_each(|r| r.map(|_| ()))?;
            }
            (1, _) => return Err("the second section is not the directory".into()),
            (_, FAST | DIRECTORY) => return Err(format!("section {id} twice")),
            _ => {
                if frame.sections().take(k).any(|(i, _)| i == id) {
                    return Err(format!("section {id} twice"));
                }
            }
        }
        at += 2 + bytes.len();
        seen = k + 1;
    }
    if at != frame.sections.len() {
        return Err("a section past the fixed part".into());
    }
    if seen < 2 {
        return Err("a frame without its fast section and directory".into());
    }
    let c = &data[fixed_end + 2..];
    match c.first() {
        None => return Ok((frame, Some("chunk cut short"))),
        Some(0) => return Ok((frame, None)),
        Some(_) => {}
    }
    let Some(&size) = c.get(5) else {
        return Ok((frame, Some("chunk cut short")));
    };
    let size = size as usize;
    let Some(sum) = c.get(6 + size..6 + size + 2) else {
        return Ok((frame, Some("chunk cut short")));
    };
    let (index, count) = (c[3], c[4]);
    if check(&c[..6 + size]) != sum {
        return Ok((frame, Some("chunk check failed")));
    }
    if !(size >= 1 && (1..=MAX_CHUNKS).contains(&count) && index < count) {
        return Ok((frame, Some("bad object part")));
    }
    frame.chunk = Some(Chunk {
        oid: c[0],
        version: u16::from_be_bytes([c[1], c[2]]),
        index,
        count,
        data: &c[6..6 + size],
    });
    Ok((frame, None))
}

/// The directory section's records, each object's id and version, in id order; an error for a
/// directory not of 3 bytes a record or not in rising id order (ids 1 to 255).
pub fn directory(bytes: &[u8]) -> impl Iterator<Item = Result<(u8, u16), String>> + '_ {
    let mut last = 0u8;
    let odd = (!bytes.len().is_multiple_of(3))
        .then(|| Err("a directory not of 3 bytes a record".to_string()));
    odd.into_iter()
        .chain(bytes.chunks_exact(3).map(move |r| {
            if r[0] <= last {
                return Err("a directory not in rising id order".to_string());
            }
            last = r[0];
            Ok((r[0], u16::from_be_bytes([r[1], r[2]])))
        }))
}
