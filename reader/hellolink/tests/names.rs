//! The reader's name cache (docs/specs/213.md, section 9): object 25 of format 2 gives names by
//! (kind, id) with a hash; the reader keeps them on disk and gives them in /state.

use hellolink::api::Api;
use hellolink::follow::parse_watch;
use serde_json::{Value, json};
use std::path::PathBuf;
use std::time::Duration;

fn names_object(text: &str) -> Value {
    json!({"kind": "object", "id": 25, "format": 0, "text": text, "session": 7})
}

fn file(name: &str) -> PathBuf {
    let p = PathBuf::from(env!("CARGO_TARGET_TMPDIR")).join(name);
    let _ = std::fs::remove_file(&p);
    p
}

#[test]
fn names_of_object_25_are_kept_in_state_and_on_disk() {
    let path = file("names-kept.json");
    let mut api = Api::start(0, Duration::from_millis(200)).unwrap();
    api.keep_names(&path).unwrap();
    api.tell(&json!({"kind": "state", "session": 7, "seq": 1, "format": 2}));
    api.tell(&names_object(
        r#"{"C:740": ["Adolescent Whelp", 10475], "S:75": ["Auto Shot", 1234]}"#,
    ));
    let snap = api.snapshot();
    assert_eq!(
        snap["names"]["C:740"],
        json!(["Adolescent Whelp", 10475]),
        "{snap}"
    );
    let disk: Value = serde_json::from_str(&std::fs::read_to_string(&path).unwrap()).unwrap();
    assert_eq!(disk["S:75"], json!(["Auto Shot", 1234]));
    // a later object 25 without an entry does not drop it; a new hash replaces the name
    api.tell(&names_object(r#"{"C:740": ["Young Whelp", 999]}"#));
    let snap = api.snapshot();
    assert_eq!(snap["names"]["C:740"], json!(["Young Whelp", 999]));
    assert_eq!(snap["names"]["S:75"], json!(["Auto Shot", 1234]));
    api.close();
    // the next run starts with what is on disk
    let mut again = Api::start(0, Duration::from_millis(200)).unwrap();
    again.keep_names(&path).unwrap();
    again.tell(&json!({"kind": "state", "session": 8, "seq": 1, "format": 2}));
    assert_eq!(
        again.snapshot()["names"]["C:740"],
        json!(["Young Whelp", 999])
    );
    again.close();
}

#[test]
fn a_names_object_that_is_no_list_of_names_changes_nothing() {
    let path = file("names-bad.json");
    let mut api = Api::start(0, Duration::from_millis(200)).unwrap();
    api.keep_names(&path).unwrap();
    api.tell(&json!({"kind": "state", "session": 7, "seq": 1, "format": 2}));
    api.tell(&names_object(r#"{"C:740": ["Whelp", 1]}"#));
    for bad in [
        "not json",
        r#"{"C:740": "Whelp"}"#,
        r#"{"C:740": ["Whelp", "x"]}"#,
        r#"["C:740"]"#,
    ] {
        api.tell(&names_object(bad));
    }
    assert_eq!(api.snapshot()["names"], json!({"C:740": ["Whelp", 1]}));
    api.close();
}

#[test]
fn without_names_state_has_no_names_key() {
    let mut api = Api::start(0, Duration::from_millis(200)).unwrap();
    api.tell(&json!({"kind": "state", "session": 1, "seq": 1}));
    assert_eq!(
        api.snapshot().get("names"),
        None,
        "format 1's /state is as before"
    );
    api.close();
}

#[test]
fn watch_takes_names_file() {
    let args = parse_watch(&[
        "--names".into(),
        "/tmp/x.json".into(),
        "--serve".into(),
        "8787".into(),
    ])
    .unwrap();
    assert_eq!(args.names, Some(PathBuf::from("/tmp/x.json")));
}

#[test]
fn names_need_serve() {
    let e = parse_watch(&["--names".into(), "/tmp/x.json".into()]).unwrap_err();
    assert!(e.contains("--serve"), "{e}");
    assert!(parse_watch(&["--names=/tmp/x".into(), "--serve=0".into()]).is_err());
}

#[test]
fn a_names_object_with_one_bad_entry_changes_nothing_in_memory_or_on_disk() {
    let path = file("names-mixed.json");
    let mut api = Api::start(0, Duration::from_millis(200)).unwrap();
    api.keep_names(&path).unwrap();
    api.tell(&json!({"kind": "state", "session": 7, "seq": 1, "format": 2}));
    api.tell(&names_object(r#"{"C:740": ["Whelp", 1]}"#));
    let before = std::fs::read_to_string(&path).unwrap();
    api.tell(&names_object(r#"{"C:740": ["Other", 2], "S:1": "bad"}"#));
    assert_eq!(api.snapshot()["names"], json!({"C:740": ["Whelp", 1]}));
    assert_eq!(std::fs::read_to_string(&path).unwrap(), before);
    api.close();
}

#[test]
fn a_cache_file_with_a_bad_entry_is_refused() {
    let path = file("names-badfile.json");
    std::fs::write(&path, r#"{"C:740": null}"#).unwrap();
    let mut api = Api::start(0, Duration::from_millis(200)).unwrap();
    assert!(api.keep_names(&path).is_err());
    api.close();
}

#[test]
fn format_1s_state_over_http_has_no_names_though_the_cache_holds_some() {
    use std::io::{Read, Write};
    let path = file("names-format1.json");
    std::fs::write(&path, r#"{"C:740": ["Whelp", 1]}"#).unwrap();
    let mut api = Api::start(0, Duration::from_millis(200)).unwrap();
    api.keep_names(&path).unwrap();
    api.tell(&json!({"kind": "state", "session": 1, "seq": 1}));
    let mut s = std::net::TcpStream::connect(("127.0.0.1", api.port)).unwrap();
    s.write_all(b"GET /state HTTP/1.0\r\nHost: 127.0.0.1\r\n\r\n")
        .unwrap();
    let mut body = String::new();
    s.read_to_string(&mut body).unwrap();
    assert!(!body.contains("names"), "{body}");
    api.tell(&json!({"kind": "state", "session": 1, "seq": 2, "format": 2}));
    assert_eq!(api.snapshot()["names"]["C:740"], json!(["Whelp", 1]));
    api.close();
}
