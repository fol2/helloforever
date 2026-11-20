//! `hellolink replay RECORD`: a record of `watch --record` (docs/STRIP.md, section 10) fed
//! back through the Watcher, for measurement offline (#213, step 5). Each event `watch --json`
//! said comes out as one JSON line with the capture's time `t` added; each run's header comes
//! out as `{"kind": "record", "started": ...}`, and a new Watcher starts with it.
//!
//! The record holds what the Watcher needs but the picture: a frame's bytes when they changed,
//! the depth and levels when they changed, `why` for a capture with no frame. A line with only
//! `t` is the last good frame again. The squares' session is the frame's (section 2). For a
//! capture with no frame the depth and session are the last known.

use crate::rows::dumps;
use crate::strip1::{Row, unpack_frame};
use crate::watch::Watcher;
use serde_json::{Value, json};
use std::io::{BufRead, Write};

fn bytes(hex: &str) -> Option<Vec<u8>> {
    if !hex.len().is_multiple_of(2) {
        return None;
    }
    (0..hex.len())
        .step_by(2)
        .map(|i| u8::from_str_radix(hex.get(i..i + 2)?, 16).ok())
        .collect()
}

/// Reads the record's lines from `input` and writes the events to `out`.
pub fn replay(input: impl BufRead, out: &mut impl Write) -> Result<(), String> {
    let mut watcher: Option<Watcher> = None;
    // the last good frame's bytes, depth, levels and session
    let mut raw: Option<Vec<u8>> = None;
    let mut depth: Option<u8> = None;
    let mut levels = [None; 4];
    let mut session: Option<u32> = None;
    for (n, line) in input.lines().enumerate() {
        let at = |why: &str| format!("line {}: {why}", n + 1);
        let line = line.map_err(|e| at(&e.to_string()))?;
        if line.trim().is_empty() {
            continue;
        }
        let v: Value = serde_json::from_str(&line).map_err(|e| at(&e.to_string()))?;
        if v.get("record").is_some() {
            watcher = Some(Watcher::default());
            (raw, depth, levels, session) = (None, None, [None; 4], None);
            let event = json!({"kind": "record", "started": v["started"]});
            writeln!(out, "{}", dumps(&event)).map_err(|e| e.to_string())?;
            continue;
        }
        let w = watcher.as_mut().ok_or_else(|| at("no header before it"))?;
        let t = v["t"].as_f64().ok_or_else(|| at("no time"))?;
        if let Some(d) = v.get("depth") {
            depth = Some(
                d.as_u64()
                    .and_then(|d| u8::try_from(d).ok())
                    .ok_or_else(|| at("bad depth"))?,
            );
        }
        if let Some(l) = v.get("levels") {
            let l: [Option<i64>; 4] =
                serde_json::from_value(l.clone()).map_err(|_| at("bad levels"))?;
            levels = l;
        }
        if let Some(f) = v.get("frame") {
            raw = Some(
                f.as_str()
                    .and_then(bytes)
                    .ok_or_else(|| at("bad frame hex"))?,
            );
        }
        let why = v.get("why");
        let frame = match (why, &raw) {
            (Some(_), _) | (None, None) => None,
            (None, Some(raw)) => Some(unpack_frame(raw).map_err(|e| at(&e))?),
        };
        if let Some(f) = &frame {
            session = Some(f.session as u32);
        }
        let row = match (why, frame) {
            (Some(w), _) if w == "no row" => None,
            (why, frame) => Some(Row {
                session,
                depth,
                levels,
                frame,
                why: why.and_then(|w| w.as_str()).map(String::from),
                apart: None,
                square: 0.0,
                r#box: None,
                grid: None,
                raw: None,
                palette: None,
            }),
        };
        for mut event in w.feed_row(row, t) {
            event["t"] = json!(t);
            writeln!(out, "{}", dumps(&event)).map_err(|e| e.to_string())?;
        }
    }
    if watcher.is_none() {
        return Err("line 1: no header".into());
    }
    Ok(())
}
