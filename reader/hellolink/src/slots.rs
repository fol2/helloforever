//! The slot writer, as `write` in tools/hellolink.py (docs/specs/115.md, section 6).
//!
//! The slot file has three parts, each with one writer: the text (`seq`, `text`; `/hlink`),
//! the reader's request to the strip (`strip`, docs/specs/29.md, section 3) and the
//! assistant's set of cards (`assist`). A write replaces its own part and carries the others
//! over; a write of `strip` or `assist` keeps the top `seq` and `text`, so `/hlink` does not
//! show an old text as new. The parts live in `.parts.json` beside the first slot, which the
//! game never reads; the Python tool reads and writes the same file, under the same lock.
//! The slot files are byte for byte those of the Python tool.

use serde_json::{Map, Value, json};
use std::fs::{self, File, OpenOptions};
use std::io::{self, Write};
use std::os::unix::fs::OpenOptionsExt;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::{Duration, Instant};
use std::time::{SystemTime, UNIX_EPOCH};

/// How long a write waits for another writer's lock.
pub const LOCK_WAIT: Duration = Duration::from_secs(10);

const CARD_FIELDS: [&str; 9] = [
    "id", "kind", "prio", "src", "at", "ttl", "text", "basis", "detail",
];
/// The card fields that are strings; the others are whole numbers.
const CARD_TEXT: [&str; 6] = ["id", "kind", "src", "text", "basis", "detail"];

/// A Lua string literal of the bytes: data, never code.
pub fn lua_string(text: &[u8]) -> Vec<u8> {
    let mut out = vec![b'"'];
    for &b in text {
        match b {
            b'"' | b'\\' => out.extend([b'\\', b]),
            // control bytes, newline included
            0..0x20 | 0x7F => out.extend(format!("\\{b:03}").bytes()),
            _ => out.push(b),
        }
    }
    out.push(b'"');
    out
}

/// A JSON number that is a whole number (Python's int, not float, not bool).
fn whole(v: Option<&Value>) -> bool {
    v.and_then(Value::as_number)
        .is_some_and(|n| n.is_i64() || n.is_u64())
}

/// The set as the tool can write it: whole numbers and strings where the spec has them, at
/// most 8 cards; a field a card does not need is left out. The addon checks the rest
/// (section 6, "What HelloLink takes").
pub fn check_assist(a: &Value) -> Result<Value, String> {
    let Some(a) = a.as_object() else {
        return Err("the set needs whole numbers session and seq".into());
    };
    if !whole(a.get("session")) || !whole(a.get("seq")) {
        return Err("the set needs whole numbers session and seq".into());
    }
    let re = a.get("re").filter(|v| !v.is_null());
    if re.is_some() && !whole(re) {
        return Err("re is a whole number or absent".into());
    }
    let cards = match a.get("cards").and_then(Value::as_array) {
        Some(cards) if cards.len() <= 8 => cards,
        _ => return Err("cards is a list of at most 8".into()),
    };
    let mut out = Vec::new();
    for c in cards {
        let c = c.as_object().ok_or("a card is an object")?;
        let mut card = Map::new();
        for k in CARD_FIELDS {
            let Some(v) = c.get(k).filter(|v| !v.is_null()) else {
                continue;
            };
            let right = if CARD_TEXT.contains(&k) {
                v.is_string()
            } else {
                whole(Some(v))
            };
            if !right {
                return Err(format!("card field {k} has the wrong type"));
            }
            card.insert(k.into(), v.clone());
        }
        out.push(Value::Object(card));
    }
    Ok(json!({"session": a["session"], "seq": a["seq"], "re": re, "cards": out}))
}

/// A whole number or a string as the Lua file has it.
fn lua_value(v: &Value) -> Vec<u8> {
    match v {
        Value::String(s) => lua_string(s.as_bytes()),
        v => v.to_string().into_bytes(),
    }
}

fn assist_lua(a: &Value, t: i64) -> Vec<u8> {
    let mut items = vec![
        format!("session = {}", a["session"]).into_bytes(),
        format!("seq = {}", a["seq"]).into_bytes(),
        format!("t = {t}").into_bytes(),
    ];
    if let Some(re) = a.get("re").filter(|v| !v.is_null()) {
        items.push(format!("re = {re}").into_bytes());
    }
    let cards: Vec<Vec<u8>> = a["cards"]
        .as_array()
        .map(Vec::as_slice)
        .unwrap_or_default()
        .iter()
        .map(|c| {
            let fields: Vec<Vec<u8>> = CARD_FIELDS
                .iter()
                .filter_map(|k| {
                    c.get(k)
                        .map(|v| [format!("{k} = ").into_bytes(), lua_value(v)].concat())
                })
                .collect();
            [b"{ ".to_vec(), fields.join(&b", "[..]), b" }".to_vec()].concat()
        })
        .collect();
    items.push(if cards.is_empty() {
        b"cards = {}".to_vec()
    } else {
        [
            b"cards = { ".to_vec(),
            cards.join(&b", "[..]),
            b" }".to_vec(),
        ]
        .concat()
    });
    [b"{ ".to_vec(), items.join(&b", "[..]), b" }".to_vec()].concat()
}

/// A slot's file. `strip` is the session whose strip is asked to fall back to depth 2;
/// `assist` the set of cards (checked by check_assist), written at time `t`.
pub fn inbox_file(
    seq: i64,
    text: &str,
    slots: usize,
    strip: Option<i64>,
    assist: Option<&Value>,
    t: i64,
) -> Vec<u8> {
    let mut out = format!("HelloLink_Inbox = {{ seq = {seq}, text = ").into_bytes();
    out.extend(lua_string(text.as_bytes()));
    out.extend(format!(", slots = {slots}").bytes());
    if let Some(session) = strip {
        out.extend(format!(", strip = {{ session = {session}, depth = 2 }}").bytes());
    }
    if let Some(a) = assist {
        out.extend(b", assist = ");
        out.extend(assist_lua(a, t));
    }
    out.extend(b" }\n");
    out
}

/// The slot folders, `HelloLink_S001` and on, in order.
pub fn slots(addons: &Path) -> Vec<PathBuf> {
    let mut found: Vec<PathBuf> = fs::read_dir(addons)
        .into_iter()
        .flatten()
        .flatten()
        .filter(|e| {
            let name = e.file_name();
            let name = name.to_string_lossy();
            name.len() == 14
                && name.starts_with("HelloLink_S")
                && name[11..].bytes().all(|b| b.is_ascii_digit())
        })
        .map(|e| e.path())
        .filter(|p| p.is_dir())
        .collect();
    found.sort();
    found
}

/// A temporary file of its own per write, then a rename: the game never sees half a file, and
/// two writers at once cannot publish each other's unfinished one. Mode 0600, as Python's
/// mkstemp: the texts and cards are the player's, not other users' of the computer.
fn put(slot: &Path, data: &[u8], name: &str) -> Result<(), String> {
    static NEXT: AtomicU64 = AtomicU64::new(0);
    let n = NEXT.fetch_add(1, Ordering::Relaxed);
    let tmp = slot.join(format!(".inbox-{}-{n}", std::process::id()));
    let written = OpenOptions::new()
        .write(true)
        .create_new(true)
        .mode(0o600)
        .open(&tmp)
        .and_then(|mut f| f.write_all(data))
        .and_then(|_| fs::rename(&tmp, slot.join(name)));
    written.map_err(|e| {
        let _ = fs::remove_file(&tmp);
        format!("{}: {e}", slot.join(name).display())
    })
}

/// Strips the ASCII digits at the end: (the rest, the digits), None when there are none.
fn digits_at_end(data: &[u8]) -> Option<(&[u8], &[u8])> {
    let n = data.iter().rev().take_while(|b| b.is_ascii_digit()).count();
    (n > 0).then(|| data.split_at(data.len() - n))
}

/// The session a slot file asks the strip to fall back in, or None. The request is the last
/// field of a file written without an assist part: `", [slots = N, ]strip = { session = S,
/// depth = 2 } }\n` at its very end (Python's STRIP_ASK). The same words inside the text are
/// followed by the text's closing quote, and a quote inside the text has a backslash, so they
/// cannot end the file this way.
pub fn strip_ask(data: &[u8]) -> Option<i64> {
    let rest = data.strip_suffix(b", depth = 2 } }\n")?;
    let (rest, session) = digits_at_end(rest)?;
    let rest = rest.strip_suffix(b"strip = { session = ")?;
    let rest = match rest.strip_suffix(b", ") {
        Some(before) if !before.ends_with(b"\"") => {
            let (before, _) = digits_at_end(before)?;
            before.strip_suffix(b"slots = ")?
        }
        _ => rest,
    };
    if !rest.ends_with(b"\", ") {
        return None;
    }
    std::str::from_utf8(session).ok()?.parse().ok()
}

/// The `seq` and `text` at the head of a slot file written before the parts were kept, or
/// None (Python's OLD_TOP and its unescaping).
pub fn old_top(data: &[u8]) -> Option<(i64, String)> {
    let rest = data.strip_prefix(b"HelloLink_Inbox = { seq = ")?;
    let n = rest.iter().take_while(|b| b.is_ascii_digit()).count();
    let seq = std::str::from_utf8(&rest[..n]).ok()?.parse().ok()?;
    let mut rest = rest[n..].strip_prefix(b", text = \"")?.iter();
    let mut raw = Vec::new();
    loop {
        match *rest.next()? {
            b'"' => break,
            b'\\' => match *rest.next()? {
                b'\n' => return None, // Python's `.` takes no line break here
                b => raw.extend([b'\\', b]),
            },
            b => raw.push(b),
        }
    }
    let mut text = Vec::new();
    let mut i = 0;
    while i < raw.len() {
        if raw[i] != b'\\' {
            text.push(raw[i]);
            i += 1;
        } else if raw.len() >= i + 4 && raw[i + 1..i + 4].iter().all(u8::is_ascii_digit) {
            text.push(std::str::from_utf8(&raw[i + 1..i + 4]).ok()?.parse().ok()?);
            i += 4;
        } else {
            text.push(raw[i + 1]);
            i += 2;
        }
    }
    Some((seq, String::from_utf8_lossy(&text).into_owned()))
}

fn now() -> std::time::Duration {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
}

/// What a write did: the bytes of the slot file and the slots written.
pub struct Written {
    pub bytes: usize,
    pub slots: usize,
}

/// Puts the file into every slot, with the parts given replaced and the others carried over.
/// A reader's request for the strip to fall back stays in the slots until another session is
/// named (the addon looks at a slot only now and then). `assist` is a set checked by
/// check_assist.
pub fn write(
    addons: &Path,
    text: Option<&str>,
    strip_session: Option<i64>,
    assist: Option<Value>,
) -> Result<Written, String> {
    let found = slots(addons);
    let Some(first) = found.first() else {
        return Err(format!(
            "no HelloLink slots in {}: run `install` first",
            addons.display()
        ));
    };
    // One writer at a time reads the parts, replaces its own and writes every slot: two
    // writers (a text, a reader's request, the companion) cannot undo each other. flock(2),
    // as the Python tool's fcntl.flock; waited for LOCK_WAIT at most (Python: no limit), and
    // Ctrl-C ends the wait.
    let lock_path = first.join(".lock");
    let at = |e: &dyn std::fmt::Display| format!("{}: {e}", lock_path.display());
    let lock = File::create(&lock_path).map_err(|e| at(&e))?;
    let end = Instant::now() + LOCK_WAIT;
    loop {
        match lock.try_lock() {
            Ok(()) => break,
            Err(std::fs::TryLockError::WouldBlock)
                if Instant::now() < end && !crate::capture::interrupted() =>
            {
                std::thread::sleep(Duration::from_millis(10));
            }
            Err(std::fs::TryLockError::WouldBlock) if crate::capture::interrupted() => {
                return Err(at(&"Ctrl-C while another writer held it"));
            }
            Err(std::fs::TryLockError::WouldBlock) => {
                return Err(at(&format!(
                    "another writer held it for more than {} s",
                    LOCK_WAIT.as_secs()
                )));
            }
            Err(std::fs::TryLockError::Error(e)) => return Err(at(&e)),
        }
    }
    let parts_path = first.join(".parts.json");
    let kept = match fs::read(&parts_path) {
        Ok(raw) => Some(serde_json::from_slice::<Value>(&raw).map_err(|e| {
            // Python reads it then as an old slot, and a part it cannot carry over is lost:
            // nothing is written instead
            format!(
                "{}: it cannot be read ({e}): nothing was written",
                parts_path.display()
            )
        })?),
        Err(e) if e.kind() == io::ErrorKind::NotFound => None,
        Err(e) => return Err(format!("{}: {e}", parts_path.display())),
    };
    let mut parts = match kept {
        Some(Value::Object(parts)) => parts,
        Some(_) => {
            return Err(format!(
                "{}: not an object: nothing was written",
                parts_path.display()
            ));
        }
        None => {
            // slots written before the parts were kept: their text, its seq and the request stay
            let old = fs::read(first.join("Inbox.lua")).unwrap_or_default();
            let mut parts = Map::new();
            parts.insert("strip".into(), json!(strip_ask(&old)));
            if let Some((seq, text)) = old_top(&old) {
                parts.insert("seq".into(), json!(seq));
                parts.insert("text".into(), json!(text));
            }
            parts
        }
    };
    if text.is_some() || !parts.contains_key("seq") {
        parts.insert("seq".into(), json!(now().as_millis() as i64));
        parts.insert("text".into(), json!(text.unwrap_or("")));
    }
    if let Some(session) = strip_session {
        parts.insert("strip".into(), json!(session));
    }
    if let Some(assist) = assist {
        parts.insert("assist".into(), assist);
        parts.insert("t".into(), json!(now().as_secs() as i64));
    }
    let data = inbox_file(
        parts["seq"].as_i64().unwrap_or(0),
        parts["text"].as_str().unwrap_or(""),
        found.len(),
        parts.get("strip").and_then(Value::as_i64),
        parts.get("assist").filter(|v| !v.is_null()),
        parts.get("t").and_then(Value::as_i64).unwrap_or(0),
    );
    let raw = serde_json::to_vec(&parts).map_err(|e| e.to_string())?;
    put(first, &raw, ".parts.json")?;
    for slot in &found {
        put(slot, &data, "Inbox.lua")?;
    }
    Ok(Written {
        bytes: data.len(),
        slots: found.len(),
    })
}
