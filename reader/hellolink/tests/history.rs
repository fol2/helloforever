//! The saved data reader and the history's usual time (docs/specs/331.md).

use hellolink::history::{History, read_str};

fn fixture() -> String {
    std::fs::read_to_string(concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/tests/history/HelloForever.lua"
    ))
    .unwrap()
}

fn expected() -> String {
    std::fs::read_to_string(concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/tests/history/expected.json"
    ))
    .unwrap()
    .trim_end()
    .to_string()
}

fn err(text: &str) -> String {
    match read_str(text) {
        Ok(_) => panic!("read, but should fail:\n{text}"),
        Err(e) => e,
    }
}

#[test]
fn the_hand_written_file_gives_the_expected_summary() {
    let h = read_str(&fixture()).unwrap();
    assert_eq!(h.summary().to_string(), expected());
}

#[test]
fn crlf_line_ends_read_the_same() {
    let h = read_str(&fixture().replace('\n', "\r\n")).unwrap();
    assert_eq!(h.summary().to_string(), expected());
}

#[test]
fn the_usual_time_joins_the_character_by_guid_and_its_records_with_no_guid_by_name() {
    let h: History = read_str(&fixture()).unwrap();
    // FakeHunter-TestRealm (10, 20, 30; the reset and the approximate pull left out; 0 unknown)
    // and FakeHunter- with no guid (12): the median of 10, 12, 20, 30
    assert_eq!(
        h.usual(
            "Player-1-0000ABCD",
            "FakeHunter",
            "1984:14",
            "hf1-0000abcd-1794999999-1-1"
        ),
        Some((16, 4))
    );
    // the fight itself is left out by its key: 12, 20, 30
    assert_eq!(
        h.usual(
            "Player-1-0000ABCD",
            "FakeHunter",
            "1984:14",
            "hf1-0000abcd-1794000200-4-1"
        ),
        Some((20, 3))
    );
    // under 3 known times there is no usual time
    assert_eq!(
        h.usual("Player-1-0000ABCD", "FakeHunter", "740:14", ""),
        None
    );
    // a record with another guid is never joined, even with the same name
    assert_eq!(
        h.usual("Player-1-0000FFFF", "FakeHunter", "1984:14", ""),
        None
    );
    // an unknown guid takes only the records with no guid of that name: one fight
    assert_eq!(
        h.usual("Player-1-00001234", "FakeHunter", "1984:14", ""),
        None
    );
    assert_eq!(h.usual("Player-1-0000ABCD", "FakeHunter", "9:9", ""), None);
}

#[test]
fn a_file_cut_short_is_refused() {
    let text = fixture();
    let cut = &text[..text.len() / 2];
    assert!(err(cut).contains("cut short"), "{}", err(cut));
    assert!(err("HelloForeverDB = {").contains("cut short"));
    assert!(err("HelloForeverDB = \"abc").contains("cut short"));
}

#[test]
fn what_the_subset_does_not_know_is_refused_with_the_place() {
    let e = err("HelloForeverDB = {\n[\"a\"] = 1/0,\n}\n");
    assert!(e.contains("line 2"), "{e}");
    let e = err("HelloForeverDB = {\n[\"a\"] = inf,\n}\n");
    assert!(e.contains("line 2"), "{e}");
    let e = err("HelloForeverDB = { [\"a\"] = \"x\\q\" }");
    assert!(e.contains("line 1"), "{e}");
    let e = err("HelloForeverDB = { 1 2 }");
    assert!(e.contains("line 1"), "{e}");
    assert!(err("").contains("HelloForeverDB"));
}

fn one_blob(blob: &str, filed: &str) -> String {
    format!(
        "HelloForeverDB = {{ [\"characters\"] = {{ [\"FakeHunter-TestRealm\"] = {{ [\"fightLog\"] = {{ \
         [\"days\"] = {{ [\"2026-11-01\"] = {{ [\"keys\"] = {{ \"{filed}\" }}, [\"data\"] = {{ \"{blob}\" }} }} }} }} }} }} }}"
    )
}

#[test]
fn a_bad_blob_is_refused_with_the_character_the_day_and_the_key() {
    let key = "hf1-0000abcd-1794000200-4-1";
    for blob in [
        "x1:{}",            // an unknown prefix
        "d1:AdEA!!!!",      // not Base64
        "d1:AdEALv97Im==",  // a Deflate stream that does not end (valid Base64)
        "j1:{\\\"key\\\":", // JSON that does not parse
    ] {
        let e = err(&one_blob(blob, key));
        for part in ["FakeHunter-TestRealm", "2026-11-01", key] {
            assert!(e.contains(part), "{blob}: {e}");
        }
    }
    // a record filed under another key
    let e = err(&one_blob(
        "j1:{\\\"key\\\":\\\"hf1-0000abcd-1794000300-5-1\\\"}",
        key,
    ));
    assert!(e.contains(key) && e.contains("filed"), "{e}");
}

#[test]
fn keys_and_data_of_different_lengths_are_refused() {
    let text = "HelloForeverDB = { [\"characters\"] = { [\"A-\"] = { [\"fightLog\"] = { [\"days\"] = \
                { [\"2026-11-01\"] = { [\"keys\"] = { \"k1\", \"k2\" }, [\"data\"] = { \"j1:{}\" } } } } } } }";
    let e = err(text);
    assert!(e.contains("2026-11-01"), "{e}");
}
