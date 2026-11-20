//! `--record`: a record of what the reader read, for measurement offline (#178; docs/STRIP.md,
//! section 10). The `Recorder` of tools/hellolink_strip.py, line for line the same.

use crate::rows::dumps_compact;
use crate::strip1::Row;
use serde_json::{Value, json};
use std::fs::{File, OpenOptions};
use std::io::{self, Write};
use std::path::Path;
use std::time::{SystemTime, UNIX_EPOCH};

/// A header line, then one JSON line a capture: `t`, seconds since the first capture; `frame`
/// (hex) when a good frame's bytes changed; `depth`, `levels` and `palette` when they changed,
/// also on a capture whose frame failed; for a capture with no frame, `why` and, when bytes
/// were read, `bad` (hex: all of a failed frame, or as much as was read). The file is appended
/// to and written a line at a time.
pub struct Recorder {
    file: File,
    t0: Option<f64>,
    frame: Option<Vec<u8>>,
    depth: Option<u8>,
    levels: Option<[Option<i64>; 4]>,
    /// Format 2: the further level triples (docs/specs/213.md, section 8).
    more: Option<Vec<Option<i64>>>,
    palette: Option<Vec<[u8; 3]>>,
}

fn hex(data: &[u8]) -> String {
    data.iter().map(|b| format!("{b:02x}")).collect()
}

/// Python's round(x, 3): the nearest number of three decimals, halves to the even one.
fn round3(x: f64) -> f64 {
    format!("{x:.3}").parse().unwrap_or(x)
}

impl Recorder {
    /// Opens the record and writes its header. `started` is the Unix time; None is now.
    pub fn new(path: &Path, started: Option<f64>) -> io::Result<Recorder> {
        let file = OpenOptions::new().create(true).append(true).open(path)?;
        let mut record = Recorder {
            file,
            t0: None,
            frame: None,
            depth: None,
            levels: None,
            more: None,
            palette: None,
        };
        let started = started.unwrap_or_else(|| {
            SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .map_or(0.0, |d| d.as_secs_f64())
        });
        record.line(&[("record", json!(1)), ("started", json!(started))])?;
        Ok(record)
    }

    /// One line, its keys in the order given, as Python's json.dumps writes a dict.
    fn line(&mut self, pairs: &[(&str, Value)]) -> io::Result<()> {
        let parts: Vec<String> = pairs
            .iter()
            .map(|(k, v)| format!("{}:{}", dumps_compact(&json!(k)), dumps_compact(v)))
            .collect();
        self.file
            .write_all(format!("{{{}}}\n", parts.join(",")).as_bytes())
    }

    /// Takes what read_row returned for a capture at time `now`.
    pub fn note(&mut self, row: Option<&Row>, now: f64) -> io::Result<()> {
        let t0 = *self.t0.get_or_insert(now);
        let mut out = vec![("t", json!(round3(now - t0)))];
        let Some(row) = row else {
            out.push(("why", json!("no row")));
            return self.line(&out);
        };
        if row.frame.is_some() {
            if row.raw != self.frame {
                self.frame = row.raw.clone();
                out.push(("frame", json!(row.raw.as_deref().map(hex))));
            }
        } else {
            out.push(("why", json!(row.why)));
            if let Some(raw) = &row.raw {
                out.push(("bad", json!(hex(raw))));
            }
        }
        if row.depth.is_some() {
            if row.depth != self.depth {
                self.depth = row.depth;
                out.push(("depth", json!(row.depth)));
            }
            if Some(row.levels) != self.levels {
                self.levels = Some(row.levels);
                out.push(("levels", json!(row.levels)));
            }
        }
        if row.format == 2 && row.depth.is_some() && Some(&row.more) != self.more.as_ref() {
            self.more = Some(row.more.clone());
            out.push(("more", json!(row.more)));
        }
        if let Some(palette) = &row.palette
            && !palette.is_empty()
            && Some(palette) != self.palette.as_ref()
        {
            self.palette = Some(palette.clone());
            out.push(("palette", json!(palette)));
        }
        self.line(&out)
    }
}
