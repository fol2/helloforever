//! The reader's local HTTP API, as tools/strip_api.py (docs/STRIP.md, section 10): one
//! reader, any number of local programs.
//!
//! ```text
//! GET /state    the present: the last state, the last levels, the last of each object,
//!               the row's condition and the age of the state in seconds
//! GET /events   server-sent events, `data: <JSON>` and an empty line: first the present
//!               (`{"kind": "snapshot", ...}`, what /state gives), then every event after
//!               it, the JSON that `watch --json` prints; nothing is missed in between
//! ```
//!
//! Read-only, and for this computer only: it listens on 127.0.0.1, sends no CORS header (a web
//! page in a browser cannot read the answer) and refuses a request whose Host is not this
//! server (a web page that points its own name at 127.0.0.1). Nothing is kept on disk.
//! HTTP/1.0, as Python's server: one request a connection.

use crate::rows::dumps;
use serde_json::{Map, Value, json};
use std::io::{self, Read, Write};
use std::net::{TcpListener, TcpStream};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::mpsc::{self, RecvTimeoutError, SyncSender, TrySendError};
use std::sync::{Arc, Mutex, MutexGuard};
use std::thread::{self, JoinHandle};
use std::time::{Duration, Instant};

/// Events a client may be behind before it is dropped.
pub const QUEUE: usize = 1000;
/// Seconds without an event before a comment line is sent.
pub const HEARTBEAT: f64 = 15.0;
/// Seconds a client gets for one read or write, on every route.
pub const SEND_WAIT: f64 = 10.0;
const NAMES: [&str; 2] = ["127.0.0.1", "localhost"];
/// Bytes of a request's head, at most (Python's line limit is 65536).
const HEAD_MAX: u64 = 65536;

type Event = Arc<Value>;

/// One /events client: its queue (None wakes it to leave) and its flag to leave.
struct Listener {
    id: u64,
    tx: SyncSender<Option<Event>>,
    gone: Arc<AtomicBool>,
}

impl Listener {
    /// Tells the client's thread to end, and wakes it when it waits for an event.
    fn leave(&self) {
        self.gone.store(true, Ordering::Relaxed);
        let _ = self.tx.try_send(None); // a full queue: it sees the flag after its write
    }
}

#[derive(Default)]
struct Present {
    state: Value,
    levels: Value,
    /// Each object as /state gives it, in the order first seen (Python's dict).
    objects: Vec<(String, Value)>,
    condition: &'static str,
    when: Option<Instant>,
    listeners: Vec<Listener>,
    next_id: u64,
    closed: bool,
}

impl Present {
    /// The present: state, levels, objects, condition, age.
    fn value(&self) -> Map<String, Value> {
        let objects: Map<String, Value> = self.objects.iter().cloned().collect();
        let age = self
            .when
            .map(|w| (w.elapsed().as_secs_f64() * 100.0).round() / 100.0);
        let mut out = Map::new();
        out.insert("state".into(), self.state.clone());
        out.insert("levels".into(), self.levels.clone());
        out.insert("objects".into(), Value::Object(objects));
        out.insert("condition".into(), json!(self.condition));
        out.insert("age".into(), json!(age));
        out
    }
}

pub struct Api {
    present: Arc<Mutex<Present>>,
    stop: Arc<AtomicBool>,
    server: Option<JoinHandle<()>>,
    pub port: u16,
}

fn lock(present: &Mutex<Present>) -> MutexGuard<'_, Present> {
    present.lock().unwrap_or_else(|e| e.into_inner())
}

impl Api {
    /// Listens on 127.0.0.1:port (0: a free port); `send_wait` limits each read and write.
    pub fn start(port: u16, send_wait: Duration) -> io::Result<Api> {
        let listener = TcpListener::bind(("127.0.0.1", port))?;
        let port = listener.local_addr()?.port();
        // polled, so that close can end the accept loop and free the port without unsafe code
        listener.set_nonblocking(true)?;
        let present = Arc::new(Mutex::new(Present {
            condition: "waiting",
            ..Present::default()
        }));
        let stop = Arc::new(AtomicBool::new(false));
        let (p, s) = (Arc::clone(&present), Arc::clone(&stop));
        let server = thread::spawn(move || {
            while !s.load(Ordering::Relaxed) {
                match listener.accept() {
                    Ok((stream, _)) => {
                        let p = Arc::clone(&p);
                        // no thread for it (the system has none to give): the connection is
                        // closed, and the API stays up
                        let _ = thread::Builder::new().spawn(move || {
                            let _ = serve(stream, &p, port, send_wait); // a client that left
                        });
                    }
                    Err(e) if e.kind() == io::ErrorKind::WouldBlock => {
                        thread::sleep(Duration::from_millis(20));
                    }
                    Err(_) => thread::sleep(Duration::from_millis(20)),
                }
            }
        });
        Ok(Api {
            present,
            stop,
            server: Some(server),
            port,
        })
    }

    /// /events clients now.
    pub fn clients(&self) -> usize {
        lock(&self.present).listeners.len()
    }

    /// What /state gives now.
    pub fn snapshot(&self) -> Value {
        Value::Object(lock(&self.present).value())
    }

    /// Takes one event of the reader. Never waits: a client that is QUEUE events behind is
    /// dropped (it reads /state and listens again).
    pub fn tell(&self, event: &Value) {
        let mut p = lock(&self.present);
        match event.get("kind").and_then(Value::as_str).unwrap_or("") {
            "state" => {
                if !p.state.is_null() && p.state.get("session") != event.get("session") {
                    p.objects.clear(); // the UI loaded again: its objects come anew
                }
                p.state = event.clone();
                p.when = Some(Instant::now());
                p.condition = "live";
                if let Some(levels) = event.get("levels") {
                    p.levels = levels.clone();
                }
            }
            "levels" => p.levels = event.get("levels").cloned().unwrap_or(Value::Null),
            "object" => {
                let id = key(&event["id"]);
                let object = json!({"format": event.get("format"), "text": event.get("text"), "stale": false});
                match p.objects.iter_mut().find(|(k, _)| *k == id) {
                    Some((_, v)) => *v = object,
                    None => p.objects.push((id, object)),
                }
            }
            kind @ ("stale-object" | "fresh-object") => {
                let id = key(&event["id"]);
                if let Some((_, v)) = p.objects.iter_mut().find(|(k, _)| *k == id) {
                    v["stale"] = json!(kind == "stale-object");
                }
            }
            "stale" => p.condition = "stale",
            "lost" => p.condition = "lost",
            "waiting" => p.condition = "waiting",
            _ => {}
        }
        let event: Event = Arc::new(event.clone());
        p.listeners
            .retain(|l| match l.tx.try_send(Some(Arc::clone(&event))) {
                Err(TrySendError::Full(_)) => {
                    l.leave();
                    false
                }
                _ => true,
            });
    }

    /// No new client after this; every client is told to leave, and the port is free when
    /// it returns.
    pub fn close(&mut self) {
        {
            let mut p = lock(&self.present);
            p.closed = true;
            for l in p.listeners.drain(..) {
                l.leave();
            }
        }
        self.stop.store(true, Ordering::Relaxed);
        if let Some(server) = self.server.take() {
            let _ = server.join();
        }
    }
}

impl Drop for Api {
    fn drop(&mut self) {
        self.close();
    }
}

/// An object's id as /state's key: Python's str() of the id.
fn key(id: &Value) -> String {
    match id {
        Value::String(s) => s.clone(),
        v => v.to_string(),
    }
}

/// /state's body as Python's json.dumps without sort_keys writes it: the top and each
/// object in Python's order (the objects as first seen), the events as they came (their
/// keys sorted, as the reader makes them).
fn state_body(objects: &[(String, Value)], p: &Map<String, Value>) -> String {
    let objects: Vec<String> = objects
        .iter()
        .map(|(k, v)| {
            let fields: Vec<String> = ["format", "text", "stale"]
                .iter()
                .map(|f| format!("\"{f}\": {}", dumps(&v[*f])))
                .collect();
            format!("{}: {{{}}}", dumps(&json!(k)), fields.join(", "))
        })
        .collect();
    format!(
        "{{\"state\": {}, \"levels\": {}, \"objects\": {{{}}}, \"condition\": {}, \"age\": {}}}\n",
        dumps(&p["state"]),
        dumps(&p["levels"]),
        objects.join(", "),
        dumps(&p["condition"]),
        dumps(&p["age"])
    )
}

/// A request's head, up to its empty line: `wait` for all of it (a client that sends a byte
/// now and then is cut off too), HEAD_MAX bytes at most.
fn read_head(mut stream: TcpStream, wait: Duration) -> io::Result<String> {
    let end = Instant::now() + wait;
    let mut head = Vec::new();
    let mut buf = [0; 4096];
    while !head.windows(4).any(|w| w == b"\r\n\r\n") && !head.windows(2).any(|w| w == b"\n\n") {
        let left = end.saturating_duration_since(Instant::now());
        if left.is_zero() || head.len() as u64 > HEAD_MAX {
            return Err(io::ErrorKind::TimedOut.into());
        }
        stream.set_read_timeout(Some(left))?;
        match stream.read(&mut buf)? {
            0 => break,
            n => head.extend(&buf[..n]),
        }
    }
    // the head ends at its first empty line: what came after it (another request) is not read
    let ends = [&b"\r\n\r\n"[..], b"\n\n"]
        .iter()
        .filter_map(|end| head.windows(end.len()).position(|w| w == *end))
        .min();
    head.truncate(ends.unwrap_or(head.len()));
    Ok(String::from_utf8_lossy(&head).into_owned())
}

fn answer(out: &mut TcpStream, code: u16, kind: &str, body: &[u8]) -> io::Result<()> {
    let reason = match code {
        200 => "OK",
        400 => "Bad Request",
        403 => "Forbidden",
        404 => "Not Found",
        501 => "Not Implemented",
        _ => "Service Unavailable",
    };
    let mut head =
        format!("HTTP/1.0 {code} {reason}\r\nContent-Type: {kind}\r\nCache-Control: no-store\r\n");
    if kind != "text/event-stream" {
        head += &format!("Content-Length: {}\r\n", body.len());
    }
    head += "\r\n";
    out.write_all(head.as_bytes())?;
    out.write_all(body)?;
    out.flush()
}

/// One connection: its request, then the answer.
fn serve(stream: TcpStream, present: &Mutex<Present>, port: u16, wait: Duration) -> io::Result<()> {
    stream.set_nonblocking(false)?;
    stream.set_write_timeout(Some(wait))?;
    let mut out = stream.try_clone()?;
    let head = read_head(stream, wait)?;
    let mut lines = head.lines();
    let words: Vec<&str> = lines.next().unwrap_or("").split_whitespace().collect();
    let (method, path) = match words[..] {
        [method, path, _] | [method, path] => (method.to_string(), path.to_string()),
        _ => return answer(&mut out, 400, "text/plain", b"bad request\n"),
    };
    // the first Host, as Python's headers.get
    let host = lines
        .filter_map(|h| h.split_once(':'))
        .find(|(name, _)| name.trim().eq_ignore_ascii_case("host"))
        .map(|(_, value)| value.trim().to_lowercase())
        .unwrap_or_default();
    if method != "GET" {
        return answer(&mut out, 501, "text/plain", b"GET /state or GET /events\n");
    }
    let (name, given) = host.split_once(':').unwrap_or((&host, ""));
    if !NAMES.contains(&name) || (!given.is_empty() && given != port.to_string()) {
        let body = b"this server answers to 127.0.0.1 and localhost only\n";
        return answer(&mut out, 403, "text/plain", body);
    }
    if path == "/state" {
        let (objects, p) = {
            let p = lock(present);
            (p.objects.clone(), p.value())
        };
        let body = state_body(&objects, &p); // written after the lock: `tell` does not wait
        return answer(&mut out, 200, "application/json", body.as_bytes());
    }
    if path != "/events" {
        return answer(&mut out, 404, "text/plain", b"GET /state or GET /events\n");
    }
    let (tx, rx) = mpsc::sync_channel(QUEUE);
    let gone = Arc::new(AtomicBool::new(false));
    let id = {
        // the present and the place in the line, as one step
        let mut p = lock(present);
        if p.closed {
            drop(p);
            return answer(&mut out, 503, "text/plain", b"the reader is leaving\n");
        }
        let mut snapshot = p.value();
        snapshot.insert("kind".into(), json!("snapshot"));
        let _ = tx.try_send(Some(Arc::new(Value::Object(snapshot))));
        p.next_id += 1;
        let id = p.next_id;
        p.listeners.push(Listener {
            id,
            tx,
            gone: Arc::clone(&gone),
        });
        id
    };
    let sent = (|| {
        answer(&mut out, 200, "text/event-stream", b"")?;
        while !gone.load(Ordering::Relaxed) {
            let line = match rx.recv_timeout(Duration::from_secs_f64(HEARTBEAT)) {
                Ok(Some(event)) => format!("data: {}\n\n", dumps(&event)),
                Ok(None) | Err(RecvTimeoutError::Disconnected) => break, // dropped or closed
                Err(RecvTimeoutError::Timeout) => ": still here\n\n".into(),
            };
            out.write_all(line.as_bytes())?;
            out.flush()?;
        }
        Ok(())
    })();
    lock(present).listeners.retain(|l| l.id != id);
    sent
}
