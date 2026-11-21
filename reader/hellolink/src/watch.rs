//! Section 8, a reader that follows the row: `Quality` and `Watcher` of tools/strip1.py.
//! No I/O, no clock: values in, events out.

use crate::bitmap::Bitmap;
use crate::rows::fast_json;
use crate::strip1::{Assembler, LEVEL_NAMES, MAX_CHUNKS, NEAR, OBJECT_IDS, Row, read_row};
use crate::strip2::{Joiner, Keys};
use serde_json::{Value, json};
use std::collections::BTreeSet;

/// An event: a JSON object with a `kind`, as the Python Watcher's dicts.
pub type Event = Value;

/// Section 3, "Falling back": when a reader asks the addon for depth 2.
#[derive(Default)]
pub struct Quality {
    /// The last 200 depth-4 frames: true for one that passed, false for one that did not.
    recent: Vec<bool>,
    /// A depth-4 frame was read at least once.
    ever: bool,
}

impl Quality {
    /// Takes what read_row returned; true when the reader should ask for depth 2.
    pub fn note(&mut self, row: &Row) -> bool {
        if row.depth != Some(4) {
            return false;
        }
        let ok = row.frame.is_some();
        self.ever |= ok;
        self.recent.push(ok);
        if self.recent.len() > 200 {
            self.recent.remove(0);
        }
        if row.apart.is_some_and(|a| a < NEAR) {
            return true;
        }
        let full = self.recent.len() >= 200;
        if !self.ever {
            return full;
        }
        full && self.recent.iter().filter(|ok| !**ok).count() > 4
    }
}

pub const RELOCATE_AFTER: u32 = 2;
pub const LOST_AFTER: u32 = 30;
pub const STALE_AFTER: f64 = 3.0;
/// Format 2: the fast state is old when its keyframe came more than this long ago.
pub const KEY_OLD: f64 = 1.5;

fn levels_json(levels: &[Option<i64>; 4]) -> Value {
    Value::Object(
        LEVEL_NAMES
            .iter()
            .zip(levels)
            .map(|(name, v)| (name.to_string(), json!(v)))
            .collect(),
    )
}

/// Takes captures of the row's place one after the other and says what is new. `feed` takes
/// a bitmap and the time, `idle` only the time (call it when no capture came, so that
/// staleness is noticed without one). One Watcher lives as long as the reader: it keeps what
/// it knows of a session when the row has to be looked for again.
///
/// `feed` and `idle` return events, each with a `kind`:
///   `state`    a new `seq`: session, seq, depth, levels and the fast block
///   `levels`   the level squares changed with no new `seq`
///   `object`   a new version of an object is whole: id, format, text
///   `ask`      the reader should ask the addon for depth 2 (once a session): session
///   `relocate` two captures in a row gave no frame: look for the row again (section 8)
///   `lost`     30 captures in a row gave no frame
///   `stale`    3 s passed with no new `seq`. With it, and every 3 s while it lasts, comes a
///              `relocate`: a row that moved away leaves a capture that never changes.
///   `stale-object`  an object was not seen whole for three rounds of the largest size: id
///   `fresh-object`  an object called stale was seen whole again in the same version: id
pub struct Watcher {
    pub joiner: Assembler,
    /// Format 2 (docs/specs/213.md): the kept keyframe, and objects joined from chunks that
    /// need not come in a row.
    keys: Keys,
    joiner2: Joiner,
    /// The row's format and depth, to drop the kept keyframe when either changes.
    shape: Option<(u8, Option<u8>)>,
    /// The format of the last row read: format 2 is old after 1.5 s (docs/specs/213.md, section 9).
    format: u8,
    quality: Quality,
    /// The grid of the last good read, tried first on the next capture.
    pub hint: Option<(f64, i64, f64)>,
    session: Option<u32>,
    seq: Option<u16>,
    levels: Option<[Option<i64>; 4]>,
    /// The session a fall-back was asked for.
    asked: Option<u32>,
    misses: u32,
    /// When the last new seq came.
    fresh_at: Option<f64>,
    stale: bool,
    dwell: u8,
    stale_objects: BTreeSet<(u8, u16)>,
    /// Format 3: held versions the directory named another version for (docs/specs/232.md, 4 A).
    dir_old: BTreeSet<(u8, u16)>,
    /// When a new search was last asked for because time passed.
    search_at: Option<f64>,
    /// When a frame last passed its check, or when the watch began.
    progress_at: Option<f64>,
    /// The last capture fed had a row, read or not.
    pub shown: bool,
}

impl Default for Watcher {
    fn default() -> Self {
        Watcher {
            joiner: Assembler::default(),
            keys: Keys::default(),
            joiner2: Joiner::default(),
            shape: None,
            format: 1,
            quality: Quality::default(),
            hint: None,
            session: None,
            seq: None,
            levels: None,
            asked: None,
            misses: 0,
            fresh_at: None,
            stale: false,
            dwell: 10,
            stale_objects: BTreeSet::new(),
            dir_old: BTreeSet::new(),
            search_at: None,
            progress_at: None,
            shown: false,
        }
    }
}

impl Watcher {
    /// What time alone makes old.
    pub fn idle(&mut self, now: f64) -> Vec<Event> {
        let mut events = vec![];
        let progress = *self.progress_at.get_or_insert(now);
        if let Some(fresh) = self.fresh_at
            && !self.stale
            && now - fresh
                > if self.format >= 2 {
                    KEY_OLD
                } else {
                    STALE_AFTER
                }
        {
            self.stale = true;
            events.push(json!({"kind": "stale", "session": self.session, "seq": self.seq}));
        }
        // A new search does not wait for a frame that was once good: a row found but never
        // decoded, which then moves away, leaves a capture that stands still too.
        // (Python's `fresh_at or progress_at`: a time of 0.0 counts as none.)
        let fresh = self.fresh_at.filter(|&f| f != 0.0).unwrap_or(progress);
        let since = if fresh > progress { fresh } else { progress };
        if now - since > STALE_AFTER && self.search_at.is_none_or(|s| now - s >= STALE_AFTER) {
            self.search_at = Some(now);
            self.hint = None;
            events.push(json!({"kind": "relocate", "why": "nothing new for 3 s"}));
        }
        let limit = (3 * OBJECT_IDS * MAX_CHUNKS as u32 * self.dwell as u32) as f64 / 100.0;
        let held = self
            .joiner
            .objects
            .iter()
            .map(|(&oid, &(version, _, _, seen))| (oid, version, seen));
        let held2 = self
            .joiner2
            .whole
            .iter()
            .map(|(&oid, &(version, seen))| (oid, version, seen));
        let held: Vec<_> = held.chain(held2).collect();
        for (oid, version, seen) in held {
            if now - seen > limit {
                if self.stale_objects.insert((oid, version)) {
                    events.push(json!({"kind": "stale-object", "id": oid}));
                }
            } else if !self.joiner2.secret.contains(&oid)
                && !self.dir_old.contains(&(oid, version))
                && self.stale_objects.remove(&(oid, version))
            {
                // seen whole again: no longer old
                events.push(json!({"kind": "fresh-object", "id": oid}));
            }
        }
        events
    }

    /// Reads a capture, trying the last good place first, and says what is new.
    pub fn feed(&mut self, bmp: &Bitmap, now: f64) -> Vec<Event> {
        self.feed_row(read_row(bmp, self.hint), now)
    }

    /// `feed` for a row already read with `read_row(bmp, watcher.hint)`: a reader that keeps
    /// a record of each row (the Python Watcher's `on_row`) reads it, notes it, then calls this.
    pub fn feed_row(&mut self, row: Option<Row>, now: f64) -> Vec<Event> {
        self.shown = row.as_ref().is_some_and(|r| r.grid.is_some());
        let mut events = vec![];
        if let Some(r) = &row
            && r.depth.is_some()
            && r.session != self.session
        {
            (self.session, self.seq, self.levels) = (r.session, None, None);
            self.quality = Quality::default();
            self.stale_objects.clear();
            self.dir_old.clear();
            self.keys.drop_key();
            self.joiner2 = Joiner::default();
        }
        if let Some(r) = &row
            && r.depth.is_some()
        {
            self.format = r.format;
        }
        if let Some(r) = &row
            && r.depth.is_some()
            && self
                .shape
                .replace((r.format, r.depth))
                .is_some_and(|s| s != (r.format, r.depth))
        {
            self.keys.drop_key();
        }
        if let Some(r) = &row
            && self.quality.note(r)
            && self.asked != r.session
        {
            self.asked = r.session;
            events.push(json!({"kind": "ask", "session": r.session}));
        }
        let Some((row, frame)) = row.as_ref().and_then(|r| r.frame.as_ref().map(|f| (r, f))) else {
            let why = row.as_ref().map_or(json!("no row"), |r| json!(r.why));
            return self.missed(why, now, events);
        };
        self.misses = 0;
        (self.hint, self.dwell, self.progress_at) = (row.grid, frame.dwell, Some(now));
        // Format 2: a delta's state needs its keyframe; without it the fast part is dropped
        // and no state is said (docs/specs/213.md, section 6).
        let fast = match frame.two {
            None => Some(frame.fast.clone()),
            Some(_) => self.keys.resolve(frame, now),
        };
        if Some(frame.seq) != self.seq
            && let Some(fast) = &fast
        {
            (self.seq, self.levels) = (Some(frame.seq), Some(row.levels));
            // format 2: fresh as its keyframe, not as the delta
            let fresh = if frame.two.is_some() {
                self.keys.key_at().unwrap_or(now)
            } else {
                now
            };
            (self.fresh_at, self.search_at) = (Some(fresh), None);
            if frame.two.is_none() || now - fresh <= KEY_OLD {
                self.stale = false;
            }
            let mut state = json!({"kind": "state", "session": row.session, "seq": frame.seq,
                "depth": row.depth, "levels": levels_json(&row.levels), "fast": fast_json(fast)});
            if row.format >= 2 {
                state["format"] = json!(row.format);
                state["more"] = json!(row.more);
                state["keyAge"] = json!(((now - fresh) * 100.0).round() / 100.0);
            }
            events.push(state);
        } else if Some(frame.seq) == self.seq && Some(row.levels) != self.levels {
            self.levels = Some(row.levels);
            events.push(json!({"kind": "levels", "levels": levels_json(&row.levels)}));
        }
        let done = match (&frame.two, &frame.chunk) {
            (None, _) => self.joiner.feed(frame, now),
            (Some(_), Some(c)) => self.joiner2.feed(c, now),
            (Some(_), None) => None,
        };
        // format 3: the directory names each object's newest version; a held one that differs is
        // old at once, not after three rounds (docs/specs/232.md, section 4 A)
        for &(oid, version) in frame.directory.iter().flatten() {
            if let Some(&(held, _)) = self.joiner2.whole.get(&oid)
                && held != version
                && self.dir_old.insert((oid, held))
            {
                self.stale_objects.insert((oid, held));
                events.push(json!({"kind": "stale-object", "id": oid}));
            }
        }
        if let Some((id, format, text)) = done {
            self.dir_old.retain(|&(o, _)| o != id);
            let mut object = json!({"kind": "object", "id": id, "format": format, "text": text});
            if frame.two.is_some() {
                object["session"] = json!(row.session); // format 2 (the API's objects of a session)
            }
            if format == 253 {
                object["secret"] = json!(true); // secret now: keep the last copy, marked old
            }
            events.push(object);
        }
        if let Some((id, version, why)) = self.joiner2.bad.take() {
            events.push(json!({"kind": "bad-object", "id": id, "version": version, "why": why}));
        }
        events.extend(self.idle(now));
        events
    }

    fn missed(&mut self, why: Value, now: f64, mut events: Vec<Event>) -> Vec<Event> {
        self.misses = self.misses.saturating_add(1);
        if self.misses == RELOCATE_AFTER {
            self.hint = None;
            events.push(json!({"kind": "relocate", "why": why}));
        }
        if self.misses == LOST_AFTER {
            events.push(json!({"kind": "lost", "why": why}));
        }
        events.extend(self.idle(now));
        events
    }
}
