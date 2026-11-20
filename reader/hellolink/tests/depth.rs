//! `hellolink depth`: the rows of `/hlink probe depth` (HelloLink/HelloLink.lua, `probeDepth`)
//! read from a screenshot (#213, step 4). The rows are drawn here from that Lua code, on the
//! noisy background of `render`, not by the reader's own code.

use hellolink::bitmap::{Bitmap, render};
use hellolink::depth::{Depth, probe_depth};
use std::path::PathBuf;
use std::process::Command;

const LINE: usize = 256;
const PATTERN: usize = 240;

/// The squares of `probeDepth(levels, px)`, as (red, green, blue) from 0 to 1, in order.
fn probe_colours(levels: u32) -> Vec<[f64; 3]> {
    let digit = |d: u32| [(d >= 4) as u32 as f64, (d % 4 >= 2) as u32 as f64, (d % 2) as f64];
    let l = (levels - 1) as f64;
    let symbol = |i: u32| {
        [
            (i / (levels * levels)) as f64 / l,
            (i / levels % levels) as f64 / l,
            (i % levels) as f64 / l,
        ]
    };
    let mut out: Vec<[f64; 3]> = [2, 1, 7, 0, 6, 3, 5, 4].iter().map(|&d| digit(d)).collect();
    out.push(digit(levels / 8));
    out.push(digit(levels % 8));
    let symbols = levels.pow(3);
    out.extend((0..symbols).map(symbol));
    let mut state = levels;
    for _ in 0..PATTERN {
        state = (state * 75 + 74) % 65537;
        out.push(symbol(state % symbols));
    }
    out
}

/// A screenshot of the probe's rows at (x, y), `bend` applied to every colour of the rows.
fn shot(levels: u32, px: usize, x: usize, y: usize, bend: fn([f64; 3]) -> [f64; 3]) -> Bitmap {
    let cells: String = probe_colours(levels)
        .into_iter()
        .enumerate()
        .map(|(i, c)| {
            let [r, g, b] = bend(c);
            format!("{} {} {px} {px} {r:.6} {g:.6} {b:.6}\n", x + i % LINE * px, y + i / LINE * px)
        })
        .collect();
    Bitmap::new(&render(&cells, 1.0, 0, 0, 2560, 200).unwrap()).unwrap()
}

fn same(c: [f64; 3]) -> [f64; 3] {
    c
}

/// Every channel to the nearest of four levels: 8 levels a channel come back as pairs.
fn four_levels(c: [f64; 3]) -> [f64; 3] {
    c.map(|v| (v * 3.0).round() / 3.0)
}

#[test]
fn four_levels_at_two_pixels_read_with_none_wrong() {
    let d = probe_depth(&shot(4, 2, 300, 80, same)).unwrap();
    assert_eq!(
        d,
        Depth {
            levels: 4,
            px: 2,
            wrong: 0,
            of: 240,
            apart: 85
        }
    );
}

#[test]
fn eight_levels_at_one_pixel_read_with_none_wrong() {
    let d = probe_depth(&shot(8, 1, 7, 40, same)).unwrap();
    assert_eq!((d.levels, d.px, d.wrong, d.apart), (8, 1, 0, 36));
}

#[test]
fn colours_the_screen_cannot_tell_apart_are_counted_wrong() {
    let d = probe_depth(&shot(8, 2, 300, 80, four_levels)).unwrap();
    assert_eq!((d.levels, d.px), (8, 2));
    assert_eq!(d.apart, 0, "colours that came back the same are 0 apart");
    assert!(d.wrong > 0, "{d:?}");
}

#[test]
fn an_image_with_no_probe_row_gives_none() {
    let blank = Bitmap::new(&render("", 1.0, 0, 0, 2560, 200).unwrap()).unwrap();
    assert_eq!(probe_depth(&blank), None);
}

#[test]
fn the_command_prints_a_line_an_image_and_fails_when_none_has_a_row() {
    let dir = PathBuf::from(env!("CARGO_TARGET_TMPDIR"));
    let (with, without) = (dir.join("depth-with.bmp"), dir.join("depth-without.bmp"));
    let cells: String = probe_colours(4)
        .into_iter()
        .enumerate()
        .map(|(i, [r, g, b])| format!("{} 80 2 2 {r:.6} {g:.6} {b:.6}\n", 300 + i * 2))
        .collect();
    std::fs::write(&with, render(&cells, 1.0, 0, 0, 2560, 200).unwrap()).unwrap();
    std::fs::write(&without, render("", 1.0, 0, 0, 2560, 200).unwrap()).unwrap();
    let run = |files: &[&PathBuf]| {
        Command::new(env!("CARGO_BIN_EXE_hellolink"))
            .arg("depth")
            .args(files)
            .output()
            .unwrap()
    };
    let out = run(&[&with, &without]);
    assert!(out.status.success(), "{}", String::from_utf8_lossy(&out.stderr));
    let lines: Vec<serde_json::Value> = String::from_utf8(out.stdout)
        .unwrap()
        .lines()
        .map(|l| serde_json::from_str(l).unwrap())
        .collect();
    assert_eq!(lines.len(), 2);
    assert_eq!(lines[0]["levels"], 4);
    assert_eq!(lines[0]["wrong"], 0);
    assert_eq!(lines[0]["image"], with.to_str().unwrap());
    assert_eq!(lines[1]["row"], false);
    let out = run(&[&without]);
    assert!(!out.status.success(), "no image had a row");
}
