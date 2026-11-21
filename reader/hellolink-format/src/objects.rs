//! Format 3's objects in binary (object format 2; docs/specs/232.md, part E): each object's
//! shape, and its bytes back as the JSON that format 2 sends for it. An object with no shape here
//! is still sent as JSON in format 3.
//!
//! The addon (HelloLink/Strip.lua) writes the same bytes by hand; `tests/vectors/objects3.json`
//! holds bytes written from the shapes below that both sides are held to.

use crate::Shape::{self, Bool, Int, List, Opt, Packed, Record, Ref, Tenths, Text, Tuple, Who};
use crate::decode;

/// The object format byte of a binary object.
pub const FORMAT: u8 = 2;
/// The object format byte of a binary object deflated (one that passes what a version may send).
pub const DEFLATED: u8 = 3;

/// The unit tokens of object 24, in the order the addon reads them (Strip.lua, `UNITS`).
pub fn unit_tokens() -> Vec<String> {
    let mut t = vec!["focus".to_string(), "mouseover".to_string()];
    t.extend((1..=4).map(|i| format!("party{i}")));
    t.extend((1..=4).map(|i| format!("partypet{i}")));
    t.extend((1..=40).map(|i| format!("raid{i}")));
    t.extend((1..=5).map(|i| format!("boss{i}")));
    t
}

fn opt(s: Shape) -> Shape {
    Opt(Box::new(s))
}

/// The shape of object `oid` in binary, or None when it goes as JSON.
pub fn shape(oid: u8) -> Option<Shape> {
    match oid {
        // units: each unit that exists by its token, then "nameplates"; a unit is [who, level,
        // class, classification, flags, target, threat, mark, cast]
        24 => {
            let unit = Tuple(vec![
                Who,
                Int,
                opt(Text),
                opt(Text),
                opt(Int),
                opt(Text),
                opt(Int),
                opt(Int),
                opt(Who),
            ]);
            let mut fields: Vec<(String, Shape)> = unit_tokens()
                .into_iter()
                .map(|t| (t, unit.clone()))
                .collect();
            fields.push(("nameplates".into(), List(Box::new(unit))));
            Some(Record(fields))
        }
        // auras: {"player": [aura, ...], "target": [...]}; an aura is
        // [spell, stacks, duration, expires, source], source a unit token or null
        26 => {
            let aura = Tuple(vec![Ref('S'), Int, Tenths, Tenths, Opt(Box::new(Text))]);
            Some(Record(vec![
                ("player".into(), List(Box::new(aura.clone()))),
                ("target".into(), List(Box::new(aura))),
            ]))
        }
        // cooldowns: {"slots": [[slot, what, active, onGCD, start, duration], ...]}; each slot packed:
        // one byte of bits (slot zero, what present, active, onGCD, start present and zero, duration
        // present and zero), then the slot, what, start and duration that are there and not zero
        27 => Some(Record(vec![(
            "slots".into(),
            List(Box::new(Packed(vec![
                Int,
                opt(Who),
                Bool,
                Bool,
                opt(Tenths),
                opt(Tenths),
            ]))),
        )])),
        _ => None,
    }
}

/// The JSON text of object `oid` from its binary bytes (no format byte, no check).
pub fn to_json(oid: u8, payload: &[u8]) -> Result<String, String> {
    let s = shape(oid).ok_or_else(|| format!("object {oid} has no binary form"))?;
    Ok(decode(&s, payload)?.to_string())
}
