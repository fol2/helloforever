//! `hellolink depth IMAGE...`: how many colours a square can carry on this display (#213,
//! step 4), and whether rows of 1-pixel squares one under the other read true (lanes, #232, part
//! C). Reads the rows of `/hlink probe depth <levels> [pixels] [lines]` and `/hlink probe lanes`
//! (HelloLink.lua) from a screenshot, as `probe_depth` of the Python reader did before #210.
//!
//! The rows: a finder (the strip's digits turned by one place), two digits that give the
//! levels a channel and the lines (the first is levels / 8 + 2 * (lines - 1)), a palette of every
//! colour in order (levels cubed), then 240 squares of a known pattern, or `lines` whole lines of
//! it; 256 squares a line. The reader does not know what a colour should look like
//! on this screen: it names each pattern square by the nearest palette colour as read.

use crate::bitmap::Bitmap;
use crate::strip1::{FINDER as STRIP_FINDER, Match, apart, matches_of};

pub const FINDER: [u8; 8] = [2, 1, 7, 0, 6, 3, 5, 4];
const LINE: usize = 256;
pub const PATTERN: usize = 240;

/// The pattern's length for `lines`: 240 for one line (the probe before lanes), else whole lines.
pub fn pattern_len(lines: usize) -> usize {
    if lines == 1 { PATTERN } else { lines * LINE }
}

/// What a probe row gave: levels a channel, pixels a square, pattern squares named wrong (of
/// `of`), how far apart the nearest two palette colours came back, and for each screen line the
/// pattern is on, its squares named wrong (the lanes).
#[derive(Debug, PartialEq)]
pub struct Depth {
    pub levels: u32,
    pub px: usize,
    pub wrong: usize,
    pub of: usize,
    pub apart: i32,
    pub lines: usize,
    pub wrong_by_line: Vec<usize>,
}

/// The pattern's symbols, as `probeDepth` makes them.
fn pattern(levels: u32, len: usize) -> Vec<u32> {
    let mut state = levels;
    (0..len)
        .map(|_| {
            state = (state * 75 + 74) % 65537;
            state % levels.pow(3)
        })
        .collect()
}

/// The side of a finder's squares when its six inner runs are the same whole number of
/// pixels and the outer two are at least that.
fn whole_squares(m: &Match) -> Option<usize> {
    let side = m[1].1 - m[1].0;
    let inner = m[1..7].iter().all(|r| r.1 - r.0 == side);
    let outer = m[0].1 - m[0].0 >= side && m[7].1 - m[7].0 >= side;
    (inner && outer).then_some(side)
}

/// The first probe row in the image, or None.
pub fn probe_depth(bmp: &Bitmap) -> Option<Depth> {
    for y in 0..bmp.height {
        for m in matches_of(bmp.digits(y), &FINDER) {
            let Some(w) = whole_squares(&m) else { continue };
            let x0 = m[1].0 - w;
            // This finder is the strip's turned by one place: the strip's squares 1 to 8 match
            // it when its first level square is 4 (health near 50 %). The strip's finder then
            // starts one square to the left (`/hlink probe depth` draws from x = 0).
            let centre = |x: usize, y: usize| bmp.digit(x as f64 + w as f64 / 2.0, y as f64);
            if x0 >= w && centre(x0 - w, y) == Some(STRIP_FINDER[0]) {
                continue;
            }
            // The first line that matches whole may be under the top: an edge pixel of the top
            // line can differ. Go up while the squares' centres still show the finder.
            let finder_at = |y: usize| (0..8).all(|i| centre(x0 + i * w, y) == Some(FINDER[i]));
            let mut top = y;
            while top > 0 && finder_at(top - 1) {
                top -= 1;
            }
            let point = |i: usize| {
                (
                    (x0 + i % LINE * w) as f64 + w as f64 / 2.0,
                    (top + i / LINE * w) as f64 + w as f64 / 2.0,
                )
            };
            let digit = |i: usize| {
                let (x, y) = point(i);
                bmp.digit(x, y)
            };
            let (Some(high), Some(low)) = (digit(8), digit(9)) else {
                continue;
            };
            let (levels, lines) = ((high % 2) as u32 * 8 + low as u32, high as usize / 2 + 1);
            let len = pattern_len(lines);
            if !(2..=8).contains(&levels) {
                continue;
            }
            let symbols = levels.pow(3) as usize;
            let rgb = |i: usize| {
                let (x, y) = point(i);
                bmp.rgb(x, y)
            };
            let Some(palette) = (0..symbols)
                .map(|i| rgb(10 + i))
                .collect::<Option<Vec<_>>>()
            else {
                continue;
            };
            let Some(cells) = (0..len)
                .map(|i| rgb(10 + symbols + i))
                .collect::<Option<Vec<_>>>()
            else {
                continue;
            };
            // the first of the nearest, as Python's min()
            let nearest = |c: [u8; 3]| {
                (0..symbols)
                    .min_by_key(|&i| {
                        (0..3)
                            .map(|k| (c[k] as i32 - palette[i][k] as i32).pow(2))
                            .sum::<i32>()
                    })
                    .unwrap_or(0) as u32
            };
            // each pattern square's screen line, counted from the first line the pattern is on
            let first = (10 + symbols) / LINE;
            let mut wrong_by_line = vec![0; (10 + symbols + len - 1) / LINE - first + 1];
            for (i, (c, want)) in cells.iter().zip(pattern(levels, len)).enumerate() {
                if nearest(*c) != want {
                    wrong_by_line[(10 + symbols + i) / LINE - first] += 1;
                }
            }
            let wrong = wrong_by_line.iter().sum();
            return Some(Depth {
                levels,
                px: w,
                wrong,
                of: len,
                apart: apart(&palette)?,
                lines,
                wrong_by_line,
            });
        }
    }
    None
}
