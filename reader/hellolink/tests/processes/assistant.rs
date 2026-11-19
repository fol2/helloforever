//! The assistant program (src/assistant.rs): the checks of tests/assistant_test.py, message
//! for message; the sets of tools/assistant.py on the same events and clock; and the whole
//! program against a stand-in for the reader's API and a scratch AddOns folder.

use hellolink::assistant::{Assistant, Pace, money_text, run};
use hellolink::slots::{check_assist, inbox_file};
use serde_json::{Value, json};
use std::fs;
use std::io::{BufRead, BufReader, Read, Write};
use std::net::TcpListener;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

const TOOLS: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/../../tools");
const T0: f64 = 1794516000.0;

fn state_of(session: i64, level: (i64, i64, i64), money: i64) -> Value {
    json!({"kind": "state", "session": session, "seq": 1, "depth": 4,
           "fast": {"level": {"level": level.0, "xp": level.1, "xpMax": level.2}, "purse": {"money": money, "bagFree": 3}}})
}

fn state() -> Value {
    state_of(4711, (14, 1000, 9000), 7800)
}

fn obj13(ask: Value, re: Value, seq: Value, lang: &str) -> Value {
    let v = json!({"on": true, "lang": lang, "seq": seq, "re": re, "ask": ask, "left": 150, "taken": 0, "refused": 0, "shown": null});
    json!({"kind": "object", "id": 13, "format": 1, "text": v.to_string()})
}

fn o13() -> Value {
    obj13(Value::Null, Value::Null, Value::Null, "en")
}

fn ask(n: i64, topic: &str, t: f64) -> Value {
    obj13(
        json!({"n": n, "topic": topic, "t": t as i64}),
        Value::Null,
        Value::Null,
        "en",
    )
}

fn fight(key: &str, this: i64, usual: i64, died: bool, name: &str) -> Value {
    let v = json!({"fight": key, "rev": 1, "counted": true, "id": 1984, "level": 14, "name": name,
                   "dur": [this, usual, 5], "dps": [30, 30, 5], "taken": [100, 100, 5], "died": [died, 0, 5]});
    json!({"kind": "object", "id": 12, "format": 1, "text": v.to_string()})
}

fn card(s: &Option<Value>) -> Value {
    s.as_ref().map_or(Value::Null, |s| s["cards"][0].clone())
}

fn local_hm(t: f64) -> String {
    let out = Command::new("python3")
        .args([
            "-c",
            &format!("import time; print(time.strftime('%H:%M', time.localtime({t})))"),
        ])
        .output()
        .unwrap();
    String::from_utf8_lossy(&out.stdout).trim().to_string()
}

#[test]
fn the_checks_of_the_python_test() {
    // 1. No set before the session and object 13 are known; then the heartbeat.
    let mut b = Assistant::default();
    assert!(b.due(T0).is_none(), "no set before anything is known");
    b.feed(&state(), T0);
    assert!(
        b.due(T0).is_none(),
        "no set before object 13 is read (its re must be known first)"
    );
    b.feed(&o13(), T0);
    let s = b.due(T0).unwrap();
    assert!(
        s["session"] == 4711 && s["cards"] == json!([]) && s["re"].is_null(),
        "then a set for the session, with no card and no re"
    );
    assert!(
        b.due(T0 + 30.0).is_none(),
        "the heartbeat: nothing new within a minute"
    );
    let s2 = b.due(T0 + 61.0);
    assert!(
        s2.is_some_and(|s2| s2["seq"] == s["seq"]),
        "...and a set again after a minute, the same seq (nothing changed)"
    );

    // 2. `session` from a recorded run of events.
    let mut b = Assistant::default();
    let run = [
        state_of(4711, (14, 1000, 9000), 7800),
        o13(),
        fight("hf1-a-1", 12, 15, false, "Defias Thug"),
        fight("hf1-a-2", 18, 12, true, "Riverpaw Gnoll"),
        fight("hf1-a-2", 18, 12, true, "Riverpaw Gnoll"),
        fight("hf1-a-3", 14, 13, false, "Defias Thug"),
        state_of(4711, (14, 8500, 9000), 17000),
        state_of(4711, (15, 500, 9800), 19000),
    ];
    for (i, e) in run.iter().enumerate() {
        b.feed(e, T0 + i as f64 * 300.0);
    }
    let now = T0 + 7.0 * 300.0;
    b.feed(&ask(1, "session", now - 5.0), now);
    let s = b.due(now);
    let c = card(&s);
    assert_eq!(
        c["text"], "This session: 3 fights, 1 death, 14,571 XP an hour, +1 g 12 s",
        "session: the fights counted once each, the deaths, XP an hour, the money gained"
    );
    assert_eq!(
        c["detail"], "Slowest against usual: Riverpaw Gnoll 18 s, usual 12 s",
        "...the slowest against usual in the detail"
    );
    assert_eq!(
        c["basis"],
        format!("the strip since {}", local_hm(T0)),
        "...and its ground: the strip since the session began"
    );
    assert!(
        c["id"] == "session" && c["kind"] == "event" && c["src"] == "companion" && c["ttl"] == 600,
        "...an event card of the companion, 600 s"
    );
    let s = s.unwrap();
    assert_eq!(s["re"], 1, "the set carries the answered question's number");
    assert_eq!(
        check_assist(&s).unwrap()["re"],
        1,
        "the set is one the tool can write"
    );

    // 3. Answered once; every later set carries re.
    assert!(
        b.due(now + 2.0).is_none(),
        "the same question is not answered again"
    );
    let later = b.due(now + 70.0).unwrap();
    assert!(
        later["re"] == 1 && later["cards"][0]["id"] == "session",
        "a later set (the heartbeat) carries re and the card"
    );
    let gone = b.due(now + 700.0).unwrap();
    assert!(
        gone["cards"] == json!([]) && gone["re"] == 1,
        "the card goes after its ttl, the re stays"
    );
    b.feed(
        &obj13(
            json!({"n": 2, "topic": "session", "t": now as i64 + 800}),
            json!(1),
            Value::Null,
            "en",
        ),
        now + 800.0,
    );
    let nxt = b.due(now + 801.0).unwrap();
    assert!(
        nxt["re"] == 2 && nxt["cards"][0]["id"] == "session",
        "the next question is answered"
    );

    // 4. Nothing new while the state is not live.
    let mut b = Assistant::default();
    b.feed(&state(), T0);
    b.feed(&o13(), T0);
    b.due(T0);
    b.feed(
        &json!({"kind": "stale", "session": 4711, "seq": 1}),
        T0 + 10.0,
    );
    b.feed(&ask(1, "session", T0 + 10.0), T0 + 10.0);
    let s = b.due(T0 + 11.0);
    assert!(
        s.is_none_or(|s| s["re"].is_null() && s["cards"] == json!([])),
        "while the reader says stale a question is not answered"
    );
    b.feed(&state(), T0 + 20.0);
    assert!(
        b.due(T0 + 21.0).is_some_and(|s| s["re"] == 1),
        "...and live again within 60 s it is"
    );
    let mut b = Assistant::default();
    b.feed(
        &json!({"kind": "snapshot", "condition": "waiting", "state": null, "objects": {}}),
        T0,
    );
    b.feed(&ask(1, "session", T0), T0);
    assert!(
        b.due(T0 + 1.0).is_none(),
        "with no live state there is no session and no set"
    );

    // 5. A question older than 60 s; another topic.
    let mut b = Assistant::default();
    b.feed(&state(), T0);
    b.feed(&ask(1, "session", T0 - 61.0), T0);
    let s = b.due(T0).unwrap();
    assert!(
        s["re"].is_null() && s["cards"] == json!([]),
        "a question asked 61 s ago is not answered"
    );
    b.feed(&ask(2, "weather", T0), T0 + 1.0);
    let s = b.due(T0 + 2.0);
    assert!(
        s.is_none_or(|s| s["re"].is_null() && s["cards"] == json!([])),
        "a topic it does not know is not answered"
    );

    // 6. Started again: re from object 13; no question answered twice.
    let mut b = Assistant::default();
    let text = obj13(
        json!({"n": 4, "topic": "session", "t": T0 as i64 - 10}),
        json!(4),
        json!(9),
        "en",
    )["text"]
        .clone();
    b.feed(&json!({"kind": "snapshot", "condition": "live", "state": state(), "objects": {"13": {"format": 1, "stale": false, "text": text}}}), T0);
    let s = b.due(T0).unwrap();
    assert!(
        s["re"] == 4 && s["cards"] == json!([]),
        "started again, it takes re from object 13 and answers no question twice"
    );
    assert!(
        s["seq"].as_i64().unwrap() >= 9,
        "...and its seq follows the one the game holds"
    );

    // 7. A new UI session (a reload) starts the counts again.
    let mut b = Assistant::default();
    b.feed(&state_of(1, (14, 1000, 9000), 7800), T0);
    b.feed(&o13(), T0);
    b.feed(&fight("hf1-x", 10, 12, false, "Defias Thug"), T0);
    b.feed(&state_of(2, (14, 1000, 9000), 7800), T0 + 5.0);
    b.feed(&ask(1, "session", T0 + 5.0), T0 + 5.0);
    let s = b.due(T0 + 6.0).unwrap();
    assert!(
        s["session"] == 2
            && s["cards"][0]["text"]
                .as_str()
                .unwrap()
                .starts_with("This session: 0 fights, 0 deaths"),
        "a new UI session: the set is for it, and its counts start again"
    );
    let mut b = Assistant::default();
    b.feed(&state(), T0);
    b.feed(
        &obj13(
            json!({"n": 1, "topic": "session", "t": T0 as i64}),
            Value::Null,
            Value::Null,
            "yue",
        ),
        T0,
    );
    let s = b.due(T0).unwrap();
    assert!(
        s["cards"][0]["text"]
            .as_str()
            .unwrap()
            .starts_with("今次："),
        "the card is in the player's language"
    );
    assert!(
        money_text(0) == "0 c" && money_text(5) == "+5 c" && money_text(-12345) == "-1 g 23 s 45 c",
        "money: copper, silver, gold, and a loss"
    );

    // Review round 1 (#134): a reload after an answer; revisions of a fight.
    let mut b = Assistant::default();
    b.feed(&state_of(1, (14, 1000, 9000), 7800), T0);
    b.feed(&ask(1, "session", T0), T0);
    assert!(
        b.due(T0).is_some_and(|s| s["re"] == 1),
        "session 1: question 1 answered"
    );
    b.feed(&state_of(2, (14, 1000, 9000), 7800), T0 + 10.0);
    assert!(
        b.due(T0 + 11.0).is_none(),
        "a reload: no set before the new session's object 13 is read (no old re carried)"
    );
    b.feed(&ask(1, "session", T0 + 12.0), T0 + 12.0);
    let s = b.due(T0 + 12.0).unwrap();
    assert!(
        s["session"] == 2 && s["re"] == 1 && s["cards"] != json!([]),
        "...then the new session's question 1 is answered"
    );
    let mut b = Assistant::default();
    b.feed(&state(), T0);
    b.feed(&o13(), T0);
    b.feed(&fight("hf1-r-1", 12, 15, false, "Defias Thug"), T0);
    b.feed(&fight("hf1-r-1", 12, 15, true, "Defias Thug"), T0 + 1.0);
    b.feed(&fight("hf1-r-2", 30, 10, false, "Gone Boar"), T0 + 2.0);
    b.feed(&json!({"kind": "object", "id": 12, "format": 1, "text": json!({"fight": "hf1-r-2", "rev": 2, "counted": false}).to_string()}), T0 + 3.0);
    b.feed(&ask(1, "session", T0 + 4.0), T0 + 4.0);
    let c = card(&b.due(T0 + 4.0));
    assert!(
        c["text"]
            .as_str()
            .unwrap()
            .starts_with("This session: 1 fight, 1 death")
            && c.get("detail").is_none(),
        "a fight by its last revision: a death added later counts; a fight that no longer counts goes"
    );
}

/// tools/assistant.py's Assistant, one step a line on its stdin: `["new"]`, `["feed", event,
/// now]` or `["due", now]`; a due's set comes back as a JSON line.
struct PyAssistant {
    child: std::process::Child,
    out: BufReader<std::process::ChildStdout>,
}

impl PyAssistant {
    fn start() -> PyAssistant {
        let code = format!(
            "import sys, json\nsys.path.insert(0, {TOOLS:?})\nimport assistant as A\nb = None\n\
             for line in sys.stdin:\n    s = json.loads(line)\n    if s[0] == 'new': b = A.Assistant()\n    \
             elif s[0] == 'feed': b.feed(s[1], s[2])\n    else: print(json.dumps(b.due(s[1])), flush=True)\n"
        );
        let mut child = Command::new("python3")
            .args(["-c", &code])
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .spawn()
            .unwrap();
        let out = BufReader::new(child.stdout.take().unwrap());
        PyAssistant { child, out }
    }

    fn send(&mut self, step: &Value) {
        writeln!(self.child.stdin.as_mut().unwrap(), "{step}").unwrap();
    }

    fn due(&mut self, now: f64) -> Option<Value> {
        self.send(&json!(["due", now]));
        let mut line = String::new();
        self.out.read_line(&mut line).unwrap();
        let v: Value = serde_json::from_str(&line).unwrap();
        (!v.is_null()).then_some(v)
    }
}

impl Drop for PyAssistant {
    fn drop(&mut self) {
        let _ = self.child.kill();
        let _ = self.child.wait();
    }
}

#[test]
fn the_same_sets_as_the_python_program() {
    // every run of the Python test, and more: odd names, a fight with no times, a snapshot's
    // objects in the order of their ids as text, a level up and a loss of money
    let mut runs: Vec<Vec<(Value, f64)>> = vec![];
    let mut long = vec![
        (state_of(4711, (14, 1000, 9000), 7800), T0),
        (o13(), T0),
        (fight("a", 12, 15, false, "Defias Thug"), T0 + 300.0),
        (fight("b", 18, 12, true, "Riverpaw Gnoll"), T0 + 600.0),
        (fight("c", 20, 14, false, ""), T0 + 700.0),
        (fight("d", 26, 20, false, "Tie"), T0 + 800.0),
        (
            json!({"kind": "object", "id": 12, "format": 1, "text": json!({"fight": "e", "counted": true, "name": 7, "dur": null}).to_string()}),
            T0 + 900.0,
        ),
        (state_of(4711, (14, 8500, 9000), 3000), T0 + 1800.0),
        (state_of(4711, (15, 500, 9800), 2950), T0 + 2100.0),
        (ask(1, "session", T0 + 2095.0), T0 + 2100.0),
    ];
    runs.push(long.clone());
    long.push((
        obj13(
            json!({"n": 2, "topic": "session", "t": T0 as i64 + 2500}),
            json!(1),
            json!(30),
            "yue",
        ),
        T0 + 2500.0,
    ));
    runs.push(long);
    let text = obj13(
        json!({"n": 4, "topic": "session", "t": T0 as i64 - 10}),
        json!(4),
        json!(9),
        "en",
    )["text"]
        .clone();
    runs.push(vec![(
        json!({"kind": "snapshot", "condition": "live", "state": state(), "objects": {
            "13": {"format": 1, "stale": false, "text": text},
            "12": {"format": 1, "stale": false, "text": json!({"fight": "s", "counted": true, "name": "Snap", "dur": [9, 3, 5], "died": [true]}).to_string()},
            "2": {"format": 255, "stale": true, "text": null}}}),
        T0,
    )]);
    runs.push(vec![
        (state(), T0),
        (o13(), T0),
        (json!({"kind": "stale"}), T0 + 10.0),
        (ask(1, "session", T0 + 10.0), T0 + 10.0),
        (state(), T0 + 20.0),
    ]);
    runs.push(vec![
        (state_of_money(1, (14, 1, 9)), T0),
        (ask(1, "session", T0), T0),
        (state_of_money(2, (14, 1, 9)), T0 + 10.0),
        (ask(1, "session", T0 + 12.0), T0 + 12.0),
    ]);
    let mut py = PyAssistant::start();
    for (r, run) in runs.iter().enumerate() {
        py.send(&json!(["new"]));
        let mut rs = Assistant::default();
        for (i, (e, now)) in run.iter().enumerate() {
            py.send(&json!(["feed", e, now]));
            rs.feed(e, *now);
            for later in [0.0, 1.0, 61.0, 700.0] {
                let at = now + later + i as f64 * 0.001;
                assert_eq!(
                    rs.due(at),
                    py.due(at),
                    "run {r}, step {i}, at +{later} s: the same set as the Python program"
                );
            }
        }
    }
}

fn state_of_money(session: i64, level: (i64, i64, i64)) -> Value {
    state_of(session, level, 7800)
}

fn wall() -> f64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs_f64()
}

fn addons(name: &str, n: usize) -> PathBuf {
    let dir = Path::new(env!("CARGO_TARGET_TMPDIR")).join(format!("assistant-{name}"));
    let _ = fs::remove_dir_all(&dir);
    for i in 1..=n {
        let slot = dir.join(format!("HelloLink_S{i:03}"));
        fs::create_dir_all(&slot).unwrap();
        fs::write(slot.join("Inbox.lua"), inbox_file(0, "", n, None, None, 0)).unwrap();
    }
    dir
}

/// A stand-in for the reader's API on a free port: each connection to /events gets what
/// `answer` writes for its number (from 1); the connections are counted.
fn reader(
    answer: impl Fn(usize, &mut std::net::TcpStream) + Send + Sync + 'static,
) -> (String, Arc<Mutex<usize>>) {
    let listener = TcpListener::bind("127.0.0.1:0").unwrap();
    let url = format!("http://{}", listener.local_addr().unwrap());
    let calls = Arc::new(Mutex::new(0));
    let (c, answer) = (Arc::clone(&calls), Arc::new(answer));
    thread::spawn(move || {
        for stream in listener.incoming().flatten() {
            let n = {
                let mut c = c.lock().unwrap();
                *c += 1;
                *c
            };
            let answer = Arc::clone(&answer);
            thread::spawn(move || {
                let mut stream = stream;
                let mut head = [0; 1024];
                let _ = stream.read(&mut head);
                let _ =
                    stream.write_all(b"HTTP/1.0 200 OK\r\nContent-Type: text/event-stream\r\n\r\n");
                answer(n, &mut stream);
            });
        }
    });
    (url, calls)
}

#[test]
fn the_whole_program() {
    // 8. A stand-in reader and a scratch AddOns folder.
    let dir = addons("whole", 3);
    let now = wall() as i64;
    let text = obj13(
        json!({"n": 1, "topic": "session", "t": now}),
        Value::Null,
        json!(1),
        "en",
    )["text"]
        .clone();
    let feed = vec![
        json!({"kind": "snapshot", "condition": "live", "state": state_of_money(21517, (14, 1000, 9000)), "levels": {}, "objects": {
            "13": {"format": 1, "stale": false, "text": text}}, "age": 0.1}),
        fight("hf1-z-1", 20, 12, false, "Kobold Vermin"),
    ];
    let (url, _) = reader(move |_, s| {
        for e in &feed {
            if write!(s, "data: {e}\n\n").is_err() {
                return;
            }
            thread::sleep(Duration::from_millis(200));
        }
        for _ in 0..20 {
            if s.write_all(b": alive\n\n").is_err() {
                return;
            }
            thread::sleep(Duration::from_millis(200));
        }
    });
    let log = dir.join("sets.jsonl");
    run(
        &dir,
        &url,
        Some(&log),
        &Pace {
            until: Some(wall() + 3.0),
            ..Pace::default()
        },
    )
    .unwrap();
    let slot = fs::read_to_string(dir.join("HelloLink_S002/Inbox.lua")).unwrap();
    assert!(
        slot.contains("assist = { session = 21517, seq = ")
            && slot.contains(", re = 1,")
            && slot.contains("id = \"session\""),
        "the program writes the set into every slot, for the session, answering the question ({slot})"
    );
    let lines: Vec<Value> = fs::read_to_string(&log)
        .unwrap()
        .lines()
        .map(|l| serde_json::from_str(l).unwrap())
        .collect();
    assert!(
        !lines.is_empty() && lines[0]["re"] == 1,
        "--log has each set written"
    );
    assert!(
        lines.len() == 1 && lines[0]["cards"].as_array().unwrap().len() == 1,
        "it answered once in the run: one set with the card, re 1 in every set ({lines:?})"
    );

    // 9. The reader goes away: the heartbeat goes on; a closed stream is not tried again at once.
    let first = json!({"kind": "snapshot", "condition": "live", "state": state_of_money(21517, (14, 1000, 9000)), "objects": {
        "13": {"format": 1, "stale": false, "text": obj13(Value::Null, Value::Null, json!(1), "en")["text"]}}});
    let (url, calls) = reader(move |n, s| {
        if n == 1 {
            let _ = write!(s, "data: {first}\n\n"); // the first time: the present, then the stream ends
        }
    });
    let log = dir.join("offline.jsonl");
    let pace = Pace {
        heartbeat: 1.0,
        retry: 0.5,
        until: Some(wall() + 3.5),
    };
    run(&dir, &url, Some(&log), &pace).unwrap();
    let sets = fs::read_to_string(&log)
        .map(|t| t.lines().count())
        .unwrap_or(0);
    assert!(
        sets >= 3,
        "with the reader's stream ended the program still writes a set about every heartbeat ({sets})"
    );
    let calls = *calls.lock().unwrap();
    assert!(
        (2..=9).contains(&calls),
        "...and does not try the stream again at once (a pause between tries) ({calls})"
    );
}

#[test]
fn a_log_line_as_the_python_program_writes_it() {
    let dir = addons("log", 1);
    let (url, _) = reader(|_, s| {
        let text = obj13(
            json!({"n": 1, "topic": "session", "t": wall() as i64}),
            Value::Null,
            Value::Null,
            "yue",
        )["text"]
            .clone();
        let _ = write!(
            s,
            "data: {}\n\n",
            json!({"kind": "snapshot", "condition": "live", "state": state(), "objects": {"13": {"format": 1, "stale": false, "text": text}}})
        );
        thread::sleep(Duration::from_secs(2));
    });
    let log = dir.join("log.jsonl");
    run(
        &dir,
        &url,
        Some(&log),
        &Pace {
            until: Some(wall() + 1.0),
            ..Pace::default()
        },
    )
    .unwrap();
    let line = fs::read_to_string(&log).unwrap();
    assert!(
        line.is_ascii() && line.contains("\\u4eca\\u6b21") && line.contains("\"written\": "),
        "a log line is JSON as Python writes it: ASCII, with the time it was written ({line})"
    );
}
