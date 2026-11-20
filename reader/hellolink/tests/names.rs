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
    let args = parse_watch(&["--names".into(), "/tmp/x.json".into()]).unwrap();
    assert_eq!(args.names, Some(PathBuf::from("/tmp/x.json")));
}
