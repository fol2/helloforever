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
    /// The palette squares as read, in code order.
    pub palette: Vec<[u8; 3]>,
    /// The pattern squares as read, in order.
    pub cells: Vec<[u8; 3]>,
}

/// The pattern read by the ramp over a set of levels (`docs/specs/232.md`, part C, "The computed
/// palette", "Measure first" 1): only the pattern squares and palette squares whose three levels
/// are all in the set count. `wrong` is by the nearest drawn palette colour of the set,
/// `ramp_wrong` by the ramp (the reader's steps 1 and 3), `gap` and `leak` as its step 4.
#[derive(Debug, PartialEq)]
pub struct Measure {
    pub levels: Vec<u32>,
    pub pattern: usize,
    pub wrong: usize,
    pub ramp_wrong: usize,
    pub gap: i32,
    pub leak: i32,
}

impl Depth {
    /// The measures over `set`: levels under `self.levels`, rising, two at least.
    pub fn measure(&self, set: &[u32]) -> Measure {
        let l = self.levels;
        let level = |i: u32| [i / (l * l), i / l % l, i % l];
        let code = |t: [u32; 3]| (t[0] * l + t[1]) * l + t[2];
        let in_set = |i: u32| level(i).iter().all(|k| set.contains(k));
        let colour = |i: u32| self.palette[i as usize].map(i32::from);
        // the ramp: each channel at each level of the set, the other two at the lowest
        let base = colour(code([set[0]; 3]));
        let (mut ramp, mut leak) = ([vec![], vec![], vec![]], 0);
        for (c, values) in ramp.iter_mut().enumerate() {
            for &k in set {
                let mut t = [set[0]; 3];
                t[c] = k;
                let p = colour(code(t));
                values.push(p[c]);
                for o in (0..3).filter(|&o| o != c) {
                    leak = leak.max((p[o] - base[o]).abs());
                }
            }
        }
        let gap = ramp
            .iter()
            .flat_map(|v| v.windows(2).map(|w| w[1] - w[0]))
            .min()
            .unwrap_or(0);
        // channel by channel, the nearest level of the ramp; of two equally near, the first (lower)
        let by_ramp = |p: [u8; 3]| {
            let t: [u32; 3] = std::array::from_fn(|c| {
                let n = (0..set.len())
                    .min_by_key(|&n| (p[c] as i32 - ramp[c][n]).abs())
                    .unwrap_or(0);
                set[n]
            });
            code(t)
        };
        let codes: Vec<u32> = (0..l.pow(3)).filter(|&i| in_set(i)).collect();
        let by_palette = |p: [u8; 3]| nearest(&self.palette, &codes, p);
        let (mut pattern, mut wrong, mut ramp_wrong) = (0, 0, 0);
        for (&p, want) in self.cells.iter().zip(self::pattern(l, self.of)) {
            if in_set(want) {
                pattern += 1;
                wrong += usize::from(by_palette(p) != want);
                ramp_wrong += usize::from(by_ramp(p) != want);
            }
        }
        Measure {
            levels: set.to_vec(),
            pattern,
            wrong,
            ramp_wrong,
            gap,
            leak,
        }
    }

    /// The measures for each floor f from 1 to levels − 2: the levels f to levels − 1.
    pub fn floors(&self) -> Vec<Measure> {
        (1..self.levels.saturating_sub(1))
            .map(|f| self.measure(&(f..self.levels).collect::<Vec<_>>()))
            .collect()
    }
}

/// Of `codes`, the palette colour nearest to `c` by the sum of squared differences; of equally
/// near ones, the first (as Python's min()).
fn nearest(palette: &[[u8; 3]], codes: &[u32], c: [u8; 3]) -> u32 {
    codes
        .iter()
        .copied()
        .min_by_key(|&i| {
            (0..3)
                .map(|k| (c[k] as i32 - palette[i as usize][k] as i32).pow(2))
                .sum::<i32>()
        })
        .unwrap_or(0)
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
            // with lines, the pattern starts a line of its own: exactly `lines` screen lines
            let start = if lines == 1 {
                10 + symbols
            } else {
                (10 + symbols).div_ceil(LINE) * LINE
            };
            let Some(cells) = (0..len).map(|i| rgb(start + i)).collect::<Option<Vec<_>>>() else {
                continue;
            };
            let all: Vec<u32> = (0..symbols as u32).collect();
            // each pattern square's screen line, counted from the first line the pattern is on
            let first = start / LINE;
            let mut wrong_by_line = vec![0; (start + len - 1) / LINE - first + 1];
            for (i, (c, want)) in cells.iter().zip(pattern(levels, len)).enumerate() {
                if nearest(&palette, &all, *c) != want {
                    wrong_by_line[(start + i) / LINE - first] += 1;
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
                palette,
                cells,
            });
        }
    }
    None
}
