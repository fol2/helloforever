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
//! - `List`: the count (LEB128), then the items.
//! - `Record`: a presence bit a field (field 0 in bit 0 of the first byte), then the present
//!   fields in order. A field that is missing or null is absent.
//! - `Opt` (a list item that can be null): one byte, 0 for null or 1, then the value.
//! - `Any` (values whose shapes did not agree): the JSON text, as `Text`.

use serde_json::{Map, Number, Value};

#[derive(Clone, Debug, PartialEq)]
pub enum Shape {
    /// No value seen yet.
    Never,
    Bool,
    Int,
    Float,
    Text,
    List(Box<Shape>),
    Record(Vec<(String, Shape)>),
    Opt(Box<Shape>),
    Any,
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
            out.extend((n.as_f64().unwrap_or_default() as f32).to_le_bytes())
        }
        (Shape::Text, Value::String(t)) => text(out, t),
        (Shape::List(inner), Value::Array(items)) => {
            leb(out, items.len() as u64);
            for item in items {
                encode(inner, item, out)?;
            }
        }
        (Shape::Record(fields), Value::Object(m)) => {
            let at = out.len();
            out.resize(at + fields.len().div_ceil(8), 0);
            for (i, (name, inner)) in fields.iter().enumerate() {
                if let Some(val) = m.get(name).filter(|val| !val.is_null()) {
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
        (s, v) => return Err(format!("{v} is not of shape {s:?}")),
    }
    Ok(())
}

struct Reader<'a> {
    bytes: &'a [u8],
    at: usize,
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

    fn value(&mut self, s: &Shape) -> Result<Value, String> {
        Ok(match s {
            Shape::Never => return Err("a value of no shape".into()),
            Shape::Bool => Value::Bool(self.byte()? != 0),
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
            Shape::List(inner) => {
                let n = self.leb()?;
                let mut items = vec![];
                for _ in 0..n {
                    items.push(self.value(inner)?);
                }
                Value::Array(items)
            }
            Shape::Record(fields) => {
                let at = self.at;
                self.at = at
                    .checked_add(fields.len().div_ceil(8))
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
            Shape::Opt(inner) => match self.byte()? {
                0 => Value::Null,
                _ => self.value(inner)?,
            },
            Shape::Any => serde_json::from_str(&self.text()?).map_err(|e| e.to_string())?,
        })
    }
}

/// Reads one value of shape `s`; every byte must be used.
pub fn decode(s: &Shape, bytes: &[u8]) -> Result<Value, String> {
    let mut r = Reader { bytes, at: 0 };
    let v = r.value(s)?;
    if r.at != bytes.len() {
        return Err(format!("{} bytes left over", bytes.len() - r.at));
    }
    Ok(v)
}

/// Whether `back` (a value decoded) is `v` as the binary form keeps it: record fields that are
/// null left out, a number as an `f32` where its shape is `Float`.
pub fn same(back: &Value, v: &Value) -> bool {
    match (back, v) {
        (Value::Object(a), Value::Object(b)) => {
            let present = || b.iter().filter(|(_, x)| !x.is_null());
            a.len() == present().count()
                && present().all(|(k, x)| a.get(k).is_some_and(|y| same(y, x)))
        }
        (Value::Array(a), Value::Array(b)) => {
            a.len() == b.len() && a.iter().zip(b).all(|(y, x)| same(y, x))
        }
        (Value::Number(a), Value::Number(b)) if !(a.is_i64() && b.is_i64()) => {
            a.as_f64().map(|f| f as f32) == b.as_f64().map(|f| f as f32)
        }
        (a, b) => a == b,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

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
            assert!(same(&decode(&s, &out).unwrap(), v), "{v}");
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
}
