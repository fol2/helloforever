//! `rows`: the row of each image as one JSON line, byte for byte as
//! `hellolink_strip.py rows` prints it (Python's json.dumps with sort_keys).

use crate::bitmap::Bitmap;
use crate::strip1::{Assembler, Fast, Row, read_row};
use serde::Serialize;
use serde_json::{Value, json};
use std::io::{self, Write};

/// Python's repr() of a float: the shortest text that reads back the same, with ".0" on a
/// whole number and an exponent below 1e-4 and from 1e16.
pub fn py_float(v: f64) -> String {
    if v.is_nan() {
        return "NaN".into();
    }
    if v.is_infinite() {
        return if v > 0.0 { "Infinity" } else { "-Infinity" }.into();
    }
    let sci = format!("{v:e}");
    let (mantissa, exp) = sci.split_once('e').unwrap_or((&sci, "0"));
    let exp: i32 = exp.parse().unwrap_or(0);
    if (-4..16).contains(&exp) {
        let fixed = format!("{v}");
        return if fixed.contains('.') {
            fixed
        } else {
            fixed + ".0"
        };
    }
    format!(
        "{mantissa}e{}{:02}",
        if exp < 0 { '-' } else { '+' },
        exp.abs()
    )
}

/// The separators of Python's json.dumps (", " and ": ") and its floats.
struct Python;

impl serde_json::ser::Formatter for Python {
    fn begin_array_value<W: ?Sized + Write>(&mut self, w: &mut W, first: bool) -> io::Result<()> {
        if first { Ok(()) } else { w.write_all(b", ") }
    }
    fn begin_object_key<W: ?Sized + Write>(&mut self, w: &mut W, first: bool) -> io::Result<()> {
        if first { Ok(()) } else { w.write_all(b", ") }
    }
    fn begin_object_value<W: ?Sized + Write>(&mut self, w: &mut W) -> io::Result<()> {
        w.write_all(b": ")
    }
    fn write_f64<W: ?Sized + Write>(&mut self, w: &mut W, v: f64) -> io::Result<()> {
        w.write_all(py_float(v).as_bytes())
    }
}

/// A value as Python's json.dumps(..., ensure_ascii=False, sort_keys=True) writes it.
/// serde_json's maps keep their keys sorted.
pub fn dumps(value: &Value) -> String {
    let mut out = Vec::new();
    let mut ser = serde_json::Serializer::with_formatter(&mut out, Python);
    // Writing to a Vec does not fail, and a Value always serialises.
    let _ = value.serialize(&mut ser);
    String::from_utf8_lossy(&out).into_owned()
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
    dumps(&json!({
        "i": i, "row": true, "session": row.session, "depth": row.depth, "levels": row.levels,
        "why": row.why, "apart": row.apart, "square": row.square,
        "seq": frame.map(|f| f.seq), "dwell": frame.map(|f| f.dwell), "fast": frame.map(|f| fast_json(&f.fast)),
        "chunk": chunk.map(|c| json!([c.oid, c.version, c.index, c.count, c.data.len()])),
        "object": done.map(|d| json!([d.0, d.1, d.2])),
    }))
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
