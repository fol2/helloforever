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
            Some("Player-1-0000ABCD"),
            "FakeHunter",
            "1984:14",
            "hf1-0000abcd-1794999999-1-1"
        ),
        Some((16, 4))
    );
    // the fight itself is left out by its key: 12, 20, 30
    assert_eq!(
        h.usual(
            Some("Player-1-0000ABCD"),
            "FakeHunter",
            "1984:14",
            "hf1-0000abcd-1794000200-4-1"
        ),
        Some((20, 3))
    );
    // under 3 known times there is no usual time
    assert_eq!(
        h.usual(Some("Player-1-0000ABCD"), "FakeHunter", "740:14", ""),
        None
    );
    // a record with another guid is never joined, even with the same name
    assert_eq!(
        h.usual(Some("Player-1-0000FFFF"), "FakeHunter", "1984:14", ""),
        None
    );
    // an unknown guid takes only the records with no guid of that name: one fight
    assert_eq!(
        h.usual(Some("Player-1-00001234"), "FakeHunter", "1984:14", ""),
        None
    );
    assert_eq!(
        h.usual(Some("Player-1-0000ABCD"), "FakeHunter", "9:9", ""),
        None
    );
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
    let e = err("HelloForeverDB = { [\"a\"] = \"x\\300\" }");
    assert!(e.contains("line 1") && e.contains("255"), "{e}");
    let e = err("HelloForeverDB = {\n[\"a\"] = 1e309,\n}");
    assert!(e.contains("line 2") && e.contains("finite"), "{e}");
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
    // the fixture's d1: blob, and two bytes after its Deflate end ("{}" in a stored block)
    let good = "AdEALv97ImtleSI6ImhmMS0wMDAwYWJjZC0xNzk0MDAwMTAwLTMtMSIsInJldiI6MSwiZHVyIjoxMiwibHZsIjoxNCwicHVsbCI6eyJzdGFydCI6eyJsZXZlbCI6MTR9LCJzdG9wIjp7ImxldmVsIjoxNH19LCJ0eXBlcyI6eyJFbmVteURhbWFnZVRha2VuIjp7ImNvbWJhdFNvdXJjZXMiOlt7InNvdXJjZUNyZWF0dXJlSUQiOjE5ODQsIm5hbWUiOiJEZWZpYXMgVGh1ZyJ9XX19fQ==";
    let bad_pad = good.replace("fQ==", "fR==");
    let after_end = format!("d1:{}fXt9", &good[..good.len() - 4]); // the last 4: "}" becomes "}{}"
    for (blob, why) in [
        ("x1:{}", "prefix"),                  // an unknown prefix
        ("d1:AdEA!!!!", "Base64"),            // not Base64
        (&format!("d1:{bad_pad}"), "Base64"), // padding bits that are not zero
        ("d1:AdEALv97", "does not end"),      // a stored block cut after its first byte
        (&after_end, "after the end"),        // bytes after the Deflate stream
        ("j1:{\\\"key\\\":", "JSON"),         // JSON that does not parse
    ] {
        let e = err(&one_blob(blob, key));
        assert!(e.contains(why), "{blob}: {e}");
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

/// One character record: `(key, guid, reset, fights)`, each fight `(start, rev, dur)` against the
/// Thug at 14 as a `j1:` blob, all on one day.
type Record<'a> = (&'a str, Option<&'a str>, Option<i64>, &'a [(i64, i64, i64)]);

fn file_of(records: &[Record]) -> String {
    let mut out = String::from("HelloForeverDB = {\n[\"characters\"] = {\n");
    for (name, guid, reset, fights) in records {
        out += &format!("[\"{name}\"] = {{\n");
        if let Some(g) = guid {
            out += &format!("[\"guid\"] = \"{g}\",\n");
        }
        if let Some(r) = reset {
            out += &format!("[\"baselineResetAt\"] = {r},\n");
        }
        let key = |s: i64| format!("hf1-0000abcd-{s}-1-1");
        let keys: Vec<String> = fights
            .iter()
            .map(|(s, _, _)| format!("\"{}\"", key(*s)))
            .collect();
        let data: Vec<String> = fights
            .iter()
            .map(|(s, rev, dur)| {
                let rec = format!(
                    r#"{{"key":"{}","rev":{rev},"dur":{dur},"lvl":14,"pull":{{"start":{{"level":14}}}},"types":{{"EnemyDamageTaken":{{"combatSources":[{{"sourceCreatureID":1984,"name":"Defias Thug"}}]}}}}}}"#,
                    key(*s)
                );
                format!("\"j1:{}\"", rec.replace('"', "\\\""))
            })
            .collect();
        out += &format!(
            "[\"fightLog\"] = {{ [\"days\"] = {{ [\"2026-11-01\"] = {{ [\"keys\"] = {{ {} }}, [\"data\"] = {{ {} }} }} }} }},\n}},\n",
            keys.join(", "),
            data.join(", ")
        );
    }
    out + "},\n}\n"
}

const G: Option<&str> = Some("Player-1-0000ABCD");

#[test]
fn a_fight_in_both_records_counts_once_by_its_highest_revision() {
    // the same fight: rev 1 (8 s) in FakeHunter-, rev 2 (40 s) in FakeHunter-TestRealm
    let h = read_str(&file_of(&[
        ("FakeHunter-", None, None, &[(1794000100, 1, 8)]),
        (
            "FakeHunter-TestRealm",
            G,
            None,
            &[
                (1794000100, 2, 40),
                (1794000200, 1, 10),
                (1794000300, 1, 20),
            ],
        ),
    ]))
    .unwrap();
    assert_eq!(h.usual(G, "FakeHunter", "1984:14", ""), Some((20, 3)));
    // and the other way round: the record read first holds the higher revision
    let h = read_str(&file_of(&[
        ("FakeHunter-", None, None, &[(1794000100, 2, 40)]),
        (
            "FakeHunter-TestRealm",
            G,
            None,
            &[(1794000100, 1, 8), (1794000200, 1, 10), (1794000300, 1, 20)],
        ),
    ]))
    .unwrap();
    assert_eq!(h.usual(G, "FakeHunter", "1984:14", ""), Some((20, 3)));
}

#[test]
fn the_reset_of_one_record_applies_to_every_record_of_the_character() {
    let h = read_str(&file_of(&[
        (
            "FakeHunter-",
            None,
            None,
            &[
                (1794000100, 1, 10),
                (1794000200, 1, 12),
                (1794000300, 1, 14),
            ],
        ),
        (
            "FakeHunter-TestRealm",
            G,
            Some(1794000500),
            &[(1794000600, 1, 40)],
        ),
    ]))
    .unwrap();
    assert_eq!(h.usual(G, "FakeHunter", "1984:14", ""), None);
    // each record's own summary keeps its own reset
    assert_eq!(h.summary()["FakeHunter-"]["counted"], 3);
}

#[test]
fn a_null_guid_joins_the_records_with_no_guid_by_name() {
    let h = read_str(&file_of(&[
        (
            "FakeHunter-",
            None,
            None,
            &[
                (1794000100, 1, 10),
                (1794000200, 1, 12),
                (1794000300, 1, 14),
            ],
        ),
        ("FakeHunter-TestRealm", G, None, &[(1794000600, 1, 40)]),
    ]))
    .unwrap();
    assert_eq!(h.usual(None, "FakeHunter", "1984:14", ""), Some((12, 3)));
    assert_eq!(h.usual(None, "Other", "1984:14", ""), None);
}

#[test]
fn a_gap_in_the_keys_or_the_data_is_refused() {
    let text = file_of(&[("A-", None, None, &[(1794000100, 1, 10)])])
        .replace(
            "[\"keys\"] = { ",
            "[\"keys\"] = { [3] = \"hf1-0000abcd-1794000300-1-1\", ",
        )
        .replace("[\"data\"] = { ", "[\"data\"] = { [3] = \"bad\", ");
    let e = err(&text);
    assert!(e.contains("2026-11-01") && e.contains("list"), "{e}");
}

#[test]
fn a_false_stop_level_and_a_name_that_is_not_text_fall_back_as_the_addon_does() {
    let text = file_of(&[("A-", None, None, &[(1794000100, 1, 10)])])
        .replace("\\\"pull\\\":{\\\"start\\\":{\\\"level\\\":14}}", "\\\"pull\\\":{\\\"start\\\":{\\\"level\\\":14},\\\"stop\\\":{\\\"level\\\":false}},\\\"name\\\":\\\"Thug\\\"")
        .replace("\\\"name\\\":\\\"Defias Thug\\\"", "\\\"name\\\":false");
    let s = read_str(&text).unwrap().summary();
    assert_eq!(s["A-"]["counted"], 1, "{s}");
    assert_eq!(s["A-"]["keys"]["1984:14"]["name"], "Thug", "{s}");
}
