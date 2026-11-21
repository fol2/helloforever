//! `hellolink replay RECORD | measure [--shapes]`: step 1 of docs/specs/232.md. For every
//! version of strip format 2's objects in the replay (sent plain or deflated; a version whose
//! text is `null`, an object the addon could not read, left out), the bytes it takes:
//!
//! - `json`: the object's text as the addon wrote it;
//! - `sent`: what format 2 sent: the text, or its deflate when the addon sent it deflated. The
//!   client's deflate is not in the record: miniz at level 6 stands in for it (an estimate);
//! - `binary`: format 3's binary form, with the shape learnt from the whole replay;
//! - `binary+deflate`: the same, deflated by miniz at level 6;
//! - `by-reference`: the binary form with each `Text` as a `TextRef` (4 bytes) and each list of
//!   4 or more whole numbers in rising order as its first number and the steps after it. Values
//!   whose shapes did not agree (`Any`) stay JSON text, texts in them included.
//!
//! The texts that `by-reference` leaves out are counted once each, as format 3 would send them in
//! a slow round: a 4-byte hash and the text (`Text`). Every version must come back the same from
//! its binary form, or the tool fails. `--shapes` prints the learnt shapes too.

use hellolink_format::{Shape, decode, encode, learn, same};
use miniz_oxide::deflate::compress_to_vec;
use serde_json::Value;
use std::collections::{BTreeMap, BTreeSet};
use std::io::BufRead;

#[derive(Default)]
struct Sums {
    n: usize,
    json: usize,
    sent: usize,
    binary: usize,
    binary_deflated: usize,
    refs: usize,
    /// With the hand-written shape of `objects.rs`, the format byte and the check included.
    schema: usize,
}

impl Sums {
    fn add(&mut self, o: &Sums) {
        self.n += o.n;
        self.json += o.json;
        self.sent += o.sent;
        self.binary += o.binary;
        self.binary_deflated += o.binary_deflated;
        self.refs += o.refs;
        self.schema += o.schema;
    }
}

/// A list of 4 or more whole numbers in rising order as its first number and the steps.
fn steps(v: &Value) -> Value {
    match v {
        Value::Array(items) => {
            let n: Option<Vec<i64>> = items.iter().map(Value::as_i64).collect();
            let stepped: Option<Vec<i64>> = n
                .filter(|n| n.len() >= 4 && n.windows(2).all(|w| w[0] <= w[1]))
                .and_then(|n| {
                    let mut out = vec![n[0]];
                    for w in n.windows(2) {
                        out.push(w[1].checked_sub(w[0])?);
                    }
                    Some(out)
                });
            match stepped {
                Some(s) => Value::from(s),
                None => Value::Array(items.iter().map(steps).collect()),
            }
        }
        Value::Object(m) => Value::Object(m.iter().map(|(k, x)| (k.clone(), steps(x))).collect()),
        v => v.clone(),
    }
}

/// The shape with every `Text` a `TextRef`.
fn by_reference(s: &Shape) -> Shape {
    match s {
        Shape::Text => Shape::TextRef,
        Shape::List(inner) => Shape::List(Box::new(by_reference(inner))),
        Shape::Opt(inner) => Shape::Opt(Box::new(by_reference(inner))),
        Shape::Record(fields) => Shape::Record(
            fields
                .iter()
                .map(|(k, f)| (k.clone(), by_reference(f)))
                .collect(),
        ),
        s => s.clone(),
    }
}

/// The texts that shape `s` sends by reference in `v`.
fn texts(s: &Shape, v: &Value, out: &mut BTreeSet<String>) {
    match (s, v) {
        (Shape::TextRef, Value::String(t)) => {
            out.insert(t.clone());
        }
        (Shape::List(inner), Value::Array(items)) => {
            items.iter().for_each(|x| texts(inner, x, out))
        }
        (Shape::Opt(inner), v) => texts(inner, v, out),
        (Shape::Record(fields), Value::Object(m)) => {
            for (k, f) in fields {
                if let Some(x) = m.get(k) {
                    texts(f, x, out);
                }
            }
        }
        _ => {}
    }
}

fn main() -> Result<(), String> {
    let shapes_too = std::env::args().any(|a| a == "--shapes");
    // (id, the text as the addon wrote it, sent deflated, the value)
    let mut objects: Vec<(u64, String, bool, Value)> = vec![];
    for line in std::io::stdin().lock().lines() {
        let e: Value =
            serde_json::from_str(&line.map_err(|e| e.to_string())?).map_err(|e| e.to_string())?;
        // only strip format 2's objects: the replay gives a session only to those
        if e["kind"] != "object" || e.get("session").is_none() {
            continue;
        }
        let (Some(id), Some(text), Some(format)) =
            (e["id"].as_u64(), e["text"].as_str(), e["format"].as_u64())
        else {
            continue;
        };
        let v: Value = serde_json::from_str(text).map_err(|e| format!("object {id}: {e}"))?;
        if !v.is_null() {
            objects.push((id, text.to_owned(), format == 1, v));
        }
    }
    let stepped: Vec<Value> = objects.iter().map(|(_, _, _, v)| steps(v)).collect();
    let mut shapes: BTreeMap<u64, Shape> = BTreeMap::new();
    let mut ref_shapes: BTreeMap<u64, Shape> = BTreeMap::new();
    for ((id, _, _, v), r) in objects.iter().zip(&stepped) {
        let s = shapes.remove(id).unwrap_or(Shape::Never);
        shapes.insert(*id, learn(s, v));
        let s = ref_shapes.remove(id).unwrap_or(Shape::Never);
        ref_shapes.insert(*id, learn(s, r));
    }
    let ref_shapes: BTreeMap<u64, Shape> = ref_shapes
        .iter()
        .map(|(id, s)| (*id, by_reference(s)))
        .collect();
    let mut sums: BTreeMap<u64, Sums> = BTreeMap::new();
    let mut dictionary = BTreeSet::new();
    for ((id, text, deflated, v), r) in objects.iter().zip(&stepped) {
        let mut binary = vec![];
        encode(&shapes[id], v, &mut binary).map_err(|e| format!("object {id}: {e}"))?;
        if !same(&shapes[id], &decode(&shapes[id], &binary)?, v) {
            return Err(format!("object {id} does not come back the same: {text}"));
        }
        let mut by_ref = vec![];
        encode(&ref_shapes[id], r, &mut by_ref).map_err(|e| format!("object {id}: {e}"))?;
        if !same(&ref_shapes[id], &decode(&ref_shapes[id], &by_ref)?, r) {
            return Err(format!(
                "object {id} by reference does not come back the same"
            ));
        }
        texts(&ref_shapes[id], r, &mut dictionary);
        let s = sums.entry(*id).or_default();
        s.n += 1;
        s.json += text.len();
        // the object bytes: the format byte and the check too, as for the hand shape below
        s.sent += 3 + match deflated {
            true => compress_to_vec(text.as_bytes(), 6).len(),
            false => text.len(),
        };
        s.binary += binary.len();
        s.binary_deflated += compress_to_vec(&binary, 6).len();
        s.refs += by_ref.len();
        if let Some(shape) = hellolink_format::objects::shape(*id as u8) {
            let mut b = vec![];
            encode(&shape, v, &mut b).map_err(|e| format!("object {id} in its shape: {e}"))?;
            s.schema += b.len() + 3;
        }
    }
    let mut dictionary_bytes = 0;
    for t in &dictionary {
        let mut out = vec![];
        encode(&Shape::Text, &Value::from(t.as_str()), &mut out)?;
        dictionary_bytes += 4 + out.len();
    }
    println!(
        "object  versions  json  sent  binary  binary+deflate  by-reference  hand-shape   (bytes a version, mean)"
    );
    let mut all = Sums::default();
    for (id, s) in &sums {
        let mean = |x: usize| x as f64 / s.n as f64;
        println!(
            "{id:>6}  {:>8}  {:>4.0}  {:>4.0}  {:>6.0}  {:>14.0}  {:>12.0}  {:>10}",
            s.n,
            mean(s.json),
            mean(s.sent),
            mean(s.binary),
            mean(s.binary_deflated),
            mean(s.refs),
            if s.schema > 0 {
                format!("{:.0}", mean(s.schema))
            } else {
                "-".into()
            }
        );
        all.add(s);
    }
    let pct = |x: usize| 100.0 * x as f64 / all.sent.max(1) as f64;
    println!(
        "   all  {:>8}  {:>4}  {:>4}  {:>6}  {:>14}  {:>12}   (bytes, sum)",
        all.n, all.json, all.sent, all.binary, all.binary_deflated, all.refs
    );
    println!(
        "of sent: json {:.0} %, binary {:.0} %, binary+deflate {:.0} %, by-reference {:.0} %; \
         {} texts by reference, {} bytes once: {:.0} % with them",
        pct(all.json),
        pct(all.binary),
        pct(all.binary_deflated),
        pct(all.refs),
        dictionary.len(),
        dictionary_bytes,
        pct(all.refs + dictionary_bytes)
    );
    if shapes_too {
        for (id, s) in &shapes {
            println!("{id}: {s:?}");
        }
    }
    Ok(())
}
