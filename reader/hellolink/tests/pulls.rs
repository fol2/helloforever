//! `--pulls` (docs/PULLS.md, #361): the line of a pull, from the reader's events.

use hellolink::pulls::{Pulls, append, file_for, from_replay};
use serde_json::{Value, json};

/// A `state` event: the in-combat bit as asked, a position, the target's threat and a cast.
fn state(fighting: bool, x: i64) -> Value {
    json!({"kind": "state", "session": 1, "seq": x,
        "levels": {"health": 100, "power": 50, "targetHealth": 0, "petHealth": null},
        "fast": {"clock": {"clock": 1}, "state": {"flags": if fighting { 128 + 2 } else { 2 }},
            "position": {"map": 1437, "x": x, "y": 200, "facing": 64},
            "threat": {"player": 100, "pet": 40}, "cast": null}})
}

fn plates(list: Value) -> Value {
    json!({"kind": "object", "id": 24, "format": 3,
        "text": json!({"nameplates": list}).to_string()})
}

#[test]
fn a_pull_gives_one_line_by_the_format() {
    let mut p = Pulls::new("abc123");
    let t0 = 1794516378.0;
    assert_eq!(
        p.take(
            &json!({"kind": "object", "id": 10, "format": 3,
        "text": r#"{"name":"Fake","guid":"Player-1-0000ABCD"}"#}),
            t0 - 5.0
        ),
        None
    );
    assert_eq!(
        p.take(&state(false, 1), t0 - 1.0),
        None,
        "out of combat: no pull"
    );
    // ten states a second for one second: samples at 5 a second
    for i in 0..10 {
        assert_eq!(p.take(&state(true, 10 + i), t0 + i as f64 / 10.0), None);
    }
    // a fighting hostile creature on the player, a hostile one not yet in the fight, a friend
    p.take(
        &plates(json!([
            [
                "C:740:10475",
                35,
                "MAGE",
                "normal",
                2 + 4 + 8,
                "player",
                3,
                null,
                null
            ],
            ["C:741:2", 34, "WARRIOR", "elite", 4, null, 0, null, null],
            [
                "P:5:0",
                30,
                "PRIEST",
                "normal",
                2 + 8,
                null,
                null,
                null,
                null
            ]
        ])),
        t0 + 0.5,
    );
    // it goes for the pet, then dies; the other comes no nearer
    p.take(
        &plates(json!([[
            "C:740:10475",
            35,
            "MAGE",
            "normal",
            1 + 2 + 4,
            "pet",
            2,
            null,
            null
        ]])),
        t0 + 1.5,
    );
    // 2.5 s with no state: a gap
    assert_eq!(p.take(&state(true, 30), t0 + 3.5), None);
    let line = p
        .take(&state(false, 31), t0 + 4.0)
        .expect("the pull ends with the combat flag");
    let want = json!({
        "v": 1, "reader": "abc123", "char": "Player-1-0000ABCD", "t0": t0, "t1": t0 + 4.0,
        "samples": [
            [0, 1437, 10, 200, 64, 130, 100, 50, null, 0, 100, 40, null],
            [2, 1437, 12, 200, 64, 130, 100, 50, null, 0, 100, 40, null],
            [4, 1437, 14, 200, 64, 130, 100, 50, null, 0, 100, 40, null],
            [6, 1437, 16, 200, 64, 130, 100, 50, null, 0, 100, 40, null],
            [8, 1437, 18, 200, 64, 130, 100, 50, null, 0, 100, 40, null],
            [35, 1437, 30, 200, 64, 130, 100, 50, null, 0, 100, 40, null]],
        "units": [{"i": 1, "id": 740, "g": null, "lvl": 35, "cls": "normal", "seen": 5, "last": 15,
            "dead": 15, "thr": [[5, 3], [15, 2]], "thrPet": [], "tgt": [[5, "player"], [15, "pet"]]}],
        "near": [[5, 1], [15, 0]],
        "gaps": [[9, 35]],
        "gclash": false,
    });
    assert_eq!(line, want, "\n got {line}\nwant {want}");
}

#[test]
fn two_plates_of_one_creature_with_no_g_are_two_units_and_a_clash() {
    let mut p = Pulls::new("x");
    p.take(&state(true, 1), 100.0);
    let mob = |t| json!(["C:740:10475", 35, "MAGE", "normal", 6, t, 1, null, null]);
    p.take(&plates(json!([mob("player"), mob("pet")])), 100.2);
    let line = p.take(&state(false, 2), 101.0).unwrap();
    assert_eq!(line["units"].as_array().unwrap().len(), 2);
    assert_eq!(
        line["gclash"], true,
        "the reader could not tell them apart surely"
    );
    // with g (a later HelloLink: the 10th field) they are told apart: no clash
    let mut p = Pulls::new("x");
    p.take(&state(true, 1), 200.0);
    let g = |g| {
        json!([
            "C:740:10475",
            35,
            "MAGE",
            "normal",
            6,
            "player",
            1,
            null,
            null,
            g,
            0
        ])
    };
    p.take(&plates(json!([g(11), g(12)])), 200.2);
    let line = p.take(&state(false, 2), 201.0).unwrap();
    assert_eq!(line["gclash"], false);
    assert_eq!(line["units"][1]["g"], 12);
    assert_eq!(
        line["units"][1]["thrPet"],
        json!([[2, 0]]),
        "the pet's threat when sent"
    );
}

#[test]
fn a_pull_whose_end_is_not_seen_has_no_t1() {
    let mut p = Pulls::new("x");
    p.take(&state(true, 1), 100.0);
    // the reader saw nothing for over 2 minutes, then a new fight
    let lost = p
        .take(&state(true, 2), 300.0)
        .expect("the old pull is closed");
    assert_eq!(
        (lost["t0"].clone(), lost["t1"].clone()),
        (json!(100.0), Value::Null)
    );
    let end = p.end().expect("the new pull, open as the reader stops");
    assert_eq!(
        (end["t0"].clone(), end["t1"].clone()),
        (json!(300.0), Value::Null)
    );
    assert_eq!(p.end(), None);
    // a state whose flags are unknown neither starts nor ends a pull
    let mut unknown = state(true, 1);
    unknown["fast"]["state"] = Value::Null;
    assert_eq!(p.take(&unknown, 400.0), None);
    assert_eq!(p.end(), None);
}

#[test]
fn a_replay_is_timed_by_the_clients_clock() {
    // the header says 1794516300; the first capture came 78.5 s later (the reader waited), and
    // the frame's clock is time() mod 65536 for 1794516378
    let clock = 1794516378_i64 % 65536;
    let mut on = state(true, 1);
    on["fast"]["clock"]["clock"] = json!(clock);
    on["t"] = json!(10.0);
    let mut off = state(false, 2);
    off["t"] = json!(15.0);
    let events = format!(
        "{}\n{}\n{}\n",
        json!({"kind": "record", "started": 1794516300.0, "colour": "srgb"}),
        on,
        off
    );
    let lines = from_replay(events.as_bytes(), "x").unwrap();
    assert_eq!(lines.len(), 1);
    assert_eq!(
        lines[0]["t0"],
        json!(1794516378.5),
        "within the client's second"
    );
    assert_eq!(lines[0]["t1"], json!(1794516383.5));
}

#[test]
fn a_line_goes_to_its_days_file() {
    let dir = std::env::temp_dir().join(format!("hellolink-pulls-{}", std::process::id()));
    let line = json!({"v": 1, "t0": 1794516378.0});
    let path = append(&dir, &line).unwrap();
    append(&dir, &line).unwrap();
    assert_eq!(path, file_for(&dir, 1794516378.0));
    assert!(
        path.file_name()
            .unwrap()
            .to_str()
            .unwrap()
            .ends_with(".jsonl")
    );
    let text = std::fs::read_to_string(&path).unwrap();
    assert_eq!(text, format!("{line}\n{line}\n"), "appended, one line each");
    std::fs::remove_dir_all(&dir).unwrap();
}
