//! The frame of strip format 3 (docs/specs/232.md, section 6): its bytes in, its parts out, and
//! back. No screen, no file, no clock. The squares and the row are the reader's.

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
    pub session: u16,
    pub dwell: u8,
    pub seq: u16,
    /// Each section's id and bytes, in the frame's order.
    pub sections: Vec<(u8, Vec<u8>)>,
    pub chunk: Option<Chunk>,
}

impl Frame {
    /// The bytes of the section `id`, when the frame has it.
    pub fn section(&self, id: u8) -> Option<&[u8]> {
        self.sections
            .iter()
            .find(|(i, _)| *i == id)
            .map(|(_, b)| b.as_slice())
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

/// The frame's bytes, both checks included.
pub fn pack(f: &Frame) -> Vec<u8> {
    let mut out = vec![VERSION];
    out.extend(f.session.to_be_bytes());
    out.push(f.dwell);
    out.extend(f.seq.to_be_bytes());
    let fixed: usize = f.sections.iter().map(|(_, b)| 2 + b.len()).sum();
    out.extend((fixed as u16).to_be_bytes());
    for (id, b) in &f.sections {
        out.push(*id);
        out.push(b.len() as u8);
        out.extend(b);
    }
    out.extend(check(&out));
    match &f.chunk {
        None => out.push(0),
        Some(c) => {
            let at = out.len();
            out.push(c.oid);
            out.extend(c.version.to_be_bytes());
            debug_assert!(c.data.len() <= 255, "a chunk holds at most 255 bytes");
            out.extend([c.index, c.count, c.data.len() as u8]);
            out.extend(&c.data);
            let sum = check(&out[at..]);
            out.extend(sum);
        }
    }
    out
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
/// whole frame is refused.
pub fn unpack(data: &[u8]) -> Result<(Frame, Option<String>), String> {
    let (len, enough) = length(data);
    if !enough || data.len() < len {
        return Err("frame cut short".into());
    }
    if data[0] != VERSION {
        return Err(format!("unknown version {}", data[0]));
    }
    let fixed_end = HEAD + usize::from(u16::from_be_bytes([data[6], data[7]]));
    if check(&data[..fixed_end]) != data[fixed_end..fixed_end + 2] {
        return Err("frame check failed".into());
    }
    let session = u16::from_be_bytes([data[1], data[2]]);
    let dwell = data[3];
    if session == 0 || !(5..=100).contains(&dwell) {
        return Err("bad session or dwell".into());
    }
    let mut sections: Vec<(u8, Vec<u8>)> = vec![];
    let mut at = HEAD;
    while at < fixed_end {
        let (id, n) = (
            data[at],
            *data.get(at + 1).ok_or("a section cut short")? as usize,
        );
        let bytes = data
            .get(at + 2..at + 2 + n)
            .filter(|_| at + 2 + n <= fixed_end)
            .ok_or("a section past the fixed part")?;
        if sections.iter().any(|(i, _)| *i == id) {
            return Err(format!("section {id} twice"));
        }
        sections.push((id, bytes.to_vec()));
        at += 2 + n;
    }
    if sections
        .iter()
        .any(|(id, b)| *id == FAST && b.len() != FAST_LEN)
    {
        return Err("a fast section not of 67 bytes".into());
    }
    let mut frame = Frame {
        session,
        dwell,
        seq: u16::from_be_bytes([data[4], data[5]]),
        sections,
        chunk: None,
    };
    let c = &data[fixed_end + 2..len];
    if c[0] == 0 {
        return Ok((frame, None));
    }
    let (index, count, size) = (c[3], c[4], c[5] as usize);
    let why = if check(&c[..6 + size]) != c[6 + size..] {
        Some("chunk check failed")
    } else if !(size >= 1 && (1..=MAX_CHUNKS).contains(&count) && index < count) {
        Some("bad object part")
    } else {
        None
    };
    if let Some(why) = why {
        return Ok((frame, Some(why.into())));
    }
    frame.chunk = Some(Chunk {
        oid: c[0],
        version: u16::from_be_bytes([c[1], c[2]]),
        index,
        count,
        data: c[6..6 + size].to_vec(),
    });
    Ok((frame, None))
}

/// The directory section: each object's id and version, in id order.
pub fn directory(bytes: &[u8]) -> Result<Vec<(u8, u16)>, String> {
    if !bytes.len().is_multiple_of(3) {
        return Err("a directory not of 3 bytes a record".into());
    }
    let out: Vec<(u8, u16)> = bytes
        .chunks(3)
        .map(|r| (r[0], u16::from_be_bytes([r[1], r[2]])))
        .collect();
    if out.windows(2).any(|w| w[0].0 >= w[1].0) || out.iter().any(|(id, _)| *id == 0) {
        return Err("a directory not in rising id order".into());
    }
    Ok(out)
}
