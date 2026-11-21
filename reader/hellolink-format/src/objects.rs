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
        // place: {map, zone, sub, instance, instanceType, instanceMap, instanceName}; the instance's four can
        // be null (docs/STRIP.md, object 3)
        3 => Some(Record(vec![
            ("map".into(), Int),
            ("zone".into(), Text),
            ("sub".into(), Text),
            ("instance".into(), opt(Bool)),
            ("instanceType".into(), opt(Text)),
            ("instanceMap".into(), opt(Int)),
            ("instanceName".into(), opt(Text)),
        ])),
        // rest: {rested}
        8 => Some(Record(vec![("rested".into(), Int)])),
        // assist: null, or {on, lang, seq, re, ask {n, topic, t}, left, taken, refused, shown}; seq, re, ask,
        // left and shown can be null (docs/STRIP.md, object 13)
        13 => Some(opt(Record(vec![
            ("on".into(), Bool),
            ("lang".into(), Text),
            ("seq".into(), opt(Int)),
            ("re".into(), opt(Int)),
            (
                "ask".into(),
                opt(Record(vec![
                    ("n".into(), Int),
                    ("topic".into(), Text),
                    ("t".into(), Int),
                ])),
            ),
            ("left".into(), opt(Int)),
            ("taken".into(), Int),
            ("refused".into(), Int),
            ("shown".into(), opt(Text)),
        ]))),
        // target: null, or {name, type, class, level, id, reaction}; type, id and reaction can be null
        2 => Some(opt(Record(vec![
            ("name".into(), Text),
            ("type".into(), opt(Text)),
            ("class".into(), Text),
            ("level".into(), Int),
            ("id".into(), opt(Int)),
            ("reaction".into(), opt(Int)),
        ]))),
        // route: null, or {source, owner, goal {map, x, y, title}, seconds, index, guided, legCount,
        // legs [{mode, seconds, text}]}; every field there, a null one as an Opt (docs/STRIP.md)
        9 => {
            let leg = Record(vec![
                ("mode".into(), opt(Text)),
                ("seconds".into(), opt(Int)),
                ("text".into(), opt(Text)),
            ]);
            Some(opt(Record(vec![
                ("source".into(), Text),
                ("owner".into(), opt(Text)),
                (
                    "goal".into(),
                    Record(vec![
                        ("map".into(), Int),
                        ("x".into(), Int),
                        ("y".into(), Int),
                        ("title".into(), opt(Text)),
                    ]),
                ),
                ("seconds".into(), opt(Int)),
                ("index".into(), opt(Int)),
                ("guided".into(), Bool),
                ("legCount".into(), opt(Int)),
                ("legs".into(), List(Box::new(leg))),
            ])))
        }
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
