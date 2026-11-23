//! The addon's saved data file, read for the character's history (docs/specs/331.md): the Lua
//! the client writes, the fight log's blobs, and the usual time of a fight against one enemy at
//! one player level, by the addon's own rule (HelloForever/Fights.lua, `baselineOf`).

use miniz_oxide::inflate::stream::{InflateState, inflate};
use miniz_oxide::{DataFormat, MZFlush, MZStatus};
use serde_json::{Map, Value, json};
use std::collections::BTreeMap;

/// The Lua values the client writes (section 2): no functions, no identifier keys.
enum Lua {
    Nil,
    Bool, // no use reads its value
    Num(f64),
    Str(Vec<u8>),
    Table(Vec<(Lua, Lua)>),
}

impl Lua {
    fn get(&self, key: &str) -> Option<&Lua> {
        match self {
            Lua::Table(t) => t.iter().find_map(|(k, v)| match k {
                Lua::Str(s) if s == key.as_bytes() => Some(v),
                _ => None,
            }),
            _ => None,
        }
    }
    /// The values of a list, 1 to n with no gap and no other key; None for anything else, so
    /// a gap cannot hide the values after it (review of #331).
    fn list(&self) -> Option<Vec<&Lua>> {
        let Lua::Table(t) = self else { return None };
        let mut out: Vec<Option<&Lua>> = vec![None; t.len()];
        for (k, v) in t {
            let Lua::Num(n) = k else { return None };
            let i = *n as usize;
            if *n != i as f64 || i == 0 || i > t.len() || out[i - 1].is_some() {
                return None;
            }
            out[i - 1] = Some(v);
        }
        out.into_iter().collect()
    }
    fn text(&self) -> Option<String> {
        match self {
            Lua::Str(s) => Some(String::from_utf8_lossy(s).into_owned()),
            _ => None,
        }
    }
    fn num(&self) -> Option<f64> {
        match self {
            Lua::Num(n) => Some(*n),
            _ => None,
        }
    }
}

struct Parser<'a> {
    b: &'a [u8],
    i: usize,
}

impl Parser<'_> {
    fn at(&self, what: &str) -> String {
        let before = &self.b[..self.i.min(self.b.len())];
        let line = before.iter().filter(|&&c| c == b'\n').count() + 1;
        let col = self.i
            - before
                .iter()
                .rposition(|&c| c == b'\n')
                .map_or(0, |p| p + 1)
            + 1;
        format!("line {line}, column {col}: {what}")
    }
    fn short(&self) -> String {
        "the file is cut short (it ends inside a value)".into()
    }
    fn skip(&mut self) {
        loop {
            while self.i < self.b.len() && self.b[self.i].is_ascii_whitespace() {
                self.i += 1;
            }
            if self.b[self.i..].starts_with(b"--") {
                while self.i < self.b.len() && self.b[self.i] != b'\n' {
                    self.i += 1;
                }
            } else {
                return;
            }
        }
    }
    fn peek(&mut self) -> Result<u8, String> {
        self.skip();
        self.b.get(self.i).copied().ok_or_else(|| self.short())
    }
    fn expect(&mut self, c: u8) -> Result<(), String> {
        if self.peek()? != c {
            return Err(self.at(&format!("'{}' expected", c as char)));
        }
        self.i += 1;
        Ok(())
    }
    fn word(&mut self) -> &[u8] {
        let s = self.i;
        while self.i < self.b.len()
            && (self.b[self.i].is_ascii_alphanumeric() || self.b[self.i] == b'_')
        {
            self.i += 1;
        }
        &self.b[s..self.i]
    }
    fn value(&mut self) -> Result<Lua, String> {
        match self.peek()? {
            b'{' => {
                self.i += 1;
                let mut t = vec![];
                let mut n = 0.0;
                loop {
                    if self.peek()? == b'}' {
                        self.i += 1;
                        return Ok(Lua::Table(t));
                    }
                    if self.peek()? == b'[' {
                        self.i += 1;
                        let k = self.value()?;
                        self.expect(b']')?;
                        self.expect(b'=')?;
                        t.push((k, self.value()?));
                    } else {
                        n += 1.0;
                        t.push((Lua::Num(n), self.value()?));
                    }
                    match self.peek()? {
                        b',' | b';' => self.i += 1,
                        b'}' => {}
                        _ => return Err(self.at("',' or '}' expected")),
                    }
                }
            }
            b'"' => self.string(),
            b'-' | b'.' | b'0'..=b'9' => self.number(),
            _ => {
                let s = self.i;
                match self.word() {
                    b"true" | b"false" => Ok(Lua::Bool),
                    b"nil" => Ok(Lua::Nil),
                    _ => {
                        self.i = s;
                        Err(self.at("a value the client's saved data does not write"))
                    }
                }
            }
        }
    }
    fn number(&mut self) -> Result<Lua, String> {
        let s = self.i;
        if self.b[self.i] == b'-' {
            self.i += 1;
        }
        let digits = |p: &mut Self| {
            let d = p.i;
            while p.i < p.b.len() && p.b[p.i].is_ascii_digit() {
                p.i += 1;
            }
            p.i - d
        };
        let mut n = digits(self);
        if self.b.get(self.i) == Some(&b'.') {
            self.i += 1;
            n += digits(self);
        }
        if n > 0 && matches!(self.b.get(self.i), Some(b'e' | b'E')) {
            self.i += 1;
            if matches!(self.b.get(self.i), Some(b'+' | b'-')) {
                self.i += 1;
            }
            n = digits(self);
        }
        let end = self.i;
        if n == 0
            || self
                .b
                .get(self.i)
                .is_some_and(|c| c.is_ascii_alphanumeric() || *c == b'.')
        {
            self.i = s;
            return Err(self.at("a number the client's saved data does not write"));
        }
        let text = std::str::from_utf8(&self.b[s..end]).unwrap_or_default();
        match text.parse::<f64>() {
            Ok(v) if v.is_finite() => Ok(Lua::Num(v)),
            _ => {
                self.i = s;
                Err(self.at("a number that is not finite (an overflow)"))
            }
        }
    }
    fn string(&mut self) -> Result<Lua, String> {
        self.i += 1;
        let mut out = vec![];
        loop {
            let c = *self.b.get(self.i).ok_or_else(|| self.short())?;
            self.i += 1;
            match c {
                b'"' => return Ok(Lua::Str(out)),
                b'\n' | b'\r' => return Err(self.at("a line end inside a string")),
                b'\\' => {
                    let e = *self.b.get(self.i).ok_or_else(|| self.short())?;
                    self.i += 1;
                    out.push(match e {
                        b'n' => b'\n',
                        b't' => b'\t',
                        b'r' => b'\r',
                        b'a' => 7,
                        b'b' => 8,
                        b'f' => 12,
                        b'v' => 11,
                        b'\r' => {
                            if self.b.get(self.i) == Some(&b'\n') {
                                self.i += 1;
                            }
                            b'\n'
                        }
                        b'0'..=b'9' => {
                            let mut v = u32::from(e - b'0');
                            for _ in 0..2 {
                                match self.b.get(self.i) {
                                    Some(d) if d.is_ascii_digit() => {
                                        v = v * 10 + u32::from(d - b'0');
                                        self.i += 1;
                                    }
                                    _ => break,
                                }
                            }
                            u8::try_from(v).map_err(|_| self.at("an escape above 255"))?
                        }
                        // as Lua 5.1's lexer: any other escaped character is itself (\\ \" \' \q)
                        _ => e,
                    });
                }
                _ => out.push(c),
            }
        }
    }
    /// `name = value` statements; the value of `HelloForeverDB`.
    fn file(&mut self) -> Result<Lua, String> {
        let mut db = None;
        loop {
            self.skip();
            if self.i >= self.b.len() {
                return db.ok_or_else(|| "no HelloForeverDB in the file".into());
            }
            let name = self.word().to_vec();
            if name.is_empty() {
                return Err(self.at("a name expected"));
            }
            self.expect(b'=')?;
            let v = self.value()?;
            if name == b"HelloForeverDB" {
                db = Some(v);
            }
        }
    }
}

/// Standard Base64 with `=` padding, strictly (RFC 4648, section 3.5: padding bits are zero).
fn base64(text: &str) -> Option<Vec<u8>> {
    let b = text.as_bytes();
    if !b.len().is_multiple_of(4) {
        return None;
    }
    let val = |c: u8| match c {
        b'A'..=b'Z' => Some(c - b'A'),
        b'a'..=b'z' => Some(c - b'a' + 26),
        b'0'..=b'9' => Some(c - b'0' + 52),
        b'+' => Some(62),
        b'/' => Some(63),
        _ => None,
    };
    let mut out = vec![];
    for (n, q) in b.chunks(4).enumerate() {
        let pad = q.iter().rev().take_while(|&&c| c == b'=').count();
        if pad > 2 || (pad > 0 && n + 1 != b.len() / 4) {
            return None;
        }
        let mut v = 0u32;
        for &c in &q[..4 - pad] {
            v = v << 6 | u32::from(val(c)?);
        }
        if v & ((1 << (2 * pad)) - 1) != 0 {
            return None; // padding bits that are not zero
        }
        v <<= 6 * pad as u32;
        out.extend_from_slice(&v.to_be_bytes()[1..4 - pad]);
    }
    Some(out)
}

/// Raw Deflate that ends, with no byte after its end.
fn inflate_all(raw: &[u8]) -> Result<Vec<u8>, String> {
    let mut st = InflateState::new_boxed(DataFormat::Raw);
    let mut out = vec![0; raw.len() * 4 + 64];
    let (mut used, mut made) = (0, 0);
    loop {
        if made == out.len() {
            out.resize(out.len() * 2, 0);
        }
        let r = inflate(&mut st, &raw[used..], &mut out[made..], MZFlush::None);
        used += r.bytes_consumed;
        made += r.bytes_written;
        match r.status {
            Ok(MZStatus::StreamEnd) if used == raw.len() => {
                out.truncate(made);
                return Ok(out);
            }
            Ok(MZStatus::StreamEnd) => {
                return Err("bytes after the end of the Deflate stream".into());
            }
            Ok(_) if r.bytes_consumed == 0 && r.bytes_written == 0 && made < out.len() => {
                return Err("the Deflate stream does not end".into());
            }
            Ok(_) => {}
            Err(_) if used == raw.len() => return Err("the Deflate stream does not end".into()),
            Err(e) => return Err(format!("Deflate: {e:?}")),
        }
    }
}

/// A fight blob as JSON (docs/SCHEMA.md, "Integrity rules for importers").
fn blob(text: &str) -> Result<Value, String> {
    let json = if let Some(b) = text.strip_prefix("d1:") {
        inflate_all(&base64(b).ok_or("not Base64")?)?
    } else if let Some(j) = text.strip_prefix("j1:") {
        j.as_bytes().to_vec()
    } else {
        return Err(format!(
            "the prefix of {:?} is not d1: or j1:",
            text.get(..3).unwrap_or(text)
        ));
    };
    serde_json::from_slice(&json).map_err(|e| format!("JSON: {e}"))
}

/// The start, session id and seq in a fight's key (HelloForever/Core.lua, `ParseFightKey`);
/// zeros when the key is none of its forms, as the addon's `keyStart`.
fn key_start(key: &str) -> (i64, i64, i64) {
    let parts: Vec<&str> = key.split('-').collect();
    let num = |s: &str| {
        (!s.is_empty() && s.bytes().all(|c| c.is_ascii_digit()))
            .then(|| s.parse().ok())
            .flatten()
    };
    let hex = |s: &str| s.len() == 8 && s.bytes().all(|c| matches!(c, b'0'..=b'9' | b'a'..=b'f'));
    let got = match parts.as_slice() {
        ["hf1", i, a, b, c] if hex(i) => (num(a), num(b), num(c)),
        [a, b, c] => (num(a), num(b), num(c)),
        [a, b] => (num(a), num(b), Some(1)),
        _ => (None, None, None),
    };
    match got {
        (Some(a), Some(b), Some(c)) => (a, b, c),
        _ => (0, 0, 0),
    }
}

/// Lua's `tostring` of a number, as the addon's baseline key has it.
fn lua_num(n: f64) -> String {
    if n.fract() == 0.0 && n.abs() < 1e15 {
        format!("{}", n as i64)
    } else {
        format!("{n}")
    }
}

/// Lua's truth of a decoded JSON value: anything but null (nil) and false.
fn truthy(v: Option<&Value>) -> Option<&Value> {
    v.filter(|v| !v.is_null() && **v != Value::Bool(false))
}

/// What a fight counts as: (the baseline key, the enemy's name, its time).
type Counts = (String, String, Option<f64>);

/// What a fight counts as; None when it does not count (`baselineOf`, docs/SCHEMA.md "Which
/// fights count").
fn counts(rec: &Value) -> Option<Counts> {
    let p = rec.get("pull").filter(|p| p.is_object())?;
    if truthy(p.get("approx")).is_some() {
        return None;
    }
    let lvl = p
        .get("start")
        .filter(|s| s.is_object())?
        .get("level")?
        .as_f64()?;
    // `p.stop.level or nil`: a false level is no level, as nil
    let stop = truthy(
        p.get("stop")
            .filter(|s| s.is_object())
            .and_then(|s| s.get("level")),
    );
    match stop {
        Some(s) if s.as_f64() != Some(lvl) => return None,
        None if rec.get("lvl").and_then(Value::as_f64) != Some(lvl) => return None,
        _ => {}
    }
    let list = rec
        .get("types")?
        .get("EnemyDamageTaken")?
        .get("combatSources")?
        .as_array()?;
    let [row] = list.as_slice() else { return None };
    let id = row.as_object()?.get("sourceCreatureID")?.as_f64()?;
    if id <= 0.0 {
        return None;
    }
    let dur = rec
        .get("dur")
        .and_then(Value::as_f64)
        .filter(|d| d.is_finite() && *d > 0.0);
    // a name that is not text falls back to the record's
    let name = row
        .get("name")
        .and_then(Value::as_str)
        .or_else(|| rec.get("name").and_then(Value::as_str));
    Some((
        format!("{}:{}", lua_num(id), lua_num(lvl)),
        name.unwrap_or_default().to_string(),
        dur,
    ))
}

/// A fight record as the log keeps it: its key, its revision, and what it counts as.
struct Rec {
    key: String,
    rev: f64,
    counts: Option<Counts>,
}

struct Char {
    guid: Option<String>,
    reset: Option<f64>,
    recs: Vec<Rec>,
}

/// Every character record of one saved data file, with its fight records.
pub struct History {
    chars: BTreeMap<String, Char>,
}

/// The addon's median of the known times, rounded as the strip rounds, when at least 3 know it.
fn usual(times: &mut [f64]) -> Option<i64> {
    if times.len() < 3 {
        return None;
    }
    times.sort_by(f64::total_cmp);
    let n = times.len();
    let m = if n % 2 == 1 {
        times[n / 2]
    } else {
        (times[n / 2 - 1] + times[n / 2]) / 2.0
    };
    Some((m + 0.5).floor() as i64)
}

/// The counted fights of some records: each fight once, by its highest revision (a later
/// record wins a tie), and none that started before the reset.
fn counted<'a>(
    recs: impl Iterator<Item = &'a Rec>,
    reset: Option<f64>,
) -> Vec<(&'a str, &'a Counts)> {
    let mut last: BTreeMap<&str, &Rec> = BTreeMap::new();
    for r in recs {
        if last.get(r.key.as_str()).is_none_or(|l| r.rev >= l.rev) {
            last.insert(&r.key, r);
        }
    }
    last.into_values()
        .filter(|r| reset.is_none_or(|t| key_start(&r.key).0 as f64 >= t))
        .filter_map(|r| Some((r.key.as_str(), r.counts.as_ref()?)))
        .collect()
}

impl History {
    /// The usual time of `<creatureId>:<level>` for one character, leaving out one fight:
    /// (whole seconds, how many known times). The character's records are those of its guid and
    /// those with no guid of its name; its reset is the latest of theirs (section 5).
    pub fn usual(
        &self,
        guid: Option<&str>,
        name: &str,
        bkey: &str,
        leave_out: &str,
    ) -> Option<(i64, usize)> {
        let mine: Vec<&Char> = self
            .chars
            .iter()
            .filter(|(k, c)| match &c.guid {
                Some(g) => Some(g.as_str()) == guid,
                None => k.rsplit_once('-').is_some_and(|(n, _)| n == name),
            })
            .map(|(_, c)| c)
            .collect();
        let reset = mine.iter().filter_map(|c| c.reset).reduce(f64::max);
        let mut times: Vec<f64> = counted(mine.iter().flat_map(|c| &c.recs), reset)
            .into_iter()
            .filter(|(key, (b, _, _))| b == bkey && *key != leave_out)
            .filter_map(|(_, (_, _, dur))| *dur)
            .collect();
        let n = times.len();
        usual(&mut times).map(|u| (u, n))
    }

    /// `hellolink history`: each character record's fights and, for each enemy, its usual time.
    pub fn summary(&self) -> Value {
        let mut out = Map::new();
        for (k, c) in &self.chars {
            let counted = counted(c.recs.iter(), c.reset);
            let mut keys: BTreeMap<&str, (&str, &str, Vec<f64>)> = BTreeMap::new();
            for (key, (b, name, dur)) in &counted {
                let e = keys.entry(b).or_insert((key, name, vec![]));
                if key_start(key) >= key_start(e.0) {
                    (e.0, e.1) = (key, name); // the name of the key's latest fight
                }
                e.2.extend(*dur);
            }
            let keys: Map<String, Value> = keys
                .into_iter()
                .map(|(b, (_, name, mut t))| {
                    let n = t.len();
                    (
                        b.to_string(),
                        json!({"name": name, "n": n, "usual": usual(&mut t)}),
                    )
                })
                .collect();
            out.insert(
                k.clone(),
                json!({"guid": c.guid, "fights": c.recs.len(), "counted": counted.len(), "keys": keys}),
            );
        }
        Value::Object(out)
    }
}

/// Reads a saved data file whole; any part it cannot read is an error with its place.
pub fn read_bytes(b: &[u8]) -> Result<History, String> {
    let db = Parser { b, i: 0 }.file()?;
    let mut chars = BTreeMap::new();
    let Some(Lua::Table(list)) = db.get("characters") else {
        return Ok(History { chars });
    };
    for (ck, c) in list {
        let Some(name) = ck.text() else { continue };
        let mut ch = Char {
            guid: c.get("guid").and_then(Lua::text),
            reset: c.get("baselineResetAt").and_then(Lua::num),
            recs: vec![],
        };
        let mut days: Vec<(String, &Lua)> = match c.get("fightLog").and_then(|f| f.get("days")) {
            Some(Lua::Table(d)) => d.iter().filter_map(|(k, v)| Some((k.text()?, v))).collect(),
            _ => vec![],
        };
        days.sort_by(|a, b| a.0.cmp(&b.0));
        for (day, bucket) in days {
            let list = |k: &str| {
                bucket
                    .get(k)
                    .map_or(Some(vec![]), Lua::list)
                    .ok_or_else(|| format!("{name} {day}: `{k}` is not a list 1 to n"))
            };
            let (keys, data) = (list("keys")?, list("data")?);
            if keys.len() != data.len() {
                return Err(format!(
                    "{name} {day}: {} keys but {} blobs",
                    keys.len(),
                    data.len()
                ));
            }
            for (k, d) in keys.into_iter().zip(data) {
                let key = k
                    .text()
                    .ok_or_else(|| format!("{name} {day}: a key that is not text"))?;
                let place = format!("{name} {day} {key}");
                let rec = blob(
                    &d.text()
                        .ok_or_else(|| format!("{place}: a blob that is not text"))?,
                )
                .map_err(|e| format!("{place}: {e}"))?;
                if rec.get("key").and_then(Value::as_str) != Some(key.as_str()) {
                    return Err(format!("{place}: the record is filed under another key"));
                }
                let rev = rec.get("rev").and_then(Value::as_f64).unwrap_or(1.0);
                ch.recs.push(Rec {
                    counts: counts(&rec),
                    key,
                    rev,
                });
            }
        }
        chars.insert(name, ch);
    }
    Ok(History { chars })
}

pub fn read_str(text: &str) -> Result<History, String> {
    read_bytes(text.as_bytes())
}

pub fn read(path: &std::path::Path) -> Result<History, String> {
    let b = std::fs::read(path).map_err(|e| format!("{}: {e}", path.display()))?;
    read_bytes(&b).map_err(|e| format!("{}: {e}", path.display()))
}
