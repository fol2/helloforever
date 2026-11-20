//! `rows`: the row of each image as one JSON line, byte for byte as
//! `hellolink_strip.py rows` prints it (Python's json.dumps with sort_keys).

use crate::bitmap::Bitmap;
use crate::strip1::{Assembler, Fast, Row, read_row};
use serde::Serialize;
use serde_json::{Value, json};
use std::io::{self, Write};

/// The digits and the exponent of `{:.N e}` text ("1.25e3" is ("125", 3)).
fn digits_of(sci: &str) -> (String, i32) {
    let (mantissa, exp) = sci.split_once('e').unwrap_or((sci, "0"));
    (mantissa.replace('.', ""), exp.parse().unwrap_or(0))
}

/// Python's repr() of a float: the shortest text that reads back the same, and of those the
/// nearest to the exact value (Rust's shortest text can be the other one: 1794516378.0039062
/// is Python's, 1794516378.0039063 Rust's). With ".0" on a whole number, and an exponent
/// below 1e-4 and from 1e16.
pub fn py_float(v: f64) -> String {
    if v.is_nan() {
        return "NaN".into();
    }
    if v.is_infinite() {
        return if v > 0.0 { "Infinity" } else { "-Infinity" }.into();
    }
    let sign = if v.is_sign_negative() { "-" } else { "" };
    let a = v.abs();
    // Rust gives the shortest length; `{:.N e}` rounds to the nearest (halves to even). The
    // nearest of that length is taken when it reads back the same.
    let (shortest, exp) = digits_of(&format!("{a:e}"));
    let nearest = format!("{a:.*e}", shortest.len() - 1);
    let (digits, exp) = if nearest.parse::<f64>().ok() == Some(a) {
        digits_of(&nearest)
    } else {
        (shortest, exp)
    };
    let digits = match digits.trim_end_matches('0') {
        "" => "0",
        d => d,
    };
    if (-4..16).contains(&exp) {
        let point = exp + 1; // digits before the point
        if point <= 0 {
            return format!("{sign}0.{}{digits}", "0".repeat(-point as usize));
        }
        let point = point as usize;
        if digits.len() <= point {
            return format!("{sign}{digits}{}.0", "0".repeat(point - digits.len()));
        }
        return format!("{sign}{}.{}", &digits[..point], &digits[point..]);
    }
    let rest = if digits.len() > 1 {
        format!(".{}", &digits[1..])
    } else {
        String::new()
    };
    format!(
        "{sign}{}{rest}e{}{:02}",
        &digits[..1],
        if exp < 0 { '-' } else { '+' },
        exp.abs()
    )
}

/// Python's json.dumps: its separators, its floats, and with `ascii` (ensure_ascii=True)
/// every character from DEL on written as \\uXXXX.
struct Python {
    item: &'static [u8],
    key: &'static [u8],
    ascii: bool,
}

impl serde_json::ser::Formatter for Python {
    fn begin_array_value<W: ?Sized + Write>(&mut self, w: &mut W, first: bool) -> io::Result<()> {
        if first {
            Ok(())
        } else {
            w.write_all(self.item)
        }
    }
    fn begin_object_key<W: ?Sized + Write>(&mut self, w: &mut W, first: bool) -> io::Result<()> {
        if first {
            Ok(())
        } else {
            w.write_all(self.item)
        }
    }
    fn begin_object_value<W: ?Sized + Write>(&mut self, w: &mut W) -> io::Result<()> {
        w.write_all(self.key)
    }
    fn write_f64<W: ?Sized + Write>(&mut self, w: &mut W, v: f64) -> io::Result<()> {
        w.write_all(py_float(v).as_bytes())
    }
    fn write_string_fragment<W: ?Sized + Write>(
        &mut self,
        w: &mut W,
        part: &str,
    ) -> io::Result<()> {
        if !self.ascii {
            return w.write_all(part.as_bytes());
        }
        for c in part.chars() {
            if (c as u32) < 0x7F {
                w.write_all(&[c as u8])?;
            } else {
                for unit in c.encode_utf16(&mut [0; 2]) {
                    write!(w, "\\u{unit:04x}")?;
                }
            }
        }
        Ok(())
    }
}

fn dumps_with(value: &Value, format: Python) -> String {
    let mut out = Vec::new();
    let mut ser = serde_json::Serializer::with_formatter(&mut out, format);
    // Writing to a Vec does not fail, and a Value always serialises.
    let _ = value.serialize(&mut ser);
    String::from_utf8_lossy(&out).into_owned()
}

/// A value as Python's json.dumps(..., ensure_ascii=False, sort_keys=True) writes it.
/// serde_json's maps keep their keys sorted.
pub fn dumps(value: &Value) -> String {
    dumps_with(
        value,
        Python {
            item: b", ",
            key: b": ",
            ascii: false,
        },
    )
}

/// A value as Python's json.dumps(value) writes it (ASCII only), keys sorted.
pub fn dumps_ascii(value: &Value) -> String {
    dumps_with(
        value,
        Python {
            item: b", ",
            key: b": ",
            ascii: true,
        },
    )
}

/// A value as Python's json.dumps(..., separators=(",", ":")) writes it, keys sorted.
pub fn dumps_compact(value: &Value) -> String {
    dumps_with(
        value,
        Python {
            item: b",",
            key: b":",
            ascii: true,
        },
    )
}

pub fn fast_json(fast: &Fast) -> Value {
    let mut out = serde_json::Map::new();
    for (name, fields) in fast {
        let v = fields
            .as_ref()
            .map(|f| f.iter().map(|(k, v)| (k.to_string(), json!(v))).collect());
        out.insert(name.to_string(), v.map_or(Value::Null, Value::Object));
    }
    Value::Object(out)
}

/// One image's line. `None` is an image with no row.
pub fn row_line(i: usize, row: Option<&Row>, done: Option<&crate::strip1::Done>) -> String {
    let Some(row) = row else {
        return dumps(&json!({"i": i, "row": false}));
    };
    let frame = row.frame.as_ref();
    let chunk = frame.and_then(|f| f.chunk.as_ref());
    let mut line = json!({
        "i": i, "row": true, "session": row.session, "depth": row.depth, "levels": row.levels,
        "why": row.why, "apart": row.apart, "square": row.square,
        "seq": frame.map(|f| f.seq), "dwell": frame.map(|f| f.dwell), "fast": frame.map(|f| fast_json(&f.fast)),
        "chunk": chunk.map(|c| json!([c.oid, c.version, c.index, c.count, c.data.len()])),
        "object": done.map(|d| json!([d.0, d.1, d.2])),
    });
    // format 2 (docs/specs/213.md): the frame's bytes too, for a record that `replay` reads
    if row.format == 2 {
        line["format"] = json!(2);
        line["more"] = json!(row.more);
        line["frame"] = json!(
            row.raw
                .as_deref()
                .map(|b| b.iter().map(|x| format!("{x:02x}")).collect::<String>())
        );
    }
    dumps(&line)
}

/// Reads the row of each image in turn, as captures `step` seconds apart, and writes one
/// line an image: what the row holds, and an object when one completes. With `hinted`, the
/// grid of the last good read is tried first, as the live reader does; `hellolink_strip.py
/// rows` on main does not.
pub fn rows_of_images(
    images: &[Bitmap],
    step: f64,
    hinted: bool,
    out: &mut impl Write,
) -> io::Result<()> {
    let mut joiner = Assembler::default();
    let mut hint = None;
    for (i, bmp) in images.iter().enumerate() {
        let row = read_row(bmp, hint);
        let mut done = None;
        if let Some(frame) = row.as_ref().and_then(|r| r.frame.as_ref()) {
            done = joiner.feed(frame, i as f64 * step);
            if hinted {
                hint = row.as_ref().and_then(|r| r.grid);
            }
        }
        writeln!(out, "{}", row_line(i, row.as_ref(), done.as_ref()))?;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn compact_json_as_python_writes_it_with_ensure_ascii() {
        // What python3 -c 'json.dumps(v, separators=(",", ":"), sort_keys=True)' printed.
        let v = json!({"b": ["café ☃ 雪 😀\u{7f}\u{1f}\n\"\\", 1.5, null], "a": 2});
        assert_eq!(
            dumps_compact(&v),
            r#"{"a":2,"b":["caf\u00e9 \u2603 \u96ea \ud83d\ude00\u007f\u001f\n\"\\",1.5,null]}"#
        );
    }
}
