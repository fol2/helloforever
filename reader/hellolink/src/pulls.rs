//! `--pulls DIR`: a record of each pull, one JSON line a pull (docs/PULLS.md, #361). Built from the
//! reader's own events: the fast block and the level squares of each `state`, and objects 10 and 24.
//! `Pulls` does no I/O and reads no clock: events and their Unix time in, finished lines out;
//! `append` writes a line.

use serde_json::{Value, json};
use std::fs::{self, OpenOptions};
use std::io::{self, Write};
use std::path::{Path, PathBuf};

/// The format's version (docs/PULLS.md).
pub const VERSION: u32 = 1;
/// Samples come at most this often, in tenths of a second: 5 a second.
const SAMPLE_EVERY: i64 = 2;
/// No `state` for longer than this inside a pull is a gap (the fast state's own limit, KEY_OLD).
const GAP: f64 = 1.5;
/// No `state` for longer than this ends the open pull unseen: its end is not known.
const LOST: f64 = 120.0;
/// The in-combat bit of the fast block's state flags (docs/STRIP.md, section 5).
const IN_COMBAT: i64 = 128;
/// Object 24's unit flags (docs/specs/213.md): dead, in combat, can attack.
const DEAD: i64 = 1;
const FIGHTING: i64 = 2;
const HOSTILE: i64 = 4;

/// Tenths of a second from `t0`.
fn tenths(t0: f64, at: f64) -> i64 {
    ((at - t0) * 10.0).round() as i64
}

/// Unix seconds to two decimals.
fn hundredths(t: f64) -> Value {
    json!((t * 100.0).round() / 100.0)
}

/// A level square's value: the reader gives it as a per cent already (docs/STRIP.md, section 4;
/// the `levels` event of section 10), `null` when unknown.
fn per_cent(level: &Value) -> Value {
    level.as_i64().map_or(Value::Null, |l| json!(l))
}

/// Appends `v` to the list when it differs from the last value there: a list of changes.
fn change(list: &mut Vec<Value>, dt: i64, v: Value) {
    if list.last().is_none_or(|last| last[1] != v) {
        list.push(json!([dt, v]));
    }
}

struct Unit {
    key: String,
    id: Value,
    g: Value,
    level: Value,
    class: Value,
    seen: i64,
    last: i64,
    dead: Option<i64>,
    threat: Vec<Value>,
    threat_pet: Vec<Value>,
    target: Vec<Value>,
}

struct Pull {
    t0: f64,
    samples: Vec<Value>,
    sampled: Option<i64>,
    units: Vec<Unit>,
    near: Vec<Value>,
    gaps: Vec<Value>,
    clash: bool,
}

/// Follows the events and gives a line when a pull ends.
pub struct Pulls {
    reader: String,
    open: Option<Pull>,
    /// The last level squares, as names to 0..127 (a `levels` event comes without a new `state`).
    levels: Value,
    /// Object 10's `guid`: whose pull.
    character: Value,
    /// When the last `state` came.
    last_state: Option<f64>,
}

impl Pulls {
    /// `reader` names this build in each line (`install::BUILT_FROM`).
    pub fn new(reader: &str) -> Pulls {
        Pulls {
            reader: reader.into(),
            open: None,
            levels: Value::Null,
            character: Value::Null,
            last_state: None,
        }
    }

    /// Takes one event at Unix time `at`; the line of the pull it ends, if any: a pull whose
    /// in-combat flag went off, or one lost after a silence of LOST (its end unseen).
    pub fn take(&mut self, event: &Value, at: f64) -> Option<Value> {
        let mut done = None;
        match event["kind"].as_str() {
            Some("state") => {
                if let (Some(last), Some(_)) = (self.last_state, &self.open)
                    && at - last > LOST
                {
                    done = self.close(None);
                }
                if let (Some(last), Some(pull)) = (self.last_state, &mut self.open)
                    && at - last > GAP
                {
                    pull.gaps
                        .push(json!([tenths(pull.t0, last), tenths(pull.t0, at)]));
                }
                self.last_state = Some(at);
                if event["levels"].is_object() {
                    self.levels = event["levels"].clone();
                }
                let fast = &event["fast"];
                let flags = fast["state"]["flags"].as_i64();
                match (flags.map(|f| f & IN_COMBAT != 0), self.open.is_some()) {
                    (Some(true), false) => {
                        self.open = Some(Pull {
                            t0: at,
                            samples: vec![],
                            sampled: None,
                            units: vec![],
                            near: vec![],
                            gaps: vec![],
                            clash: false,
                        })
                    }
                    (Some(false), true) => return self.close(Some(at)),
                    _ => {}
                }
                if let Some(pull) = &mut self.open {
                    let dt = tenths(pull.t0, at);
                    if pull.sampled.is_none_or(|s| dt - s >= SAMPLE_EVERY) {
                        pull.sampled = Some(dt);
                        let p = &fast["position"];
                        let l = &self.levels;
                        pull.samples.push(json!([
                            dt,
                            p["map"],
                            p["x"],
                            p["y"],
                            p["facing"],
                            flags,
                            per_cent(&l["health"]),
                            per_cent(&l["power"]),
                            per_cent(&l["petHealth"]),
                            per_cent(&l["targetHealth"]),
                            fast["threat"]["player"],
                            fast["threat"]["pet"],
                            fast["cast"]["spell"],
                        ]));
                    }
                }
            }
            Some("levels") => self.levels = event["levels"].clone(),
            Some("object") if event["format"] != 253 && event["format"] != 255 => {
                let text = &event["text"];
                let parsed: Option<Value> = match text {
                    Value::String(s) => serde_json::from_str(s).ok(),
                    v => Some(v.clone()),
                };
                match (event["id"].as_u64(), parsed) {
                    (Some(10), Some(who)) => self.character = who["guid"].clone(),
                    (Some(24), Some(units)) => {
                        if let Some(pull) = &mut self.open {
                            pull.plates(&units["nameplates"], at);
                        }
                    }
                    _ => {}
                }
            }
            _ => {}
        }
        done
    }

    /// The open pull's line when the reader stops: its end was not seen.
    pub fn end(&mut self) -> Option<Value> {
        self.close(None)
    }

    fn close(&mut self, t1: Option<f64>) -> Option<Value> {
        let pull = self.open.take()?;
        let units: Vec<Value> = pull
            .units
            .iter()
            .enumerate()
            .map(|(i, u)| {
                json!({"i": i + 1, "id": u.id, "g": u.g, "lvl": u.level, "cls": u.class,
                    "seen": u.seen, "last": u.last, "dead": u.dead, "thr": u.threat,
                    "thrPet": u.threat_pet, "tgt": u.target})
            })
            .collect();
        Some(json!({
            "v": VERSION, "reader": self.reader, "char": self.character,
            "t0": hundredths(pull.t0), "t1": t1.map_or(Value::Null, hundredths),
            "samples": pull.samples, "units": units, "near": pull.near, "gaps": pull.gaps,
            "gclash": pull.clash,
        }))
    }
}

impl Pull {
    /// Object 24's nameplates at `at`: each `[who, level, class, classification, flags, target,
    /// threat, mark, cast]` (docs/specs/213.md), with `g` (10th) and the pet's threat (11th) when a
    /// later HelloLink sends them.
    fn plates(&mut self, plates: &Value, at: f64) {
        let dt = tenths(self.t0, at);
        let mut near = 0;
        let mut keys: Vec<String> = vec![];
        for p in plates.as_array().into_iter().flatten() {
            let flags = p[4].as_i64().unwrap_or(0);
            if flags & HOSTILE == 0 {
                continue;
            }
            if flags & FIGHTING == 0 && flags & DEAD == 0 {
                near += 1;
            }
            let who = p[0].as_str().unwrap_or("");
            let g = p.get(9).cloned().unwrap_or(Value::Null);
            // the key: the reference and g; with no g, the reference and its place among the
            // plates of that reference (the client's order, which may change: gclash)
            let base = format!("{who}|{g}");
            let nth = keys
                .iter()
                .filter(|k| k.starts_with(&format!("{base}#")))
                .count();
            let key = format!("{base}#{nth}");
            keys.push(key.clone());
            let known = self.units.iter().position(|u| u.key == key);
            if flags & FIGHTING == 0 && known.is_none() {
                continue; // not in this fight (yet)
            }
            if nth > 0 {
                self.clash = true; // two plates this reader cannot tell apart
            }
            let i = known.unwrap_or_else(|| {
                let id = who
                    .strip_prefix("C:")
                    .and_then(|r| r.split(':').next())
                    .and_then(|id| id.parse::<i64>().ok());
                self.units.push(Unit {
                    key: key.clone(),
                    id: json!(id),
                    g: g.clone(),
                    level: p[1].clone(),
                    class: p[3].clone(),
                    seen: dt,
                    last: dt,
                    dead: None,
                    threat: vec![],
                    threat_pet: vec![],
                    target: vec![],
                });
                self.units.len() - 1
            });
            let u = &mut self.units[i];
            u.last = dt;
            if flags & DEAD != 0 && u.dead.is_none() {
                u.dead = Some(dt);
            }
            change(&mut u.threat, dt, p[6].clone());
            if let Some(t) = p.get(10) {
                change(&mut u.threat_pet, dt, t.clone());
            }
            let target = match p[5].as_str() {
                None => Value::Null,
                Some(t @ ("player" | "pet")) => json!(t),
                Some(_) => json!("other"),
            };
            change(&mut u.target, dt, target);
        }
        if self.near.last().is_none_or(|last| last[1] != near) {
            self.near.push(json!([dt, near]));
        }
    }
}

/// The file of a pull that began at Unix time `t0`: `<dir>/<local date>.jsonl`.
pub fn file_for(dir: &Path, t0: f64) -> PathBuf {
    use chrono::TimeZone;
    let day = chrono::Local
        .timestamp_opt(t0.floor() as i64, 0)
        .single()
        .map_or("unknown-day".to_string(), |d| {
            d.format("%Y-%m-%d").to_string()
        });
    dir.join(format!("{day}.jsonl"))
}

/// Appends one line to its day's file, creating the folder.
pub fn append(dir: &Path, line: &Value) -> io::Result<PathBuf> {
    fs::create_dir_all(dir)?;
    let path = file_for(dir, line["t0"].as_f64().unwrap_or(0.0));
    let mut f = OpenOptions::new().create(true).append(true).open(&path)?;
    let mut text = serde_json::to_string(line).map_err(io::Error::other)?;
    text.push('\n');
    f.write_all(text.as_bytes())?;
    f.flush()?;
    Ok(path)
}

/// The pulls of `hellolink replay`'s events: a `record` header (`started`, Unix time) and events
/// with `t`, seconds from the run's first capture. The first capture may come long after
/// `started` (a reader waits while the game is closed), so the run's offset is set by the first
/// `state`'s clock (the client's `time()` modulo 65536): within a second of the true time.
pub fn from_replay(events: &[u8], reader: &str) -> Result<Vec<Value>, String> {
    let mut pulls = Pulls::new(reader);
    let (mut started, mut offset): (Option<f64>, Option<f64>) = (None, None);
    let mut out = vec![];
    for (n, line) in events.split(|&b| b == b'\n').enumerate() {
        if line.iter().all(u8::is_ascii_whitespace) {
            continue;
        }
        let e: Value = serde_json::from_slice(line).map_err(|e| format!("event {}: {e}", n + 1))?;
        if e["kind"] == "record" {
            out.extend(pulls.end());
            pulls = Pulls::new(reader);
            (started, offset) = (e["started"].as_f64(), None);
            continue;
        }
        let (Some(s), Some(t)) = (started, e["t"].as_f64()) else {
            continue;
        };
        let guess = s + t;
        if offset.is_none()
            && let Some(clock) = e["fast"]["clock"]["clock"].as_f64()
        {
            // the whole second k with k = clock (mod 65536) nearest the guess
            let k = clock + 65536.0 * ((guess - clock) / 65536.0).round();
            offset = Some(if (0.0..1.0).contains(&(guess - k)) {
                0.0
            } else {
                k + 0.5 - guess
            });
        }
        // events before the first clock are not timed: a pull needs a state, which has one
        if let Some(o) = offset {
            out.extend(pulls.take(&e, guess + o));
        }
    }
    out.extend(pulls.end());
    Ok(out)
}
