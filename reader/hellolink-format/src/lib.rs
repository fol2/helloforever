//! Strip format 3's records (docs/specs/232.md, part E): a record's shape and its binary form.
//!
//! Step 1 of the spec's plan: the shape is learnt from format 2's objects in a record, so that
//! the binary form can be measured against JSON plus deflate (`src/bin/measure.rs`). The
//! hand-written schema of step 4 replaces the learnt shapes; the binary form stays.
//!
//! The binary form, by shape:
//! - `Bool`: one byte, 0 or 1.
//! - `Int`: zigzag, then LEB128 (7 bits a byte, the high bit set on every byte but the last).
//! - `Float`: an `f32`, little-endian.
//! - `Text`: the length in bytes (LEB128), then UTF-8.
//! - `TextRef`: a text by reference: its FNV-1a hash, 32 bits little-endian. The text itself goes
//!   elsewhere (in format 3, a slow round of texts); decoded, it is the hash as a number.
//! - `List`: the count (LEB128), then the items.
//! - `Record`: a presence bit a field (field 0 in bit 0 of the first byte; at least one byte, so
//!   that every value takes a byte or more), then the present
//!   fields in order. A field that is missing or null is absent; in an `Opt` field a null is there,
//!   as the `Opt`'s 0, so that it reads back as null.
//! - `Opt` (a list item that can be null): one byte, 0 for null or 1, then the value.
//! - `Any` (values whose shapes did not agree): the JSON text, as `Text`.
//! - `Ref(kind)`: a reference `"<kind>:<id>:<hash>"` (docs/specs/213.md, section 7): the id
//!   (LEB128, 1 or more), then the hash, 16 bits little-endian.
//! - `Tenths`: a number with one decimal, as ten times it (`Int`: zigzag, LEB128).
//! - `Tuple`: a JSON array of fixed places, each in its own shape, one after the other.
//! - `Who`: any reference `"<kind>:<id>:<hash>"`: the kind (one ASCII letter), the id (LEB128, 0
//!   allowed: a player's id is a hash that can be 0), then the hash, 16 bits little-endian.
//! - `Packed(places)`: a JSON array of fixed places, as `Tuple`, with its small parts in bits ahead
//!   of it (bit 0 of the first byte first, as many bytes as the bits need): a `Bool` is a bit (its
//!   value); an `Opt` is a bit (present), and when it holds an `Int` or `Tenths`, a second bit
//!   (zero); an `Int` or `Tenths` is a bit (zero). After the bits come the other values in order:
//!   a present `Opt`'s value and a number only when it is not zero, and every other place.

pub mod objects;
pub mod three;

use serde_json::{Map, Number, Value};

#[derive(Clone, Debug, PartialEq)]
pub enum Shape {
    /// No value seen yet.
    Never,
    Bool,
    Int,
    Float,
    Text,
    TextRef,
    List(Box<Shape>),
    Record(Vec<(String, Shape)>),
    Opt(Box<Shape>),
    Any,
    /// A reference of this kind: `"S:14320:26398"` for `Ref('S')`.
    Ref(char),
    /// A number with one decimal.
    Tenths,
    /// A JSON array of fixed places.
    Tuple(Vec<Shape>),
    /// Any reference: `"C:740:10475"`, `"P:51234:0"`.
    Who,
    /// A tuple whose bools, presences and zeros go in bits ahead of it.
    Packed(Vec<Shape>),
}

/// The shape `a` widened to take `v` too.
pub fn learn(a: Shape, v: &Value) -> Shape {
    match (a, v) {
        (Shape::Opt(s), Value::Null) => Shape::Opt(s),
        (s, Value::Null) => Shape::Opt(Box::new(s)),
        (Shape::Opt(s), v) => Shape::Opt(Box::new(learn(*s, v))),
        (Shape::Any, _) => Shape::Any,
        (Shape::Never | Shape::Bool, Value::Bool(_)) => Shape::Bool,
        (Shape::Never | Shape::Int, Value::Number(n)) if n.is_i64() => Shape::Int,
        (Shape::Never | Shape::Int | Shape::Float, Value::Number(_)) => Shape::Float,
        (Shape::Never | Shape::Text, Value::String(_)) => Shape::Text,
        (Shape::Never, Value::Array(items)) => {
            Shape::List(Box::new(items.iter().fold(Shape::Never, learn)))
        }
        (Shape::List(s), Value::Array(items)) => {
            Shape::List(Box::new(items.iter().fold(*s, learn)))
        }
        (a @ (Shape::Never | Shape::Record(_)), Value::Object(m)) => {
            let mut fields = match a {
                Shape::Record(fields) => fields,
                _ => vec![],
            };
            for (k, val) in m.iter().filter(|(_, val)| !val.is_null()) {
                match fields.iter_mut().find(|(name, _)| name == k) {
                    Some((_, s)) => *s = learn(std::mem::replace(s, Shape::Never), val),
                    None => fields.push((k.clone(), learn(Shape::Never, val))),
                }
            }
            Shape::Record(fields)
        }
        _ => Shape::Any,
    }
}

fn leb(out: &mut Vec<u8>, mut n: u64) {
    while n >= 0x80 {
        out.push(n as u8 | 0x80);
        n >>= 7;
    }
    out.push(n as u8);
}

/// The FNV-1a hash of a text, 32 bits: a `TextRef`.
pub fn text_hash(s: &str) -> u32 {
    s.bytes().fold(0x811c_9dc5, |h, b| {
        (h ^ u32::from(b)).wrapping_mul(0x0100_0193)
    })
}

fn text(out: &mut Vec<u8>, s: &str) {
    leb(out, s.len() as u64);
    out.extend_from_slice(s.as_bytes());
}

/// Appends `v` in shape `s` to `out`.
pub fn encode(s: &Shape, v: &Value, out: &mut Vec<u8>) -> Result<(), String> {
    match (s, v) {
        (Shape::Opt(_), Value::Null) => out.push(0),
        (Shape::Opt(inner), v) => {
            out.push(1);
            encode(inner, v, out)?;
        }
        (Shape::Bool, Value::Bool(b)) => out.push(*b as u8),
        (Shape::Int, Value::Number(n)) if n.is_i64() => {
            let i = n.as_i64().unwrap_or_default();
            leb(out, ((i << 1) ^ (i >> 63)) as u64);
        }
        (Shape::Float, Value::Number(n)) => {
            let f = n.as_f64().unwrap_or_default() as f32;
            if !f.is_finite() {
                return Err(format!("{n} does not fit an f32"));
            }
            out.extend(f.to_le_bytes())
        }
        (Shape::Text, Value::String(t)) => text(out, t),
        (Shape::TextRef, Value::String(t)) => out.extend(text_hash(t).to_le_bytes()),
        (Shape::List(inner), Value::Array(items)) => {
            leb(out, items.len() as u64);
            for item in items {
                encode(inner, item, out)?;
            }
        }
        (Shape::Record(fields), Value::Object(m)) => {
            let at = out.len();
            out.resize(at + fields.len().div_ceil(8).max(1), 0);
            for (i, (name, inner)) in fields.iter().enumerate() {
                // a null is absent, but in an `Opt` field it is there, as the `Opt`'s 0 (a JSON null kept)
                if let Some(val) = m
                    .get(name)
                    .filter(|val| !val.is_null() || matches!(inner, Shape::Opt(_)))
                {
                    out[at + i / 8] |= 1 << (i % 8);
                    encode(inner, val, out)?;
                }
            }
            if let Some(k) = m
                .keys()
                .find(|k| !m[*k].is_null() && !fields.iter().any(|(name, _)| name == *k))
            {
                return Err(format!("field {k} is not in the shape"));
            }
        }
        (Shape::Any, v) => text(out, &v.to_string()),
        (Shape::Ref(kind), Value::String(r)) => {
            let (id, hash) =
                parse_ref(*kind, r).ok_or_else(|| format!("{r} is not a {kind} reference"))?;
            leb(out, id);
            out.extend(hash.to_le_bytes());
        }
        (Shape::Tenths, Value::Number(n)) => {
            let t = (n.as_f64().unwrap_or_default() * 10.0).round();
            if !(-9.0e15..=9.0e15).contains(&t) {
                return Err(format!("{n} does not fit tenths"));
            }
            let i = t as i64;
            leb(out, ((i << 1) ^ (i >> 63)) as u64);
        }
        (Shape::Tuple(places), Value::Array(items)) if places.len() == items.len() => {
            for (p, item) in places.iter().zip(items) {
                encode(p, item, out)?;
            }
        }
        (Shape::Who, Value::String(r)) => {
            let (kind, id, hash) = parse_who(r).ok_or_else(|| format!("{r} is not a reference"))?;
            out.push(kind);
            leb(out, id);
            out.extend(hash.to_le_bytes());
        }
        (Shape::Packed(places), Value::Array(items)) if places.len() == items.len() => {
            let (mut bits, mut rest) = (vec![], vec![]);
            for (p, v) in places.iter().zip(items) {
                match p {
                    Shape::Bool => {
                        bits.push(v.as_bool().ok_or_else(|| format!("{v} is not a bool"))?)
                    }
                    Shape::Opt(inner) => {
                        bits.push(!v.is_null());
                        let zero = is_number(inner) && is_zero(inner, v);
                        if is_number(inner) {
                            bits.push(zero);
                        }
                        if !v.is_null() && !zero {
                            encode(inner, v, &mut rest)?;
                        }
                    }
                    Shape::Int | Shape::Tenths => {
                        bits.push(is_zero(p, v));
                        if !is_zero(p, v) {
                            encode(p, v, &mut rest)?;
                        }
                    }
                    p => encode(p, v, &mut rest)?,
                }
            }
            for byte in bits.chunks(8) {
                out.push(
                    byte.iter()
                        .enumerate()
                        .fold(0, |b, (i, &x)| b | (x as u8) << i),
                );
            }
            out.extend(rest);
        }
        (s, v) => return Err(format!("{v} is not of shape {s:?}")),
    }
    Ok(())
}

fn is_number(s: &Shape) -> bool {
    matches!(s, Shape::Int | Shape::Tenths)
}

/// Whether `v` goes as zero in shape `s`: a `Tenths` once rounded to one decimal, as the addon
/// rounds it.
fn is_zero(s: &Shape, v: &Value) -> bool {
    match s {
        Shape::Tenths => v.as_f64().is_some_and(|f| (f * 10.0).round() == 0.0),
        _ => v.as_f64() == Some(0.0),
    }
}

/// The bits a `Packed` tuple puts ahead of its values.
fn packed_bits(places: &[Shape]) -> usize {
    places
        .iter()
        .map(|p| match p {
            Shape::Opt(inner) if is_number(inner) => 2,
            Shape::Bool | Shape::Opt(_) | Shape::Int | Shape::Tenths => 1,
            _ => 0,
        })
        .sum()
}

/// The kind (an ASCII letter), id and hash of any reference `"<kind>:<id>:<hash>"`.
fn parse_who(r: &str) -> Option<(u8, u64, u16)> {
    let mut parts = r.split(':');
    let kind = match parts.next()?.as_bytes() {
        [b] if b.is_ascii_alphabetic() => *b,
        _ => return None,
    };
    let id = parts.next()?.parse().ok()?;
    let hash = parts.next()?.parse().ok()?;
    parts.next().is_none().then_some((kind, id, hash))
}

/// The id and hash of a reference `"<kind>:<id>:<hash>"`, the id 1 or more.
fn parse_ref(kind: char, r: &str) -> Option<(u64, u16)> {
    let mut parts = r.split(':');
    let k = parts.next()?;
    let id: u64 = parts.next()?.parse().ok().filter(|&i| i >= 1)?;
    let hash: u16 = parts.next()?.parse().ok()?;
    (k.len() == 1 && k.starts_with(kind) && parts.next().is_none()).then_some((id, hash))
}

struct Reader<'a> {
    bytes: &'a [u8],
    at: usize,
    /// Values still allowed: every value takes a byte or more, so a value for each byte. A list
    /// count over it is refused before any memory is asked for.
    left: usize,
}

impl Reader<'_> {
    fn byte(&mut self) -> Result<u8, String> {
        let b = *self.bytes.get(self.at).ok_or("the bytes end early")?;
        self.at += 1;
        Ok(b)
    }

    fn leb(&mut self) -> Result<u64, String> {
        let mut n = 0u64;
        for shift in (0..64).step_by(7) {
            let b = self.byte()?;
            if shift == 63 && b > 1 {
                break; // the tenth byte has room for one bit
            }
            n |= u64::from(b & 0x7f) << shift;
            if b < 0x80 {
                return Ok(n);
            }
        }
        Err("a number longer than 64 bits".into())
    }

    fn text(&mut self) -> Result<String, String> {
        let len = usize::try_from(self.leb()?).map_err(|e| e.to_string())?;
        let end = self
            .at
            .checked_add(len)
            .filter(|end| *end <= self.bytes.len())
            .ok_or("a text past the end")?;
        let t = std::str::from_utf8(&self.bytes[self.at..end]).map_err(|e| e.to_string())?;
        self.at = end;
        Ok(t.to_owned())
    }

    fn flag(&mut self) -> Result<bool, String> {
        match self.byte()? {
            0 => Ok(false),
            1 => Ok(true),
            b => Err(format!("{b} is not 0 or 1")),
        }
    }

    fn value(&mut self, s: &Shape) -> Result<Value, String> {
        // every value takes a byte or more, but for a tuple, which takes none of its own: only its
        // places count
        let no_byte = match s {
            Shape::Tuple(_) => true,
            Shape::Packed(p) => packed_bits(p) == 0,
            _ => false,
        };
        if !no_byte {
            self.left = self
                .left
                .checked_sub(1)
                .ok_or("more values than the bytes can hold")?;
        }
        Ok(match s {
            Shape::Never => return Err("a value of no shape".into()),
            Shape::Bool => Value::Bool(self.flag()?),
            Shape::Int => {
                let z = self.leb()?;
                Value::from((z >> 1) as i64 ^ -((z & 1) as i64))
            }
            Shape::Float => {
                let mut b = [0; 4];
                for x in &mut b {
                    *x = self.byte()?;
                }
                Number::from_f64(f64::from(f32::from_le_bytes(b)))
                    .map(Value::Number)
                    .ok_or("not a number")?
            }
            Shape::Text => Value::String(self.text()?),
            Shape::TextRef => {
                let mut b = [0; 4];
                for x in &mut b {
                    *x = self.byte()?;
                }
                Value::from(u32::from_le_bytes(b))
            }
            Shape::List(inner) => {
                let n = self.leb()?;
                if n > self.left as u64 {
                    return Err(format!("a list of {n} in {} bytes", self.bytes.len()));
                }
                let mut items = vec![];
                for _ in 0..n {
                    items.push(self.value(inner)?);
                }
                Value::Array(items)
            }
            Shape::Record(fields) => {
                let at = self.at;
                self.at = at
                    .checked_add(fields.len().div_ceil(8).max(1))
                    .filter(|end| *end <= self.bytes.len())
                    .ok_or("the bytes end early")?;
                let mut m = Map::new();
                for (i, (name, inner)) in fields.iter().enumerate() {
                    if self.bytes[at + i / 8] & (1 << (i % 8)) != 0 {
                        m.insert(name.clone(), self.value(inner)?);
                    }
                }
                Value::Object(m)
            }
            Shape::Opt(inner) => match self.flag()? {
                false => Value::Null,
                true => self.value(inner)?,
            },
            Shape::Any => serde_json::from_str(&self.text()?).map_err(|e| e.to_string())?,
            Shape::Ref(kind) => {
                let id = self.leb()?;
                if id == 0 {
                    return Err("a reference with id 0".into());
                }
                let hash = u16::from_le_bytes([self.byte()?, self.byte()?]);
                Value::String(format!("{kind}:{id}:{hash}"))
            }
            Shape::Tenths => {
                let z = self.leb()?;
                let i = (z >> 1) as i64 ^ -((z & 1) as i64);
                Number::from_f64(i as f64 / 10.0)
                    .map(Value::Number)
                    .ok_or("not a number")?
            }
            Shape::Tuple(places) => {
                let mut items = Vec::with_capacity(places.len());
                for p in places {
                    items.push(self.value(p)?);
                }
                Value::Array(items)
            }
            Shape::Who => {
                let kind = self.byte()?;
                if !kind.is_ascii_alphabetic() {
                    return Err(format!("{kind} is not a kind"));
                }
                let id = self.leb()?;
                let hash = u16::from_le_bytes([self.byte()?, self.byte()?]);
                Value::String(format!("{}:{id}:{hash}", kind as char))
            }
            Shape::Packed(places) => {
                let n = packed_bits(places);
                let mut bits = Vec::with_capacity(n);
                for _ in 0..n.div_ceil(8) {
                    let b = self.byte()?;
                    bits.extend((0..8).map(|i| b >> i & 1 == 1));
                }
                let mut next = bits.into_iter();
                let mut bit = || next.next().unwrap_or(false);
                let zero = |p: &Shape| match p {
                    Shape::Tenths => Number::from_f64(0.0).map_or(Value::Null, Value::Number),
                    _ => Value::from(0),
                };
                let mut items = Vec::with_capacity(places.len());
                for p in places {
                    items.push(match p {
                        Shape::Bool => Value::Bool(bit()),
                        Shape::Opt(inner) => {
                            let present = bit();
                            let is_zero = is_number(inner) && bit();
                            match (present, is_zero) {
                                (false, _) => Value::Null,
                                (true, true) => zero(inner),
                                (true, false) => self.value(inner)?,
                            }
                        }
                        Shape::Int | Shape::Tenths => {
                            if bit() {
                                zero(p)
                            } else {
                                self.value(p)?
                            }
                        }
                        p => self.value(p)?,
                    });
                }
                Value::Array(items)
            }
        })
    }
}

/// Reads one value of shape `s`; every byte must be used.
pub fn decode(s: &Shape, bytes: &[u8]) -> Result<Value, String> {
    let mut r = Reader {
        bytes,
        at: 0,
        left: bytes.len(),
    };
    let v = r.value(s)?;
    if r.at != bytes.len() {
        return Err(format!("{} bytes left over", bytes.len() - r.at));
    }
    Ok(v)
}

/// Whether `back` (a value decoded in shape `s`) is `v` as that shape keeps it: a `Record`
/// leaves out fields that are null, a `Float` keeps an `f32`, `Any` keeps the value exactly.
pub fn same(s: &Shape, back: &Value, v: &Value) -> bool {
    match (s, back, v) {
        (Shape::Record(fields), Value::Object(a), Value::Object(b)) => {
            // as `encode` keeps them: a field that is not null, and a null in an `Opt` field
            let present = || {
                b.iter().filter(|(k, x)| {
                    !x.is_null()
                        || fields
                            .iter()
                            .any(|(name, f)| name == *k && matches!(f, Shape::Opt(_)))
                })
            };
            a.len() == present().count()
                && present().all(|(k, x)| {
                    let inner = fields.iter().find(|(name, _)| name == k);
                    matches!((inner, a.get(k)), (Some((_, f)), Some(y)) if same(f, y, x))
                })
        }
        (Shape::List(inner), Value::Array(a), Value::Array(b)) => {
            a.len() == b.len() && a.iter().zip(b).all(|(y, x)| same(inner, y, x))
        }
        (Shape::Opt(inner), back, v) if !v.is_null() => same(inner, back, v),
        (Shape::Float, Value::Number(a), Value::Number(b)) => {
            a.as_f64().map(|f| f as f32) == b.as_f64().map(|f| f as f32)
        }
        (Shape::TextRef, Value::Number(a), Value::String(b)) => {
            a.as_u64() == Some(u64::from(text_hash(b)))
        }
        (Shape::Tenths, Value::Number(a), Value::Number(b)) => {
            a.as_f64().map(|f| (f * 10.0).round()) == b.as_f64().map(|f| (f * 10.0).round())
        }
        (Shape::Packed(places), Value::Array(a), Value::Array(b)) => {
            a.len() == b.len()
                && places
                    .iter()
                    .zip(a.iter().zip(b))
                    .all(|(p, (y, x))| same(p, y, x))
        }
        (Shape::Tuple(places), Value::Array(a), Value::Array(b)) => {
            a.len() == b.len()
                && places
                    .iter()
                    .zip(a.iter().zip(b))
                    .all(|(p, (y, x))| same(p, y, x))
        }
        (_, a, b) => a == b,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn a_null_in_an_opt_field_is_kept_and_is_the_same() {
        let s = Shape::Record(vec![
            ("a".into(), Shape::Opt(Box::new(Shape::Int))),
            ("b".into(), Shape::Int),
        ]);
        let v = json!({"a": null, "b": null});
        let mut out = vec![];
        encode(&s, &v, &mut out).unwrap();
        assert_eq!(
            out,
            [0b01, 0],
            "a is there as the Opt's 0; b, a plain field, is absent"
        );
        let back = decode(&s, &out).unwrap();
        assert_eq!(back, json!({"a": null}));
        assert!(
            same(&s, &back, &v),
            "the null kept in the Opt field is the same"
        );
    }

    #[test]
    fn a_record_has_the_bytes_written_by_hand() {
        let s = Shape::Record(vec![
            ("a".into(), Shape::Int),
            ("b".into(), Shape::Text),
            ("c".into(), Shape::Bool),
        ]);
        let mut out = vec![];
        encode(&s, &json!({"a": -3, "b": "hi", "c": null}), &mut out).unwrap();
        // presence 0b011 (a and b); zigzag(-3) = 5; length 2, "h", "i"
        assert_eq!(out, [0x03, 0x05, 0x02, 0x68, 0x69]);
        assert_eq!(decode(&s, &out).unwrap(), json!({"a": -3, "b": "hi"}));
    }

    #[test]
    fn a_large_number_and_a_list_with_nulls_have_the_bytes_written_by_hand() {
        let s = Shape::List(Box::new(Shape::Opt(Box::new(Shape::Int))));
        let mut out = vec![];
        encode(&s, &json!([300, null]), &mut out).unwrap();
        // count 2; present, zigzag(300) = 600 = 0x258 -> 0xd8 0x04; null
        assert_eq!(out, [0x02, 0x01, 0xd8, 0x04, 0x00]);
    }

    #[test]
    fn learnt_shapes_widen_and_give_every_value_back() {
        let values = [
            json!({"items": [[1322, 2], [3030, 2875]], "free": 32}),
            json!({"items": [], "free": 31, "x": 0.5}),
            json!({"items": [[897, null]], "free": 2.25, "name": "Booty Bay"}),
        ];
        let s = values.iter().fold(Shape::Never, learn);
        let Shape::Record(fields) = &s else {
            panic!("{s:?}")
        };
        assert_eq!(
            fields.iter().map(|(k, _)| k.as_str()).collect::<Vec<_>>(),
            ["free", "items", "x", "name"]
        );
        assert_eq!(fields[0].1, Shape::Float, "an int then a float is a float");
        for v in &values {
            let mut out = vec![];
            encode(&s, v, &mut out).unwrap();
            assert!(same(&s, &decode(&s, &out).unwrap(), v), "{v}");
        }
    }

    #[test]
    fn a_value_of_another_shape_or_a_cut_frame_is_refused() {
        let s = Shape::Record(vec![("a".into(), Shape::Int)]);
        assert!(encode(&s, &json!({"a": "x"}), &mut vec![]).is_err());
        assert!(encode(&s, &json!({"b": 1}), &mut vec![]).is_err());
        assert!(
            decode(&s, &[0x01]).is_err(),
            "the field's bytes are missing"
        );
        assert!(decode(&s, &[0x01, 0x02, 0x00]).is_err(), "a byte left over");
    }

    #[test]
    fn bytes_that_no_value_could_give_are_refused() {
        // a count of 2^62 empty records in 9 bytes: refused before any memory is asked for
        let empty = Shape::List(Box::new(Shape::Record(vec![])));
        let huge = [0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x40];
        assert!(decode(&empty, &huge).is_err());
        // an empty record takes one byte (a presence byte), so what the encoder writes decodes
        let nine = Value::Array(vec![json!({}); 9]);
        let mut out = vec![];
        encode(&empty, &nine, &mut out).unwrap();
        assert_eq!(out, [0x09, 0, 0, 0, 0, 0, 0, 0, 0, 0]);
        assert_eq!(decode(&empty, &out).unwrap(), nine);
        assert!(
            decode(&empty, &[0x03]).is_err(),
            "three records in one byte"
        );
        // the tenth byte of a number has room for one bit
        let ten = |last| [0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, last];
        assert_eq!(decode(&Shape::Int, &ten(0x01)).unwrap(), json!(i64::MIN));
        assert!(decode(&Shape::Int, &ten(0x02)).is_err());
        // a flag is 0 or 1
        assert!(decode(&Shape::Bool, &[0x02]).is_err());
        assert!(decode(&Shape::Opt(Box::new(Shape::Int)), &[0x02, 0x00]).is_err());
        // a number an f32 cannot hold
        assert!(encode(&Shape::Float, &json!(1e300), &mut vec![]).is_err());
    }

    #[test]
    fn a_text_by_reference_has_the_bytes_written_by_hand() {
        // FNV-1a of "a" is 0xe40c292c (the published test value), little-endian
        let mut out = vec![];
        encode(&Shape::TextRef, &json!("a"), &mut out).unwrap();
        assert_eq!(out, [0x2c, 0x29, 0x0c, 0xe4]);
        let back = decode(&Shape::TextRef, &out).unwrap();
        assert_eq!(back, json!(0xe40c292c_u32));
        assert!(same(&Shape::TextRef, &back, &json!("a")));
    }

    #[test]
    fn packed_rounds_before_zero_and_an_empty_one_reads_back() {
        let s = Shape::Packed(vec![Shape::Tenths]);
        let mut out = vec![];
        encode(&s, &json!([0.04]), &mut out).unwrap();
        assert_eq!(out, [0x01], "0.04 rounds to 0.0: the zero bit, no value");
        assert_eq!(decode(&s, &out).unwrap(), json!([0.0]));
        let empty = Shape::Packed(vec![]);
        let mut out = vec![];
        encode(&empty, &json!([]), &mut out).unwrap();
        assert_eq!(out, [0u8; 0]);
        assert_eq!(decode(&empty, &out).unwrap(), json!([]));
    }

    #[test]
    fn a_short_tuple_reads_back() {
        let s = Shape::Tuple(vec![Shape::Int]);
        let mut out = vec![];
        encode(&s, &json!([0]), &mut out).unwrap();
        assert_eq!(out, [0x00]);
        assert_eq!(decode(&s, &out).unwrap(), json!([0]));
    }

    #[test]
    fn any_keeps_a_value_exactly() {
        let s = Shape::List(Box::new(Shape::Any));
        let v = json!([1, {"a": null}]);
        let mut out = vec![];
        encode(&s, &v, &mut out).unwrap();
        assert!(same(&s, &decode(&s, &out).unwrap(), &v));
    }
}
