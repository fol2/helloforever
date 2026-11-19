//! The slot writer (`hellolink write`, src/slots.rs) against bytes written out by hand from
//! tools/hellolink.py, against the Python checks (tests/strip_watch_test.py and
//! tests/hellolink_assist_test.py), and against the Python tool on the same writes.

use hellolink::slots::{check_assist, inbox_file, lua_string, strip_ask, write};
use serde_json::{Value, json};
use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::process::{Command, Output, Stdio};

const READER: &str = env!("CARGO_BIN_EXE_hellolink");
const PY_TOOL: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/../../tools/hellolink.py");

fn folder(name: &str) -> PathBuf {
    let dir = Path::new(env!("CARGO_TARGET_TMPDIR")).join(format!("slots-{name}"));
    let _ = fs::remove_dir_all(&dir);
    fs::create_dir_all(&dir).unwrap();
    dir
}

/// `n` slots, each with the file `install` writes.
fn slots_in(name: &str, n: usize) -> PathBuf {
    let addons = folder(name);
    for i in 1..=n {
        let slot = addons.join(format!("HelloLink_S{i:03}"));
        fs::create_dir_all(&slot).unwrap();
        fs::write(slot.join("Inbox.lua"), inbox_file(0, "", n, None, None, 0)).unwrap();
    }
    addons
}

fn slot(addons: &Path, i: usize) -> String {
    let raw = fs::read(addons.join(format!("HelloLink_S{i:03}/Inbox.lua"))).unwrap();
    raw.iter().map(|&b| b as char).collect() // latin-1, as the Python checks read it
}

fn run(program: &[&str], args: &[&str], stdin: Option<&str>) -> Output {
    let mut child = Command::new(program[0])
        .args(&program[1..])
        .args(args)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .unwrap();
    let mut input = child.stdin.take().unwrap();
    input.write_all(stdin.unwrap_or("").as_bytes()).unwrap();
    drop(input);
    child.wait_with_output().unwrap()
}

fn contains(hay: &[u8], needle: &[u8]) -> bool {
    hay.windows(needle.len()).any(|w| w == needle)
}

fn rust(args: &[&str], stdin: Option<&str>) -> Output {
    run(&[READER, "write"], args, stdin)
}

fn set() -> Value {
    json!({"session": 4711, "seq": 12, "cards": [
        {"id": "c1", "kind": "next", "prio": 2, "src": "rxp", "at": 100, "ttl": 60,
         "text": "Hand in the quest", "basis": "step 4", "detail": "at the inn"}]})
}

#[test]
fn the_slot_file_as_written_out_by_hand() {
    assert_eq!(
        inbox_file(7, "hi", 3, None, None, 0),
        b"HelloLink_Inbox = { seq = 7, text = \"hi\", slots = 3 }\n"
    );
    assert_eq!(
        inbox_file(7, "hi", 3, Some(4711), None, 0),
        b"HelloLink_Inbox = { seq = 7, text = \"hi\", slots = 3, strip = { session = 4711, depth = 2 } }\n"
    );
    let a = check_assist(&json!({"session": 4711, "seq": 12, "re": 3, "cards": [
        {"text": "x", "prio": 2, "id": "a", "kind": "tip", "extra": "dropped", "ttl": null}]}))
    .unwrap();
    assert_eq!(
        inbox_file(7, "", 1, Some(9), Some(&a), 100),
        b"HelloLink_Inbox = { seq = 7, text = \"\", slots = 1, strip = { session = 9, depth = 2 }, \
          assist = { session = 4711, seq = 12, t = 100, re = 3, cards = { { id = \"a\", kind = \"tip\", \
          prio = 2, text = \"x\" } } } }\n"
            .to_vec(),
        "the fields in the spec's order; a field the spec does not have, or a null, is left out"
    );
    let empty = check_assist(&json!({"session": 1, "seq": 2, "cards": []})).unwrap();
    assert_eq!(
        inbox_file(7, "", 1, None, Some(&empty), 5),
        b"HelloLink_Inbox = { seq = 7, text = \"\", slots = 1, assist = { session = 1, seq = 2, t = 5, cards = {} } }\n"
    );
    assert_eq!(
        lua_string(b"a\"b\\c\n\x7f\xc3\xa9\xff\0"),
        b"\"a\\\"b\\\\c\\010\\127\xc3\xa9\xff\\000\"",
        "a quote and a backslash get a backslash, control bytes three digits, the rest as it is"
    );
}

#[test]
fn the_request_in_the_slots() {
    // tests/strip_watch_test.py, "the request in the slots"
    let addons = slots_in("request", 3);
    write(&addons, Some(""), Some(4711), None).unwrap();
    let s = slot(&addons, 2);
    assert!(
        s.contains("strip = { session = 4711, depth = 2 }")
            && s.starts_with("HelloLink_Inbox = { seq = "),
        "the request is written to every slot as the strip field of the spec"
    );
    write(&addons, Some("hello"), None, None).unwrap();
    let s = slot(&addons, 3);
    assert!(
        s.contains("strip = { session = 4711, depth = 2 }") && s.contains("text = \"hello\""),
        "a later write of a text keeps the request: the addon may not have looked yet"
    );
    write(&addons, Some(""), Some(4712), None).unwrap();
    let s = slot(&addons, 1);
    assert!(
        s.contains("session = 4712") && !s.contains("4711"),
        "a request for another session replaces it"
    );
    let fresh = slots_in("fresh", 2);
    write(&fresh, Some("hello"), None, None).unwrap();
    assert!(
        !slot(&fresh, 1).contains("strip"),
        "with no request there is no strip field"
    );
    // a quiet write: the library prints nothing; only the command says what it wrote
    assert!(
        strip_ask(&inbox_file(
            1,
            "\", strip = { session = 1, depth = 2 } }",
            1,
            None,
            None,
            0
        ))
        .is_none()
            && strip_ask(&inbox_file(1, "x", 1, Some(77), None, 0)) == Some(77),
        "the slot writer does not take words in a text for a request"
    );
    write(
        &fresh,
        Some("he said \", strip = { session = 1, depth = 2 } }"),
        None,
        None,
    )
    .unwrap();
    fs::remove_file(fresh.join("HelloLink_S001/.parts.json")).unwrap(); // as an old slot
    write(&fresh, Some("next"), None, None).unwrap();
    assert!(
        !slot(&fresh, 1).contains("strip"),
        "so a text that looks like a request leaves none behind"
    );
    let racers: Vec<_> = (0..16)
        .map(|i| {
            let mut c = Command::new(READER);
            c.args(["write", addons.to_str().unwrap(), &format!("text {i}")]);
            if i == 7 {
                c.args(["--strip-session", "5000"]);
            }
            c.stdout(Stdio::null()).spawn().unwrap()
        })
        .collect();
    for mut r in racers {
        assert!(r.wait().unwrap().success());
    }
    write(&addons, Some("last"), None, None).unwrap();
    assert!(
        (1..=3).all(|i| slot(&addons, i).contains("session = 5000")),
        "sixteen writers at once, one of them a request: the request is still there after all of them"
    );
}

#[test]
fn the_assist_part() {
    // tests/hellolink_assist_test.py, sections 2 and 3, through the command
    let addons = slots_in("assist", 3);
    let a = addons.to_str().unwrap();
    rust(&[a, "a question's text"], None);
    let seq = slot(&addons, 1)
        .split("seq = ")
        .nth(1)
        .unwrap()
        .split(',')
        .next()
        .unwrap()
        .to_string();
    let done = rust(&[a, "--assist", "-"], Some(&set().to_string()));
    assert!(done.status.success(), "write --assist exits 0");
    assert_eq!(
        String::from_utf8_lossy(&done.stdout).trim(),
        format!(
            "wrote {} bytes to 3 slots",
            fs::read(addons.join("HelloLink_S001/Inbox.lua"))
                .unwrap()
                .len()
        ),
        "the command says what it wrote"
    );
    let s1 = slot(&addons, 1);
    assert!(
        (1..=3).all(|i| slot(&addons, i).contains("assist = { session = 4711, seq = 12, t = ")),
        "write --assist puts the part in every slot"
    );
    assert!(
        s1.contains(&format!("seq = {seq},"))
            && s1.contains("text = \"a question's text\"")
            && s1.contains("slots = 3,"),
        "...and keeps the top seq and text"
    );
    let t: i64 = s1
        .split(", t = ")
        .nth(1)
        .unwrap()
        .split(',')
        .next()
        .unwrap()
        .parse()
        .unwrap();
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_secs() as i64;
    assert!((t - now).abs() <= 5, "...with t the time of the write");
    rust(&[a, "a new text"], None);
    let s2 = slot(&addons, 1);
    assert!(
        s2.contains(&format!("assist = {{ session = 4711, seq = 12, t = {t}"))
            && !s2.contains(&format!("seq = {seq},"))
            && s2.contains("\"a new text\""),
        "a text write carries the assist part over, and has a new seq"
    );
    let seq2 = s2
        .split("seq = ")
        .nth(1)
        .unwrap()
        .split(',')
        .next()
        .unwrap()
        .to_string();
    rust(&[a, "--strip-session", "4711"], None);
    let s3 = slot(&addons, 1);
    assert!(
        s3.contains(&format!("seq = {seq2},"))
            && s3.contains("\"a new text\"")
            && s3.contains("strip = { session = 4711, depth = 2 }")
            && s3.contains("assist = { session = 4711"),
        "a strip write keeps the top seq, the text and the assist part"
    );
    let mut empty = set();
    empty["seq"] = json!(13);
    empty["cards"] = json!([]);
    rust(&[a, "--assist", "-"], Some(&empty.to_string()));
    let s4 = slot(&addons, 1);
    assert!(
        s4.contains("strip = { session = 4711, depth = 2 }")
            && s4.contains("seq = 13, t = ")
            && s4.contains("cards = {}"),
        "an assist write keeps the strip request; an empty set is written as such"
    );

    let old = slots_in("old", 2);
    for i in 1..=2 {
        fs::write(
            old.join(format!("HelloLink_S{i:03}/Inbox.lua")),
            b"HelloLink_Inbox = { seq = 123, text = \"old \\\"q\\\" \\\\ \\195\\169 end\", strip = { session = 9, depth = 2 } }\n",
        )
        .unwrap();
    }
    let done = rust(
        &[old.to_str().unwrap(), "--assist", "-"],
        Some(&set().to_string()),
    );
    let o = slot(&old, 1);
    assert!(
        done.status.success()
            && o.contains("seq = 123,")
            && o.contains("strip = { session = 9, depth = 2 }")
            && contains(
                &fs::read(old.join("HelloLink_S001/Inbox.lua")).unwrap(),
                b"\"old \\\"q\\\" \\\\ \xc3\xa9 end\""
            ),
        "an old slot's text, its seq and its request stay through the first assist write ({o})"
    );

    let before = slot(&addons, 1);
    let card = set()["cards"][0].clone();
    let with = |k: &str, v: Value| {
        let mut s = set();
        s[k] = v;
        s.to_string()
    };
    let card_with = |k: &str, v: Value| {
        let mut c = card.clone();
        c[k] = v;
        with("cards", json!([c]))
    };
    for (label, bad) in [
        ("nine cards", with("cards", json!(vec![card.clone(); 9]))),
        (
            "a session that is no whole number",
            with("session", json!(4.5)),
        ),
        ("a card that is no table", with("cards", json!(["x"]))),
        ("a text that is a number", card_with("text", json!(7))),
        ("a prio that is a word", card_with("prio", json!("high"))),
        (
            "no cards list",
            json!({"session": 4711, "seq": 1}).to_string(),
        ),
        ("not JSON", "{".to_string()),
    ] {
        let done = rust(&[a, "--assist", "-"], Some(&bad));
        assert!(
            !done.status.success() && slot(&addons, 1) == before,
            "refused, and nothing changed: {label}"
        );
    }
    let done = rust(&[a], None);
    assert!(
        !done.status.success() && slot(&addons, 1) == before,
        "a write with nothing to write is refused"
    );
}

/// The slot files with the clock's numbers (the top seq, `t`) taken out.
fn timeless(addons: &Path, n: usize) -> Vec<String> {
    (1..=n)
        .map(|i| {
            let s = slot(addons, i);
            let (head, rest) = s.split_once(", text = ").unwrap();
            assert!(head.starts_with("HelloLink_Inbox = { seq = "));
            let rest = match rest.split_once(", t = ") {
                Some((a, b)) => format!("{a}, t = T{}", &b[b.find(',').unwrap()..]),
                None => rest.to_string(),
            };
            format!("HelloLink_Inbox = {{ seq = N, text = {rest}")
        })
        .collect()
}

#[test]
fn the_same_slot_files_as_the_python_tool() {
    let hard = "say \"hi\" \\ back ]] end --[[ x\nline two\r nul é 你好 \u{7f}";
    let mut odd = set();
    odd["cards"][0]["text"] = json!("a \"quote\" ]] and \\ and\nbreak");
    odd["cards"][0]["basis"] = json!("é ]=] [[x]]");
    odd["re"] = json!(11);
    let mut empty = set();
    empty["cards"] = json!([]);
    let steps: Vec<(Vec<&str>, Option<String>)> = vec![
        (vec!["a question's text"], None),
        (vec!["--assist", "-"], Some(set().to_string())),
        (vec![hard], None),
        (vec!["--strip-session", "4711"], None),
        (vec!["--assist", "-"], Some(odd.to_string())),
        (vec!["-"], Some("from stdin\n".into())),
        (vec!["--assist", "-"], Some(empty.to_string())),
        (vec!["", "--strip-session", "4712"], None),
    ];
    let py = slots_in("py", 3);
    let rs = slots_in("rs", 3);
    let mixed = slots_in("mixed", 3);
    for (i, (args, stdin)) in steps.iter().enumerate() {
        for (addons, by_python) in [(&py, true), (&rs, false), (&mixed, i % 2 == 0)] {
            let dir = addons.to_str().unwrap();
            let all: Vec<&str> = [dir].into_iter().chain(args.iter().copied()).collect();
            let done = if by_python {
                run(&["python3", PY_TOOL, "write"], &all, stdin.as_deref())
            } else {
                rust(&all, stdin.as_deref())
            };
            assert!(
                done.status.success(),
                "step {i}: {}",
                String::from_utf8_lossy(&done.stderr)
            );
            assert_eq!(
                String::from_utf8_lossy(&done.stdout),
                format!(
                    "wrote {} bytes to 3 slots\n",
                    fs::read(addons.join("HelloLink_S001/Inbox.lua"))
                        .unwrap()
                        .len()
                ),
                "step {i}: what the command says"
            );
        }
        assert_eq!(
            timeless(&rs, 3),
            timeless(&py, 3),
            "step {i}: the Rust writer's slot files are the Python tool's"
        );
        assert_eq!(
            timeless(&mixed, 3),
            timeless(&py, 3),
            "step {i}: the two tools in turn on one folder carry each other's parts over"
        );
    }
}

// --- review round 1 of #204 ---

#[test]
fn the_slot_files_are_the_players_only() {
    use std::os::unix::fs::PermissionsExt;
    let (py, rs) = (slots_in("mode-py", 1), slots_in("mode-rs", 1));
    run(
        &["python3", PY_TOOL, "write"],
        &[py.to_str().unwrap(), "x"],
        None,
    );
    rust(&[rs.to_str().unwrap(), "x"], None);
    for file in ["HelloLink_S001/Inbox.lua", "HelloLink_S001/.parts.json"] {
        let mode = |dir: &Path| fs::metadata(dir.join(file)).unwrap().permissions().mode() & 0o777;
        assert_eq!(
            (mode(&rs), mode(&py)),
            (0o600, 0o600),
            "{file}: 0600, as the Python tool's mkstemp"
        );
    }
}

#[test]
fn python_and_rust_writers_at_once_share_one_lock() {
    let addons = slots_in("mixed-race", 3);
    let dir = addons.to_str().unwrap().to_string();
    let racers: Vec<_> = (0..24)
        .map(|i| {
            let text = format!("text {i}");
            let mut args = vec![dir.as_str(), text.as_str()];
            if i == 11 {
                args.extend(["--strip-session", "5000"]);
            }
            let mut c = if i % 2 == 0 {
                let mut c = Command::new("python3");
                c.args([PY_TOOL, "write"]);
                c
            } else {
                let mut c = Command::new(READER);
                c.arg("write");
                c
            };
            c.args(&args).stdout(Stdio::null()).spawn().unwrap()
        })
        .collect();
    for mut r in racers {
        assert!(r.wait().unwrap().success());
    }
    rust(&[&dir, "last"], None);
    assert!(
        (1..=3).all(|i| slot(&addons, i).contains("session = 5000")),
        "24 writers at once, Python and Rust in turn, one of them a request: the request is still there after all of them"
    );
}

#[test]
fn a_parts_file_that_cannot_be_read_is_not_written_over() {
    let addons = slots_in("bad-parts", 2);
    let a = addons.to_str().unwrap();
    rust(&[a, "--assist", "-"], Some(&set().to_string()));
    fs::write(
        addons.join("HelloLink_S001/.parts.json"),
        b"{\"assist\": {\"cards\": [{\"ttl\": 1e999}]}}",
    )
    .unwrap();
    let before = slot(&addons, 1);
    let done = rust(&[a, "a text"], None);
    assert!(
        !done.status.success()
            && String::from_utf8_lossy(&done.stderr).contains("nothing was written")
            && slot(&addons, 1) == before,
        "a parts file the writer cannot read is refused, and the slots keep their parts ({})",
        String::from_utf8_lossy(&done.stderr)
    );
}

#[test]
fn a_writer_waits_for_the_lock_with_a_limit() {
    let addons = slots_in("held-lock", 1);
    let held = fs::File::create(addons.join("HelloLink_S001/.lock")).unwrap();
    held.lock().unwrap();
    let before = slot(&addons, 1);
    let began = std::time::Instant::now();
    let done = rust(&[addons.to_str().unwrap(), "x"], None);
    let took = began.elapsed().as_secs_f64();
    assert!(
        !done.status.success() && (9.0..14.0).contains(&took) && slot(&addons, 1) == before,
        "a lock held by another writer is waited for 10 s, then the write fails and changes nothing ({took:.1} s; {})",
        String::from_utf8_lossy(&done.stderr)
    );
}

#[test]
fn the_parts_file_is_written_as_python_writes_it() {
    // keys already in sorted order, so Python's order (the order it read) is the sorted one
    let parts = b"{\"seq\": 1, \"strip\": 4, \"text\": \"t\"}";
    let (a, b) = (slots_in("parts-rs", 1), slots_in("parts-py", 1));
    let mut written = Vec::new();
    for (addons, program) in [
        (&a, vec![READER, "write"]),
        (&b, vec!["python3", PY_TOOL, "write"]),
    ] {
        fs::write(addons.join("HelloLink_S001/.parts.json"), parts).unwrap();
        let done = run(
            &program,
            &[addons.to_str().unwrap(), "h\u{e9}llo \u{1f44d} \"q\""],
            None,
        );
        assert!(
            done.status.success(),
            "{}",
            String::from_utf8_lossy(&done.stderr)
        );
        let raw = fs::read_to_string(addons.join("HelloLink_S001/.parts.json")).unwrap();
        let seq = serde_json::from_str::<Value>(&raw).unwrap()["seq"].to_string();
        written.push(raw.replacen(&format!("\"seq\": {seq}"), "\"seq\": SEQ", 1));
    }
    // json.dumps: ", " and ": ", every character beyond ASCII as \u escapes (UTF-16 pairs)
    assert_eq!(
        written[0],
        "{\"seq\": SEQ, \"strip\": 4, \"text\": \"h\\u00e9llo \\ud83d\\udc4d \\\"q\\\"\"}"
    );
    assert_eq!(written[0], written[1]);
}
