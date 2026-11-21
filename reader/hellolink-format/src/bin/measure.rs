//! `hellolink replay RECORD | measure [--shapes]`: step 1 of docs/specs/232.md. For each of
//! format 2's objects in the replay, the bytes it takes as JSON, as JSON plus deflate (as the
//! addon sends it; miniz at level 6 stands in for the client's deflate), and in format 3's
//! binary form with the shape learnt from the whole replay. Every object must come back the
//! same from its binary form, or the tool fails. `--shapes` prints the learnt shapes too.

use hellolink_format::{Shape, decode, encode, learn, same};
use miniz_oxide::deflate::compress_to_vec;
use serde_json::Value;
use std::collections::{BTreeMap, BTreeSet};
use std::io::BufRead;

#[derive(Default)]
struct Sums {
    n: usize,
    json: usize,
    deflated: usize,
    binary: usize,
    binary_deflated: usize,
    refs: usize,
}

/// `v` as a hand-written schema could send it, to measure that too: each text by a 4-byte
/// reference (the text itself goes once, in a slow round, and is added to `texts`), and a list
/// of 4 or more whole numbers in rising order as its first number and the steps after it.
fn by_reference(v: &Value, texts: &mut BTreeSet<String>) -> Value {
    match v {
        Value::String(t) => {
            texts.insert(t.clone());
            Value::from("ref") // 1 byte of length and 3 bytes: the size of a 32-bit reference
        }
        Value::Array(items) => {
            let n: Option<Vec<i64>> = items.iter().map(Value::as_i64).collect();
            match n {
                Some(n) if n.len() >= 4 && n.windows(2).all(|w| w[0] <= w[1]) => {
                    let steps = n.windows(2).map(|w| w[1] - w[0]);
                    Value::from(std::iter::once(n[0]).chain(steps).collect::<Vec<_>>())
                }
                _ => Value::Array(items.iter().map(|x| by_reference(x, texts)).collect()),
            }
        }
        Value::Object(m) => Value::Object(
            m.iter()
                .map(|(k, x)| (k.clone(), by_reference(x, texts)))
                .collect(),
        ),
        v => v.clone(),
    }
}

fn main() -> Result<(), String> {
    let shapes_too = std::env::args().any(|a| a == "--shapes");
    let mut objects: Vec<(u64, Value)> = vec![];
    for line in std::io::stdin().lock().lines() {
        let e: Value =
            serde_json::from_str(&line.map_err(|e| e.to_string())?).map_err(|e| e.to_string())?;
        if e["kind"] != "object" || e["format"] == 0 {
            continue;
        }
        let (Some(id), Some(text)) = (e["id"].as_u64(), e["text"].as_str()) else {
            continue;
        };
        let v: Value = serde_json::from_str(text).map_err(|e| format!("object {id}: {e}"))?;
        if !v.is_null() {
            objects.push((id, v));
        }
    }
    let mut shapes: BTreeMap<u64, Shape> = BTreeMap::new();
    let (mut ref_shapes, mut texts) = (BTreeMap::new(), BTreeSet::new());
    let refs: Vec<Value> = objects
        .iter()
        .map(|(_, v)| by_reference(v, &mut texts))
        .collect();
    for ((id, v), r) in objects.iter().zip(&refs) {
        let s = shapes.remove(id).unwrap_or(Shape::Never);
        shapes.insert(*id, learn(s, v));
        let s = ref_shapes.remove(id).unwrap_or(Shape::Never);
        ref_shapes.insert(*id, learn(s, r));
    }
    let mut sums: BTreeMap<u64, Sums> = BTreeMap::new();
    for ((id, v), r) in objects.iter().zip(&refs) {
        let json = serde_json::to_string(v).map_err(|e| e.to_string())?;
        let mut binary = vec![];
        encode(&shapes[id], v, &mut binary).map_err(|e| format!("object {id}: {e}"))?;
        if !same(&decode(&shapes[id], &binary)?, v) {
            return Err(format!("object {id} does not come back the same: {json}"));
        }
        let mut by_ref = vec![];
        encode(&ref_shapes[id], r, &mut by_ref).map_err(|e| format!("object {id}: {e}"))?;
        let s = sums.entry(*id).or_default();
        s.n += 1;
        s.json += json.len();
        s.deflated += compress_to_vec(json.as_bytes(), 6).len();
        s.binary += binary.len();
        s.binary_deflated += compress_to_vec(&binary, 6).len();
        s.refs += by_ref.len();
    }
    println!(
        "object  versions  json  json+deflate  binary  binary+deflate  by-reference   (bytes a version, mean)"
    );
    let mut all = Sums::default();
    for (id, s) in &sums {
        let mean = |x: usize| x as f64 / s.n as f64;
        println!(
            "{id:>6}  {:>8}  {:>4.0}  {:>12.0}  {:>6.0}  {:>14.0}  {:>12.0}",
            s.n,
            mean(s.json),
            mean(s.deflated),
            mean(s.binary),
            mean(s.binary_deflated),
            mean(s.refs)
        );
        all.n += s.n;
        all.json += s.json;
        all.deflated += s.deflated;
        all.binary += s.binary;
        all.binary_deflated += s.binary_deflated;
        all.refs += s.refs;
    }
    let text_bytes: usize = texts.iter().map(|t| 1 + t.len()).sum();
    let pct = |x: usize| 100.0 * x as f64 / all.deflated.max(1) as f64;
    println!(
        "   all  {:>8}  {:>4}  {:>12}  {:>6}  {:>14}  {:>12}   (bytes, sum)",
        all.n, all.json, all.deflated, all.binary, all.binary_deflated, all.refs
    );
    println!(
        "of json+deflate: binary {:.0} %, binary+deflate {:.0} %, by-reference {:.0} % (+ {} distinct texts, {} bytes once: {:.0} % with them)",
        pct(all.binary),
        pct(all.binary_deflated),
        pct(all.refs),
        texts.len(),
        text_bytes,
        pct(all.refs + text_bytes)
    );
    if shapes_too {
        for (id, s) in &shapes {
            println!("{id}: {s:?}");
        }
    }
    Ok(())
}
