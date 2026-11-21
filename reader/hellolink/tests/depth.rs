//! `hellolink depth`: the rows of `/hlink probe depth` (HelloLink/HelloLink.lua, `probeDepth`)
//! read from a screenshot (#213, step 4). The rows are drawn here from that Lua code, on the
//! noisy background of `render`, not by the reader's own code.

use hellolink::bitmap::{Bitmap, render};
use hellolink::depth::{Depth, probe_depth};
use std::path::PathBuf;
use std::process::Command;

const LINE: usize = 256;
const PATTERN: usize = 240;

/// The squares of `probeDepth(levels, px, lines)`, as (red, green, blue) from 0 to 1, in order.
fn probe_colours(levels: u32, lines: u32) -> Vec<[f64; 3]> {
    let digit = |d: u32| {
        [
            (d >= 4) as u32 as f64,
            (d % 4 >= 2) as u32 as f64,
            (d % 2) as f64,
        ]
    };
    let l = (levels - 1) as f64;
    let symbol = |i: u32| {
        [
            (i / (levels * levels)) as f64 / l,
            (i / levels % levels) as f64 / l,
            (i % levels) as f64 / l,
        ]
    };
    let mut out: Vec<[f64; 3]> = [2, 1, 7, 0, 6, 3, 5, 4].iter().map(|&d| digit(d)).collect();
    out.push(digit(levels / 8 + 2 * (lines - 1)));
    out.push(digit(levels % 8));
    let symbols = levels.pow(3);
    out.extend((0..symbols).map(symbol));
    let mut state = levels;
    for _ in 0..if lines == 1 {
        PATTERN
    } else {
        lines as usize * LINE
    } {
        state = (state * 75 + 74) % 65537;
        out.push(symbol(state % symbols));
    }
    out
}

/// The cells file of the probe's rows at (x, y), `bend` applied to every colour of the rows.
fn cells(levels: u32, px: usize, x: usize, y: usize, bend: fn([f64; 3]) -> [f64; 3]) -> String {
    cells_of(levels, 1, px, x, y, bend, None)
}

/// The same for `lines`, with the squares of screen line `bent_line` (from the probe's top) bent
/// instead of all of them, when given.
fn cells_of(
    levels: u32,
    lines: u32,
    px: usize,
    x: usize,
    y: usize,
    bend: fn([f64; 3]) -> [f64; 3],
    bent_line: Option<usize>,
) -> String {
    probe_colours(levels, lines)
        .into_iter()
        .enumerate()
        .map(|(i, c)| {
            let [r, g, b] = if bent_line.is_none_or(|l| l == i / LINE) {
                bend(c)
            } else {
                c
            };
            format!(
                "{} {} {px} {px} {r:.6} {g:.6} {b:.6}\n",
                x + i % LINE * px,
                y + i / LINE * px
            )
        })
        .collect()
}

/// A screenshot of the probe's rows at (x, y), `bend` applied to every colour of the rows.
fn shot(levels: u32, px: usize, x: usize, y: usize, bend: fn([f64; 3]) -> [f64; 3]) -> Bitmap {
    let cells = cells(levels, px, x, y, bend);
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
            apart: 85,
            lines: 1,
            wrong_by_line: vec![0, 0]
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
    let cells = cells(4, 2, 300, 80, same);
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
    assert!(
        out.status.success(),
        "{}",
        String::from_utf8_lossy(&out.stderr)
    );
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

fn image(cells: &str, scale: f64) -> Bitmap {
    Bitmap::new(&render(cells, scale, 0, 0, 2560, 200).unwrap()).unwrap()
}

#[test]
fn a_row_whose_squares_are_not_whole_pixels_is_not_read() {
    // drawn at 2.5 pixels a square: the finder's runs are 2 and 3 pixels
    assert_eq!(probe_depth(&image(&cells(4, 2, 300, 80, same), 1.25)), None);
}

#[test]
fn a_finder_cut_short_on_the_left_is_not_read() {
    // the first finder square is 1 pixel wide: the row is not whole
    let mut lines: Vec<String> = cells(4, 2, 300, 80, same)
        .lines()
        .map(String::from)
        .collect();
    lines[0] = lines[0].replacen("300 80 2 2", "301 80 1 2", 1);
    assert_eq!(probe_depth(&image(&(lines.join("\n") + "\n"), 1.0)), None);
}

#[test]
fn level_digits_out_of_2_to_8_are_not_a_row() {
    // the two level digits say 1 and 1: 9 levels, which the probe never draws
    let mut lines: Vec<String> = cells(8, 2, 300, 80, same)
        .lines()
        .map(String::from)
        .collect();
    for i in [8, 9] {
        let v: Vec<&str> = lines[i].split_whitespace().collect();
        lines[i] = format!("{} {} {} {} 0 0 1", v[0], v[1], v[2], v[3]);
    }
    assert_eq!(probe_depth(&image(&(lines.join("\n") + "\n"), 1.0)), None);
}

#[test]
fn the_strip_with_health_near_half_is_not_taken_for_the_probe() {
    use hellolink::strip1::{pack_fast, pack_frame, row_colours};
    // the strip's first level square is 4 at 50 % health: its squares 1 to 8 then show the
    // probe's finder (the strip's turned by one place)
    let frame = pack_frame(4711, 1, 10, &pack_fast(&[("clock", &[("clock", 1)])]), None).unwrap();
    let strip: String = row_colours(4711, 4, [Some(0.5), Some(1.0), None, None], &frame)
        .iter()
        .enumerate()
        .map(|(i, [r, g, b])| format!("{} 10 2 2 {r:.6} {g:.6} {b:.6}\n", 2 + i * 2))
        .collect();
    let both = strip + &cells(4, 2, 0, 80, same);
    let d = probe_depth(&image(&both, 1.0)).unwrap();
    assert_eq!((d.levels, d.px, d.wrong, d.apart), (4, 2, 0, 85));
}

#[test]
fn a_top_line_with_an_edge_pixel_off_is_still_the_top() {
    // the top left pixel of the first finder square is black: the top line does not match whole
    let cells = cells(4, 2, 300, 80, same) + "300 80 1 1 0 0 0\n";
    let d = probe_depth(&image(&cells, 1.0)).unwrap();
    assert_eq!((d.levels, d.wrong), (4, 0));
}

#[test]
fn a_display_that_moves_the_levels_still_reads_from_the_palette() {
    // every level moved, as a display does (sent 85 came back 70 on this one): a fixed table
    // would name squares wrong, the palette as read does not
    let d = probe_depth(&shot(4, 2, 300, 80, |c| c.map(|v| 0.1 + v * 0.6))).unwrap();
    assert_eq!(d.wrong, 0);
    assert!(d.apart < 85, "{d:?}");
}

#[test]
fn the_command_refuses_an_unknown_option_and_names_a_bad_image() {
    let dir = PathBuf::from(env!("CARGO_TARGET_TMPDIR"));
    let (good, bad) = (dir.join("depth-option.bmp"), dir.join("depth-bad.bmp"));
    std::fs::write(
        &good,
        render(&cells(4, 2, 300, 80, same), 1.0, 0, 0, 2560, 200).unwrap(),
    )
    .unwrap();
    std::fs::write(&bad, b"not a bitmap").unwrap();
    let out = Command::new(env!("CARGO_BIN_EXE_hellolink"))
        .args(["depth", "--typo=1", good.to_str().unwrap()])
        .output()
        .unwrap();
    assert!(!out.status.success());
    let out = Command::new(env!("CARGO_BIN_EXE_hellolink"))
        .args(["depth", bad.to_str().unwrap()])
        .output()
        .unwrap();
    assert!(!out.status.success());
    let err = String::from_utf8_lossy(&out.stderr);
    assert!(err.contains("depth-bad.bmp"), "{err}");
}

/// Every channel the other way round: a square read as another colour.
fn inverted(c: [f64; 3]) -> [f64; 3] {
    c.map(|v| 1.0 - v)
}

#[test]
fn four_lanes_at_one_pixel_read_with_none_wrong_and_say_each_line() {
    let cells = cells_of(4, 4, 1, 7, 40, same, None);
    let d =
        probe_depth(&Bitmap::new(&render(&cells, 1.0, 0, 0, 2560, 200).unwrap()).unwrap()).unwrap();
    // the pattern starts at square 74 of the first line and fills 1,024 squares: lines 0 to 4
    assert_eq!(
        (
            d.levels,
            d.px,
            d.lines,
            d.of,
            d.wrong,
            d.wrong_by_line.clone()
        ),
        (4, 1, 4, 1024, 0, vec![0, 0, 0, 0, 0])
    );
}

#[test]
fn a_lane_read_wrong_is_named_by_its_line() {
    let cells = cells_of(4, 4, 1, 7, 40, inverted, Some(2));
    let d =
        probe_depth(&Bitmap::new(&render(&cells, 1.0, 0, 0, 2560, 200).unwrap()).unwrap()).unwrap();
    assert_eq!(d.lines, 4);
    assert!(d.wrong_by_line[2] > 200, "{d:?}");
    assert_eq!(
        (
            d.wrong_by_line[0],
            d.wrong_by_line[1],
            d.wrong_by_line[3],
            d.wrong_by_line[4]
        ),
        (0, 0, 0, 0)
    );
}
