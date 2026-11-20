//! The local HTTP API (src/api.rs): the checks of tests/strip_api_test.py, and the answers the
//! Python server (tools/strip_api.py) gave to the same events, kept in tests/api/, byte for byte.

use hellolink::api::{Api, SEND_WAIT};
use serde_json::{Value, json};
use std::io::{BufRead, BufReader, Read, Write};
use std::net::TcpStream;
use std::thread;
use std::time::{Duration, Instant};

/// The answers of the Python server (tools/strip_api.py, deleted in #195 step 3c) to `told()`.
const ANSWERS: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/tests/api/python_answers.json");

fn wait() -> Duration {
    Duration::from_secs_f64(SEND_WAIT)
}

/// (status, head in lower case, body) of one request.
fn get(port: u16, path: &str, host: Option<&str>, method: &str) -> (u16, String, String) {
    let mut s = TcpStream::connect(("127.0.0.1", port)).unwrap();
    s.set_read_timeout(Some(Duration::from_secs(5))).unwrap();
    let host = host.map_or(format!("127.0.0.1:{port}"), String::from);
    write!(s, "{method} {path} HTTP/1.1\r\nHost: {host}\r\n\r\n").unwrap();
    let mut raw = String::new();
    s.read_to_string(&mut raw).unwrap();
    let (head, body) = raw.split_once("\r\n\r\n").unwrap();
    let status = head.split(' ').nth(1).unwrap().parse().unwrap();
    (status, head.to_lowercase(), body.to_string())
}

fn present(port: u16) -> Value {
    serde_json::from_str(&get(port, "/state", None, "GET").2).unwrap()
}

/// A connection to /events, its head read: (reader, head in lower case).
fn listen(port: u16) -> (BufReader<TcpStream>, String) {
    let mut s = TcpStream::connect(("127.0.0.1", port)).unwrap();
    s.set_read_timeout(Some(Duration::from_secs(5))).unwrap();
    write!(s, "GET /events HTTP/1.1\r\nHost: 127.0.0.1:{port}\r\n\r\n").unwrap();
    let mut f = BufReader::new(s);
    let mut head = String::new();
    loop {
        let mut line = String::new();
        f.read_line(&mut line).unwrap();
        if line.trim().is_empty() {
            break;
        }
        head += &line.to_lowercase();
    }
    (f, head)
}

/// The next `n` data lines of an /events connection, as they came (comments are a heartbeat).
fn lines_of(f: &mut BufReader<TcpStream>, n: usize) -> Vec<String> {
    let mut got = vec![];
    while got.len() < n {
        let mut line = String::new();
        assert!(
            f.read_line(&mut line).unwrap() > 0,
            "the events ended after {}",
            got.len()
        );
        if let Some(data) = line.strip_prefix("data: ") {
            got.push(data.trim_end().to_string());
        }
    }
    got
}

fn events_of(f: &mut BufReader<TcpStream>, n: usize) -> Vec<Value> {
    lines_of(f, n)
        .iter()
        .map(|l| serde_json::from_str(l).unwrap())
        .collect()
}

fn until(what: impl Fn() -> bool) -> bool {
    let end = Instant::now() + Duration::from_secs(3);
    while Instant::now() < end && !what() {
        thread::sleep(Duration::from_millis(20));
    }
    what()
}

fn told() -> Vec<Value> {
    vec![
        json!({"kind": "state", "session": 4711, "seq": 9, "depth": 4, "fast": {"clock": {"clock": 1}}, "levels": {"health": 0.76, "power": 1.0}}),
        json!({"kind": "levels", "levels": {"health": 0.8, "power": null}}),
        json!({"kind": "object", "id": 4, "format": 1, "text": "{\"free\": 12, \"name\": \"Matty é 你\"}"}),
        json!({"kind": "stale-object", "id": 4}),
        json!({"kind": "object", "id": 10, "format": 255, "text": null}),
        json!({"kind": "fresh-object", "id": 4}),
        json!({"kind": "stale", "why": "no new seq"}),
        json!({"kind": "waiting", "why": "no row on any display"}),
    ]
}

#[test]
fn the_checks_of_the_python_api_test() {
    let mut api = Api::start(0, wait()).unwrap();
    let port = api.port;
    let (status, head, body) = get(port, "/state", None, "GET");
    let first: Value = serde_json::from_str(&body).unwrap();
    assert!(
        status == 200
            && head.contains("content-type: application/json")
            && first
                == json!({"state": null, "levels": null, "objects": {}, "condition": "waiting", "age": null}),
        "/state before any row: 200, JSON, no state, no object, condition `waiting`"
    );
    let (mut f, sse) = listen(port);
    assert!(
        sse.starts_with("http/1.0 200") && sse.contains("content-type: text/event-stream"),
        "/events answers 200 as text/event-stream"
    );
    assert!(until(|| api.clients() == 1), "one client is listening");
    let state = told()[0].clone();
    let bags = json!({"kind": "object", "id": 4, "format": 1, "text": "{\"free\": 12, \"items\": [[2318, 16]]}"});
    let sent = [
        state.clone(),
        json!({"kind": "levels", "levels": {"health": 80}}),
        bags.clone(),
        json!({"kind": "stale-object", "id": 4}),
    ];
    for e in &sent {
        api.tell(e);
    }
    let got = events_of(&mut f, 5);
    let mut snapshot = first.clone();
    snapshot["kind"] = json!("snapshot");
    assert_eq!(
        got[0], snapshot,
        "/events gives the present first, as a `snapshot` event"
    );
    assert_eq!(
        got[1..],
        sent,
        "... then every event after the connection, in order"
    );
    let now = present(port);
    assert!(
        now["state"] == state
            && now["condition"] == "live"
            && now["age"].as_f64().is_some_and(|a| (0.0..5.0).contains(&a)),
        "/state has the last state"
    );
    assert_eq!(
        now["levels"],
        json!({"health": 80}),
        "/state has the last levels"
    );
    assert_eq!(
        now["objects"],
        json!({"4": {"format": 1, "text": bags["text"], "stale": true}}),
        "/state has the object, marked stale"
    );
    api.tell(&json!({"kind": "fresh-object", "id": 4}));
    api.tell(
        &json!({"kind": "object", "id": 4, "format": 1, "text": "{\"free\": 11, \"items\": []}"}),
    );
    api.tell(&json!({"kind": "object", "id": 2, "format": 255, "text": null}));
    let now = present(port);
    assert_eq!(
        now["objects"]["4"],
        json!({"format": 1, "text": "{\"free\": 11, \"items\": []}", "stale": false}),
        "a newer object replaces the older one, and is not stale"
    );
    assert_eq!(
        now["objects"]["2"],
        json!({"format": 255, "text": null, "stale": false}),
        "an object the addon cannot read is given as such"
    );
    let (mut f2, _) = listen(port);
    let mut late = events_of(&mut f2, 1).remove(0);
    let (mut expected, late_age) = (now.clone(), late["age"].take());
    expected["age"] = Value::Null;
    late.as_object_mut().unwrap().remove("kind");
    assert!(
        late == expected && late_age.is_number(),
        "a client that comes late gets the objects in its snapshot, as /state has them"
    );
    api.tell(&json!({"kind": "levels", "levels": {"health": 81}}));
    assert_eq!(
        events_of(&mut f2, 1),
        [json!({"kind": "levels", "levels": {"health": 81}})],
        "... and the next event after it"
    );
    for kind in ["stale", "lost", "waiting"] {
        api.tell(&json!({"kind": kind, "why": "no row"}));
        let d = present(port);
        assert!(
            d["condition"] == kind && d["state"] == state,
            "after `{kind}` the condition is `{kind}`, and the last state is still given"
        );
    }
    let mut new = state.clone();
    new["session"] = json!(4712);
    new["seq"] = json!(1);
    api.tell(&new);
    let now = present(port);
    assert!(
        now["condition"] == "live" && now["objects"] == json!({}),
        "a state of a new session: live again, and the objects of the old session are gone"
    );

    assert_eq!(
        get(port, "/state", Some(&format!("evil.example:{port}")), "GET").0,
        403,
        "a foreign Host is refused with 403 (DNS rebinding)"
    );
    assert_eq!(
        get(port, "/events", Some("evil.example"), "GET").0,
        403,
        "... on /events too"
    );
    assert_eq!(
        get(
            port,
            "/state",
            Some(&format!("127.0.0.1:{}", port.wrapping_add(1))),
            "GET"
        )
        .0,
        403,
        "... and so is another port"
    );
    assert_eq!(
        get(port, "/state", Some(&format!("LocalHost:{port}")), "GET").0,
        200,
        "localhost is this server too"
    );
    assert_eq!(
        get(port, "/nothing", None, "GET").0,
        404,
        "an unknown path is 404"
    );
    let mut two = TcpStream::connect(("127.0.0.1", port)).unwrap();
    write!(
        two,
        "GET /state HTTP/1.1\r\nHost: evil.example\r\nHost: 127.0.0.1:{port}\r\n\r\n"
    )
    .unwrap();
    let mut answer = String::new();
    two.read_to_string(&mut answer).unwrap();
    assert!(
        answer.starts_with("HTTP/1.0 403"),
        "with two Host lines the first counts, as in Python ({answer})"
    );
    let mut pair = TcpStream::connect(("127.0.0.1", port)).unwrap();
    write!(
        pair,
        "GET /state HTTP/1.1\r\n\r\nGET /state HTTP/1.1\r\nHost: 127.0.0.1:{port}\r\n\r\n"
    )
    .unwrap();
    let mut answer = String::new();
    pair.read_to_string(&mut answer).unwrap();
    assert!(
        answer.starts_with("HTTP/1.0 403"),
        "a request with no Host is refused, though a second one after it has one ({answer})"
    );
    for split in ["\n\r\n", "\n\n", "\r\n\n"] {
        let mut pair = TcpStream::connect(("127.0.0.1", port)).unwrap();
        write!(
            pair,
            "GET /state HTTP/1.1{split}GET /state HTTP/1.1\r\nHost: 127.0.0.1:{port}\r\n\r\n"
        )
        .unwrap();
        let mut answer = String::new();
        pair.read_to_string(&mut answer).unwrap();
        assert!(
            answer.starts_with("HTTP/1.0 403"),
            "... whatever the lines end in ({split:?}: {answer})"
        );
    }
    assert_eq!(get(port, "/state", None, "POST").0, 501, "POST is refused");
    let answers = [
        get(port, "/state", None, "GET").1,
        get(port, "/nothing", None, "GET").1,
        get(port, "/state", Some("evil.example"), "GET").1,
        sse,
    ];
    assert!(
        !answers
            .iter()
            .any(|h| h.contains("access-control-allow-origin")),
        "no answer carries Access-Control-Allow-Origin"
    );

    let mut big = bags.clone();
    big["text"] = json!("x".repeat(20000));
    let began = Instant::now();
    for _ in 0..4000 {
        api.tell(&big); // 80 MB to clients that read nothing
    }
    assert!(
        began.elapsed() < Duration::from_secs(2),
        "telling 4000 large events to a client that does not read takes no time ({:?})",
        began.elapsed()
    );
    assert!(
        until(|| api.clients() == 0),
        "... and that client is dropped"
    );
    assert_eq!(
        get(port, "/state", None, "GET").0,
        200,
        "the server still answers"
    );
    drop((f, f2));
    let (mut f3, _) = listen(port);
    events_of(&mut f3, 1);
    assert!(
        until(|| api.clients() == 1),
        "a new client is listening again"
    );
    let began = Instant::now();
    api.close();
    let mut rest = String::new();
    let ended = f3.read_to_string(&mut rest).map(|_| began.elapsed());
    assert!(
        ended.as_ref().is_ok_and(|t| *t < Duration::from_secs(3)),
        "close ends a client that waits for an event, at once ({ended:?})"
    );
    assert!(
        TcpStream::connect(("127.0.0.1", port)).is_err(),
        "after close the port is free"
    );

    let quick = Api::start(0, Duration::from_millis(300)).unwrap();
    let mut slow = TcpStream::connect(("127.0.0.1", quick.port)).unwrap();
    slow.set_read_timeout(Some(Duration::from_secs(5))).unwrap();
    let began = Instant::now();
    for b in b"GET /state HTTP/1.1\r\nHost: 127.0.0.1\r\nX: " {
        if slow.write_all(&[*b]).is_err() {
            break;
        }
        thread::sleep(Duration::from_millis(50));
    }
    let mut rest = Vec::new();
    let _ = slow.read_to_end(&mut rest);
    assert!(
        rest.is_empty() && began.elapsed() < Duration::from_secs(3),
        "a client that sends its request a byte at a time is cut off at the limit for the whole head ({:?})",
        began.elapsed()
    );
    let mut mute = TcpStream::connect(("127.0.0.1", quick.port)).unwrap();
    mute.set_read_timeout(Some(Duration::from_secs(5))).unwrap();
    let began = Instant::now();
    let gone = mute.read(&mut [0; 1]).is_ok_and(|n| n == 0);
    assert!(
        gone && began.elapsed() < Duration::from_secs(3),
        "a client that sends no request is cut off after the limit ({:?})",
        began.elapsed()
    );
}

/// /state's body with the age taken out.
fn ageless(body: &str) -> String {
    match body.split_once("\"age\": ") {
        Some((head, _)) => format!("{head}\"age\": A}}\n"),
        None => body.to_string(),
    }
}

/// A server's answers to the events of `told()`, in order: the first snapshot, `/state`
/// (without the age) after it and after each event, each event on `/events`, a late snapshot
/// (without the age), and the status and body of a path that is not there and of a foreign Host.
fn answers(port: u16, mut tell: impl FnMut(&Value)) -> Vec<String> {
    let state = || ageless(&get(port, "/state", None, "GET").2);
    let (mut f, _) = listen(port);
    let mut out = lines_of(&mut f, 1);
    out.push(state());
    for e in told() {
        tell(&e);
        out.extend(lines_of(&mut f, 1));
        out.push(state());
    }
    let (mut late, _) = listen(port);
    let late = lines_of(&mut late, 1).remove(0);
    let (head, tail) = late.split_once("\"age\": ").unwrap();
    out.push(format!("{head}{}", &tail[tail.find(',').unwrap()..]));
    for (path, host) in [("/nothing", None), ("/state", Some("evil.example"))] {
        let (status, _, body) = get(port, path, host, "GET");
        out.push(format!("{status} {body}"));
    }
    out
}

#[test]
fn the_same_answers_as_the_python_server() {
    let rs = Api::start(0, wait()).unwrap();
    let got = answers(rs.port, |e| rs.tell(e));
    let want: Vec<String> =
        serde_json::from_str(&std::fs::read_to_string(ANSWERS).unwrap()).unwrap();
    assert_eq!(
        got.len(),
        want.len(),
        "as many answers as the Python server gave"
    );
    for (i, (g, w)) in got.iter().zip(&want).enumerate() {
        assert_eq!(g, w, "answer {i}, byte for byte but for the age");
    }
}
