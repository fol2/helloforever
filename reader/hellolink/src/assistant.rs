//! The assistant program, as tools/assistant.py (docs/specs/115.md, section 7; the spec calls
//! it the companion): it reads the reader's local API and answers the player's questions with
//! cards, written into the slot files that HelloLink reads (section 6).
//!
//! It listens to the reader's /events (the present first, then every event); it starts no
//! capture of its own, keeps no state on disk and takes no screenshot. It writes the
//! assistant's part of the slot files at least once a minute, and at once when it answers. It
//! reads only the reader's API and writes only slot files: it presses no key and touches no
//! window.
//!
//! A question is object 13's `ask` (`{"n", "topic", "t"}`) whose `n` is not yet answered and
//! whose `t` is no more than 60 s ago. The one topic is `session`: since the program began to
//! follow this UI session, the counted fights and deaths (object 12), the XP an hour and the
//! money gained (the fast block), and the enemy that took longest against its usual time.

use crate::history::History;
use crate::rows::dumps_ascii;
use crate::slots;
use serde_json::{Map, Value, json};
use std::io::Read;
use std::io::{self, BufRead, BufReader, Write};
use std::net::{TcpStream, ToSocketAddrs};
use std::path::Path;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

/// Seconds: a set at least this often, so the game knows the program is alive.
pub const HEARTBEAT: f64 = 60.0;
/// Seconds between tries when the reader cannot be reached or closed the stream.
pub const RETRY: f64 = 5.0;
/// Seconds: an older question is not answered (the bar said "no answer").
pub const ANSWER_WITHIN: f64 = 60.0;
/// Seconds an answer stays on the bar.
pub const CARD_TTL: i64 = 600;
/// Seconds of a quiet stream before a turn without an event (so the heartbeat still runs).
const QUIET: f64 = 20.0;

struct Text {
    session: &'static str,
    fights: [&'static str; 2],
    deaths: [&'static str; 2],
    xp: &'static str,
    money: &'static str,
    slow: &'static str,
    basis: &'static str,
    /// After `basis` when the slowest enemy's usual time is the saved history's (docs/specs/331.md).
    saved: &'static str,
}

const EN: Text = Text {
    session: "This session: {fights}, {deaths}{xp}{money}",
    fights: ["{n} fight", "{n} fights"],
    deaths: ["{n} death", "{n} deaths"],
    xp: ", {n} XP an hour",
    money: ", {m}",
    slow: "Slowest against usual: {name} {this} s, usual {usual} s",
    basis: "the strip since {hm}",
    saved: " and {n} saved fights",
};

const YUE: Text = Text {
    session: "今次：{fights}，{deaths}{xp}{money}",
    fights: ["{n} 場", "{n} 場"],
    deaths: ["死 {n} 次", "死 {n} 次"],
    xp: "，每個鐘 {n} XP",
    money: "，{m}",
    slow: "比平時慢得最多：{name} {this} 秒，平時 {usual} 秒",
    basis: "由 {hm} 起嘅 strip",
    saved: " 同 {n} 場存咗嘅戰鬥",
};

fn text(lang: &str) -> &'static Text {
    if lang == "yue" { &YUE } else { &EN }
}

/// `template` with each `{name}` replaced.
/// One pass over the template, as Python's str.format: a value is not read again, so a name
/// with `{this}` in it stays as it is.
fn fill(template: &str, values: &[(&str, &str)]) -> String {
    let mut out = String::new();
    let mut rest = template;
    while let Some(open) = rest.find('{') {
        out.push_str(&rest[..open]);
        let after = &rest[open + 1..];
        match after.find('}').and_then(|close| {
            let name = &after[..close];
            values
                .iter()
                .find(|(k, _)| *k == name)
                .map(|(_, v)| (close, *v))
        }) {
            Some((close, v)) => {
                out.push_str(v);
                rest = &after[close + 1..];
            }
            None => {
                out.push('{');
                rest = after;
            }
        }
    }
    out.push_str(rest);
    out
}

/// Copper as gold, silver and copper: "+1 g 12 s", "-1 g 23 s 45 c", "0 c".
pub fn money_text(copper: i64) -> String {
    let sign = match copper.signum() {
        1 => "+",
        -1 => "-",
        _ => "",
    };
    let c = copper.unsigned_abs();
    let parts = [
        (c >= 10000).then(|| format!("{} g", c / 10000)),
        (c >= 100).then(|| format!("{} s", c / 100 % 100)),
        (!c.is_multiple_of(100) || c == 0).then(|| format!("{} c", c % 100)),
    ];
    let parts: Vec<String> = parts.into_iter().flatten().collect();
    format!("{sign}{}", parts.join(" "))
}

/// 14571 as "14,571".
fn grouped(n: i64) -> String {
    let digits = n.unsigned_abs().to_string();
    let mut out = String::new();
    for (i, d) in digits.chars().enumerate() {
        if i > 0 && (digits.len() - i).is_multiple_of(3) {
            out.push(',');
        }
        out.push(d);
    }
    if n < 0 { format!("-{out}") } else { out }
}

/// A JSON whole number (Python's int, not float, not bool).
fn whole(v: Option<&Value>) -> Option<i64> {
    v.filter(|v| v.is_i64() || v.is_u64())
        .and_then(Value::as_i64)
}

/// The local time of day, "HH:MM", of a Unix time.
fn local_hm(t: f64) -> String {
    use chrono::TimeZone;
    match chrono::Local.timestamp_opt(t.floor() as i64, 0).earliest() {
        Some(at) => at.format("%H:%M").to_string(),
        None => "--:--".into(),
    }
}

/// A fight by its last revision: its key, died, the enemy and its baseline key (`<id>:<level>`),
/// this time and the strip's usual one.
#[derive(Clone)]
struct Fight {
    key: String,
    died: bool,
    name: String,
    bkey: Option<String>,
    this: Option<i64>,
    usual: Option<i64>,
}

/// What the program knows and when it writes. `feed` takes the reader's events; `due` gives
/// the set to write now (for slots::check_assist), or None.
pub struct Assistant {
    pub live: bool,
    session: Option<i64>,
    /// Object 13 read once: its `re` is known before the first write.
    seen13: bool,
    /// The last question answered (carried in every later set).
    re: Option<i64>,
    seq: i64,
    /// Cards given: event cards, until their ttl.
    cards: Vec<Value>,
    lang: String,
    /// Object 13's last question.
    ask: Option<Map<String, Value>>,
    last_write: Option<f64>,
    changed: bool,
    start: Option<f64>,
    xp_gained: i64,
    level: Option<(i64, i64, i64)>,
    money: Option<(i64, i64)>,
    /// Each fight's key and its last revision (None: it no longer counts), in the order seen.
    fights: Vec<(String, Option<Fight>)>,
    /// Seconds: a set at least this often (HEARTBEAT; a test gives less).
    pub heartbeat: f64,
    /// `--history`: the saved data, read once at start (docs/specs/331.md, section 5).
    pub history: Option<History>,
    /// Object 10's guid (null when it has none) and name: whose records of the history are this character's.
    who: Option<(Option<String>, String)>,
}

impl Default for Assistant {
    fn default() -> Assistant {
        Assistant {
            live: false,
            session: None,
            seen13: false,
            re: None,
            seq: 0,
            cards: vec![],
            lang: "en".into(),
            ask: None,
            last_write: None,
            changed: false,
            start: None,
            xp_gained: 0,
            level: None,
            money: None,
            fights: vec![],
            heartbeat: HEARTBEAT,
            history: None,
            who: None,
        }
    }
}

impl Assistant {
    fn reset(&mut self, now: Option<f64>) {
        self.start = now;
        self.xp_gained = 0;
        self.level = None;
        self.money = None;
        self.fights.clear();
        self.who = None;
    }

    /// Takes one event of the reader.
    pub fn feed(&mut self, e: &Value, now: f64) {
        match e.get("kind").and_then(Value::as_str).unwrap_or("") {
            "snapshot" => {
                self.live = e.get("condition").and_then(Value::as_str) == Some("live");
                if let Some(state) = e.get("state").filter(|s| s.is_object()) {
                    self.state(state, now);
                }
                // in the order of their ids as text, as Python's sorted()
                for (oid, o) in e
                    .get("objects")
                    .and_then(Value::as_object)
                    .into_iter()
                    .flatten()
                {
                    let Ok(oid) = oid.parse::<i64>() else {
                        continue;
                    };
                    if o.is_object() && !o.get("stale").is_some_and(truthy) {
                        self.object(Some(oid), o.get("text"));
                    }
                }
            }
            "state" => {
                self.live = true;
                self.state(e, now);
            }
            "object" => self.object(e.get("id").and_then(Value::as_i64), e.get("text")),
            "stale" | "lost" | "waiting" => self.live = false,
            _ => {}
        }
    }

    fn state(&mut self, e: &Value, now: f64) {
        if let Some(session) = whole(e.get("session"))
            && Some(session) != self.session
        {
            // A new UI session (a reload): its questions count from 1 again, and its object 13
            // must be read before the first write; the counts start again.
            self.session = Some(session);
            self.reset(Some(now));
            self.cards.clear();
            self.changed = true;
            (self.re, self.ask, self.seen13) = (None, None, false);
        }
        let fast = e.get("fast");
        let lv = fast.and_then(|f| f.get("level")).filter(|l| l.is_object());
        if let Some(lv) = lv
            && let (Some(level), Some(xp), Some(max)) = (
                whole(lv.get("level")),
                whole(lv.get("xp")),
                whole(lv.get("xpMax")),
            )
        {
            if let Some((old_level, old_xp, old_max)) = self.level {
                if level == old_level && xp >= old_xp {
                    self.xp_gained += xp - old_xp;
                } else if level == old_level + 1 {
                    // a level up: the rest of the old bar, then the new
                    self.xp_gained += (old_max - old_xp).max(0) + xp;
                }
            }
            self.level = Some((level, xp, max));
        }
        let purse = fast.and_then(|f| f.get("purse")).filter(|p| p.is_object());
        if let Some(money) = purse.and_then(|p| whole(p.get("money"))) {
            let first = self.money.map_or(money, |(first, _)| first);
            self.money = Some((first, money));
        }
    }

    fn object(&mut self, oid: Option<i64>, text: Option<&Value>) {
        let v = match text.and_then(Value::as_str) {
            Some(t) => match serde_json::from_str::<Value>(t) {
                Ok(v) => Some(v),
                Err(_) => return,
            },
            None => None,
        };
        let v = v.as_ref();
        match oid {
            Some(10) => {
                let text = |k| {
                    v.and_then(|v| v.get(k))
                        .and_then(Value::as_str)
                        .map(String::from)
                };
                self.who = text("name").map(|name| (text("guid"), name)); // a null guid still joins by name
            }
            Some(12) => {
                let Some(key) = v.and_then(|v| v.get("fight")).and_then(Value::as_str) else {
                    return;
                };
                let v = v.unwrap_or(&Value::Null);
                // Each fight by its last revision: a later one may add a death, or no longer count.
                let fight = if v.get("counted") != Some(&Value::Bool(true)) {
                    if !self.fights.iter().any(|(k, _)| k == key) {
                        return;
                    }
                    None
                } else {
                    let died = v
                        .get("died")
                        .and_then(Value::as_array)
                        .is_some_and(|d| d.first() == Some(&Value::Bool(true)));
                    let dur = v
                        .get("dur")
                        .and_then(Value::as_array)
                        .filter(|d| d.len() == 3);
                    let bkey = whole(v.get("id"))
                        .zip(whole(v.get("level")))
                        .map(|(id, level)| format!("{id}:{level}"));
                    Some(Fight {
                        key: key.to_string(),
                        died,
                        name: name_of(v.get("name")),
                        bkey,
                        this: dur.and_then(|d| whole(d.first())),
                        usual: dur.and_then(|d| whole(d.get(1))),
                    })
                };
                match self.fights.iter_mut().find(|(k, _)| k == key) {
                    Some((_, f)) => *f = fight,
                    None => self.fights.push((key.to_string(), fight)),
                }
            }
            Some(13) => {
                self.seen13 = true;
                let Some(v) = v.and_then(Value::as_object) else {
                    self.ask = None;
                    return;
                };
                if self.re.is_none() {
                    self.re = whole(v.get("re")); // started again: carry on the answered question
                }
                if let Some(seq) = whole(v.get("seq"))
                    && seq > self.seq
                {
                    self.seq = seq;
                }
                if let Some(lang @ ("en" | "yue")) = v.get("lang").and_then(Value::as_str) {
                    self.lang = lang.into();
                }
                self.ask = v
                    .get("ask")
                    .and_then(Value::as_object)
                    .filter(|a| whole(a.get("n")).is_some() && whole(a.get("t")).is_some())
                    .cloned();
            }
            _ => {}
        }
    }

    /// The answer to `session`.
    pub fn session_card(&self, now: f64) -> Value {
        let t = text(&self.lang);
        let counted: Vec<&Fight> = self.fights.iter().filter_map(|(_, f)| f.as_ref()).collect();
        let (n, dead) = (counted.len(), counted.iter().filter(|f| f.died).count());
        let fights = fill(t.fights[usize::from(n != 1)], &[("n", &n.to_string())]);
        let deaths = fill(
            t.deaths[usize::from(dead != 1)],
            &[("n", &dead.to_string())],
        );
        let xp = match self.start {
            Some(start) if now - start >= 60.0 => {
                let per_hour = (self.xp_gained as f64 * 3600.0 / (now - start)).round_ties_even();
                fill(t.xp, &[("n", &grouped(per_hour as i64))])
            }
            _ => String::new(),
        };
        let money = match self.money {
            Some((first, last)) => fill(t.money, &[("m", &money_text(last - first))]),
            None => String::new(),
        };
        let mut card = json!({
            "id": "session", "kind": "event", "prio": 3, "src": "companion",
            "at": now as i64, "ttl": CARD_TTL,
            "text": fill(t.session, &[("fights", &fights), ("deaths", &deaths), ("xp", &xp), ("money", &money)]),
            "basis": fill(t.basis, &[("hm", &local_hm(self.start.filter(|s| *s != 0.0).unwrap_or(now)))]),
        });
        // A fight's usual time: the saved history's when it has one, else the strip's
        // (docs/specs/331.md, section 5), with the history's count of saved fights.
        let usual_of = |f: &Fight| -> Option<(i64, Option<usize>)> {
            let (guid, name) = self.who.as_ref()?;
            let saved =
                self.history
                    .as_ref()?
                    .usual(guid.as_deref(), name, f.bkey.as_deref()?, &f.key);
            saved.map(|(u, n)| (u, Some(n)))
        };
        let times = |f: &Fight| -> Option<(i64, i64, Option<usize>)> {
            let (usual, saved) = usual_of(f).or(f.usual.map(|u| (u, None)))?;
            Some((f.this?, usual, saved))
        };
        // the slowest against its usual time; the first of equals, as Python's max
        let mut slowest: Option<(&Fight, i64)> = None;
        for f in &counted {
            if let Some((this, usual, _)) = times(f)
                && this > usual
                && slowest.is_none_or(|(_, by)| this - usual > by)
            {
                slowest = Some((f, this - usual));
            }
        }
        if let Some((f, _)) = slowest
            && let Some((this, usual, saved)) = times(f)
        {
            if let Some(n) = saved {
                let basis = card["basis"].as_str().unwrap_or_default().to_string();
                card["basis"] = json!(basis + &fill(t.saved, &[("n", &n.to_string())]));
            }
            card["detail"] = json!(fill(
                t.slow,
                &[
                    ("name", &f.name),
                    ("this", &this.to_string()),
                    ("usual", &usual.to_string())
                ]
            ));
        }
        card
    }

    /// The set to write now, or None.
    pub fn due(&mut self, now: f64) -> Option<Value> {
        let session = self.session?;
        if !self.seen13 {
            return None; // no set before the program knows the session and the last answer
        }
        if let Some(a) = &self.ask
            && self.live
            && a.get("topic").and_then(Value::as_str) == Some("session")
            && whole(a.get("n")) != self.re
            && now - whole(a.get("t")).unwrap_or(0) as f64 <= ANSWER_WITHIN
        {
            self.re = whole(a.get("n"));
            let card = self.session_card(now);
            self.cards.retain(|c| c["id"] != "session");
            self.cards.push(card);
            self.changed = true;
        }
        let before = self.cards.len();
        self.cards.retain(|c| {
            let (at, ttl) = (
                c["at"].as_i64().unwrap_or(0),
                c["ttl"].as_i64().unwrap_or(0),
            );
            (at + ttl) as f64 > now
        });
        if self.cards.len() != before {
            self.changed = true;
        }
        if !self.changed && self.last_write.is_some_and(|w| now - w < self.heartbeat) {
            return None;
        }
        if self.changed {
            self.seq = self.seq.saturating_add(1);
        }
        (self.changed, self.last_write) = (false, Some(now));
        Some(json!({"session": session, "seq": self.seq, "re": self.re, "cards": self.cards}))
    }
}

/// Python's truth of a JSON value.
fn truthy(v: &Value) -> bool {
    match v {
        Value::Null => false,
        Value::Bool(b) => *b,
        Value::Number(n) => n.as_f64() != Some(0.0),
        Value::String(s) => !s.is_empty(),
        Value::Array(a) => !a.is_empty(),
        Value::Object(o) => !o.is_empty(),
    }
}

/// Python's `str(v.get("name") or "?")`.
fn name_of(v: Option<&Value>) -> String {
    match v {
        Some(v) if truthy(v) => match v {
            Value::String(s) => s.clone(),
            v => v.to_string(),
        },
        _ => "?".into(),
    }
}

/// The reader's /events: a line at a time, None after a quiet QUIET (so the heartbeat runs).
struct Events {
    lines: BufReader<TcpStream>,
    /// A line read in part before a quiet turn: kept, the rest comes after it.
    part: Vec<u8>,
}

impl Events {
    /// `reader` is "http://HOST:PORT".
    fn open(reader: &str, quiet: f64) -> io::Result<Events> {
        let bad = || {
            io::Error::new(
                io::ErrorKind::InvalidInput,
                format!("not an http://HOST:PORT address: {reader}"),
            )
        };
        let host = reader.strip_prefix("http://").ok_or_else(bad)?;
        // the connection and the whole answer's head within `quiet`: a reader that answers a
        // byte at a time does not hold the heartbeat
        let end = Instant::now() + Duration::from_secs_f64(quiet);
        let left = || {
            let left = end.saturating_duration_since(Instant::now());
            if left.is_zero() {
                Err(io::Error::from(io::ErrorKind::TimedOut))
            } else {
                Ok(left)
            }
        };
        // each address of the name in turn (localhost may give ::1 first, and the reader
        // listens on 127.0.0.1), within the one limit
        let mut tried = Err(bad());
        for address in host.to_socket_addrs()? {
            tried = TcpStream::connect_timeout(&address, left()?);
            if tried.is_ok() {
                break;
            }
        }
        let mut stream = tried?;
        stream.set_write_timeout(Some(left()?))?;
        write!(stream, "GET /events HTTP/1.0\r\nHost: {host}\r\n\r\n")?;
        let mut lines = BufReader::new(stream);
        let mut head = Vec::new();
        while !head.ends_with(b"\n\n") && !head.ends_with(b"\n\r\n") {
            lines.get_ref().set_read_timeout(Some(left()?))?;
            let mut byte = [0];
            match lines.read(&mut byte) {
                Ok(0) => return Err(io::ErrorKind::UnexpectedEof.into()),
                Ok(_) => head.push(byte[0]),
                Err(e) if e.kind() == io::ErrorKind::Interrupted => {} // a signal (#236)
                Err(e) => return Err(e),
            }
        }
        let head = String::from_utf8_lossy(&head);
        let status = head.lines().next().unwrap_or("");
        if status.split_whitespace().nth(1) != Some("200") {
            return Err(io::Error::other(format!("/events: {}", status.trim())));
        }
        lines
            .get_ref()
            .set_read_timeout(Some(Duration::from_secs_f64(quiet)))?;
        Ok(Events {
            lines,
            part: Vec::new(),
        })
    }

    /// The next event (Some(None): a quiet turn or a sign of life), or None at the end.
    fn next(&mut self) -> io::Result<Option<Option<Value>>> {
        loop {
            // what a read gave before an error stays in `part` (read_until keeps it)
            match self.lines.read_until(b'\n', &mut self.part) {
                Ok(0) => return Ok(None),
                Ok(_) if !self.part.ends_with(b"\n") => return Ok(None), // the end, in a line
                Ok(_) => {}
                Err(e)
                    if matches!(
                        e.kind(),
                        io::ErrorKind::WouldBlock | io::ErrorKind::TimedOut
                    ) =>
                {
                    return Ok(Some(None));
                }
                Err(e) => return Err(e),
            }
            let raw = std::mem::take(&mut self.part);
            let line = String::from_utf8_lossy(&raw);
            let line = line.trim();
            if let Some(data) = line.strip_prefix("data: ") {
                if let Ok(e) = serde_json::from_str(data) {
                    return Ok(Some(Some(e)));
                }
            } else if line.starts_with(':') {
                return Ok(Some(None)); // a sign of life from the reader
            }
        }
    }
}

fn wall() -> f64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs_f64()
}

/// The pace of `run`: the heartbeat, the pause between tries, a quiet stream's turn, and an
/// end (for tests).
pub struct Pace {
    pub heartbeat: f64,
    pub retry: f64,
    pub quiet: f64,
    pub until: Option<f64>,
}

impl Default for Pace {
    fn default() -> Pace {
        Pace {
            heartbeat: HEARTBEAT,
            retry: RETRY,
            quiet: QUIET,
            until: None,
        }
    }
}

/// Follows the reader and writes sets until `pace.until` or for ever. While the reader cannot
/// be reached the heartbeat goes on (the game must not take the program for gone), with
/// nothing new: no state is live. A set that cannot be written ends it, with the reason.
pub fn run(
    addons: &Path,
    reader: &str,
    log: Option<&Path>,
    history: Option<&Path>,
    pace: &Pace,
) -> Result<(), String> {
    // a file the owner named that cannot be read stops the start (docs/specs/331.md, section 5)
    let history = history.map(crate::history::read).transpose()?;
    let mut bot = Assistant {
        heartbeat: pace.heartbeat,
        history,
        ..Assistant::default()
    };
    let over = || pace.until.is_some_and(|u| wall() >= u);
    let tick = |bot: &mut Assistant, e: Option<&Value>| -> Result<(), String> {
        let now = wall();
        if let Some(e) = e {
            bot.feed(e, now);
        }
        let Some(set) = bot.due(now) else {
            return Ok(());
        };
        slots::write(addons, None, None, Some(slots::check_assist(&set)?))?;
        if let Some(log) = log {
            let mut line = set.clone();
            line["written"] = json!(now as i64);
            let written = std::fs::OpenOptions::new()
                .create(true)
                .append(true)
                .open(log)
                .and_then(|mut f| writeln!(f, "{}", dumps_ascii(&line)));
            if let Err(e) = written {
                // the log is for a person: the program goes on without it
                eprintln!("--log {}: {e}", log.display());
            }
        }
        Ok(())
    };
    while !over() {
        if let Ok(mut events) = Events::open(reader, pace.quiet) {
            while let Ok(Some(e)) = events.next() {
                tick(&mut bot, e.as_ref())?;
                if over() {
                    return Ok(());
                }
            }
        }
        bot.live = false; // the stream ended or failed: wait, beating, then again
        let wait = wall() + pace.retry;
        while wall() < wait && !over() {
            tick(&mut bot, None)?;
            std::thread::sleep(Duration::from_secs_f64(pace.retry.min(1.0)));
        }
    }
    Ok(())
}
