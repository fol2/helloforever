//! Format 3's objects in binary (object format 2; docs/specs/232.md, part E): each object's
//! shape, and its bytes back as the JSON that format 2 sends for it. An object with no shape here
//! is still sent as JSON in format 3.
//!
//! The addon (HelloLink/Strip.lua) writes the same bytes by hand; `tests/vectors/objects3.json`
//! holds bytes written from the shapes below that both sides are held to.

use crate::Shape::{self, Int, List, Opt, Record, Ref, Tenths, Text, Tuple};
use crate::decode;

/// The object format byte of a binary object.
pub const FORMAT: u8 = 2;

/// The shape of object `oid` in binary, or None when it goes as JSON.
pub fn shape(oid: u8) -> Option<Shape> {
    match oid {
        // auras: {"player": [aura, ...], "target": [...]}; an aura is
        // [spell, stacks, duration, expires, source], source a unit token or null
        26 => {
            let aura = Tuple(vec![Ref('S'), Int, Tenths, Tenths, Opt(Box::new(Text))]);
            Some(Record(vec![
                ("player".into(), List(Box::new(aura.clone()))),
                ("target".into(), List(Box::new(aura))),
            ]))
        }
        _ => None,
    }
}

/// The JSON text of object `oid` from its binary bytes (no format byte, no check).
pub fn to_json(oid: u8, payload: &[u8]) -> Result<String, String> {
    let s = shape(oid).ok_or_else(|| format!("object {oid} has no binary form"))?;
    Ok(decode(&s, payload)?.to_string())
}
