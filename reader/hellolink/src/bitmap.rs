//! An uncompressed 24- or 32-bit BMP, and the test renderer: the parts of
//! tools/hellolink_strip.py that tools/strip1.py reads through.

use crate::strip1::FINDER;

const MAX_SIDE: i64 = 16384; // pixels; larger than any display

/// A bitmap as colours and colour digits, rows from the top.
pub struct Bitmap {
    pub width: usize,
    pub height: usize,
    rgb: Vec<[u8; 3]>,
    digits: Vec<u8>,
}

fn u16_at(data: &[u8], at: usize) -> u32 {
    u16::from_le_bytes([data[at], data[at + 1]]) as u32
}

fn u32_at(data: &[u8], at: usize) -> u32 {
    u32::from_le_bytes([data[at], data[at + 1], data[at + 2], data[at + 3]])
}

impl Bitmap {
    pub fn new(data: &[u8]) -> Result<Bitmap, String> {
        if data.len() < 54 || &data[..2] != b"BM" {
            return Err("not a BMP file".into());
        }
        let offset = u32_at(data, 10) as usize;
        let width = u32_at(data, 18) as i32 as i64;
        let height = u32_at(data, 22) as i32 as i64;
        let (bpp, compression) = (u16_at(data, 28), u32_at(data, 30));
        if !matches!(bpp, 24 | 32) || !matches!(compression, 0 | 3) {
            return Err(format!(
                "unsupported BMP: {bpp} bits, compression {compression}"
            ));
        }
        if !(0 < width && width <= MAX_SIDE && 0 < height.abs() && height.abs() <= MAX_SIDE) {
            return Err(format!("unsupported BMP size: {width} x {height}"));
        }
        let mut masks = [0xFF0000, 0x00FF00, 0x0000FF];
        if compression == 3 {
            if data.len() < 66 {
                return Err("BMP too short for its colour masks".into());
            }
            masks = [u32_at(data, 54), u32_at(data, 58), u32_at(data, 62)];
        }
        if masks
            .iter()
            .any(|m| !matches!(m, 0xFF | 0xFF00 | 0xFF0000 | 0xFF000000))
        {
            return Err("unsupported BMP colour masks".into());
        }
        // The byte of red, green and blue in a pixel.
        let at = masks.map(|m| (m.trailing_zeros() / 8) as usize);
        let (width, height) = (width as usize, height.unsigned_abs() as usize);
        let step = bpp as usize / 8;
        let stride = (width * step + 3) & !3;
        let top_down = (u32_at(data, 22) as i32) < 0;
        // Every pixel the header promises must be in the file: never read past it, never pad.
        if offset < 54 || offset + stride * height > data.len() {
            return Err("BMP pixel data is not all in the file".into());
        }
        let mut rgb = Vec::with_capacity(width * height);
        for y in 0..height {
            let line = if top_down { y } else { height - 1 - y };
            for x in 0..width {
                let p = offset + line * stride + x * step;
                let byte = |i: usize| data.get(p + at[i]).copied();
                match (byte(0), byte(1), byte(2)) {
                    (Some(r), Some(g), Some(b)) => rgb.push([r, g, b]),
                    _ => return Err("BMP pixel data is not all in the file".into()),
                }
            }
        }
        let digits = rgb
            .iter()
            .map(|c| 4 * (c[0] > 127) as u8 + 2 * (c[1] > 127) as u8 + (c[2] > 127) as u8)
            .collect();
        Ok(Bitmap {
            width,
            height,
            rgb,
            digits,
        })
    }

    /// The colour digits (4 red + 2 green + blue, each on above half) of a line.
    pub fn digits(&self, y: usize) -> &[u8] {
        &self.digits[y * self.width..(y + 1) * self.width]
    }

    /// The pixel index for a point, as Python's int(): towards zero; None outside the image.
    fn index(&self, x: f64, y: f64) -> Option<usize> {
        let (xi, yi) = (x as i64, y as i64);
        (0 <= xi && (xi as usize) < self.width && 0 <= yi && (yi as usize) < self.height)
            .then(|| yi as usize * self.width + xi as usize)
    }

    /// The pixel's (red, green, blue), or None outside the image.
    pub fn rgb(&self, x: f64, y: f64) -> Option<[u8; 3]> {
        self.index(x, y).map(|i| self.rgb[i])
    }

    pub fn digit(&self, x: f64, y: f64) -> Option<u8> {
        self.index(x, y).map(|i| self.digits[i])
    }
}

/// The grey noise behind a test row: the same for every frame of one size.
fn noise(width: usize, height: usize) -> Vec<u8> {
    let mut state: u64 = 12345;
    let mut px = Vec::with_capacity(width * height * 4);
    for _ in 0..width * height {
        state = (state * 1103515245 + 12345) & 0x7FFFFFFF;
        let v = (60 + (state >> 16) % 120) as u8;
        px.extend([v, v, v, 255]);
    }
    px
}

/// Draws a cells file (one square a line: x y w h r g b, as the addon test writes them) as a
/// 32-bit top-down BMP, on a background that tries to fool the reader: grey noise, pure
/// colours, and a row that starts like the finder. As `hellolink_strip.py render`.
pub fn render(
    cells: &str,
    scale: f64,
    dx: i64,
    dy: i64,
    width: usize,
    height: usize,
) -> Result<Vec<u8>, String> {
    let mut px = noise(width, height);
    let mut rect = |x: i64, y: i64, w: i64, h: i64, rgb: [u8; 3]| {
        let (left, right) = (x.max(0), (width as i64).min(x + w));
        for yy in y.max(0)..(height as i64).min(y + h) {
            for xx in left..right {
                let at = (yy as usize * width + xx as usize) * 4;
                px[at..at + 4].copy_from_slice(&[rgb[2], rgb[1], rgb[0], 255]);
            }
        }
    };
    let (w, h) = (width as i64, height as i64);
    rect(w - 90, h - 40, 80, 30, [255, 0, 0]);
    for (i, d) in FINDER[..5].iter().enumerate() {
        let on = |bit: u8| 255 * (d >> bit & 1);
        rect(w - 200 + i as i64 * 9, h - 80, 9, 9, [on(2), on(1), on(0)]);
    }
    // Python's round(): halves to the even number.
    let round = |v: f64| v.round_ties_even() as i64;
    for line in cells.lines() {
        let v: Vec<f64> = line
            .split_whitespace()
            .map(|s| {
                s.parse::<f64>()
                    .map_err(|e| format!("cells line {line:?}: {e}"))
            })
            .collect::<Result<_, _>>()?;
        let [x, y, cw, ch, r, g, b] = v[..] else {
            return Err(format!("cells line {line:?}: not seven numbers"));
        };
        let channel = |c: f64| {
            u8::try_from(round(c * 255.0))
                .map_err(|_| format!("cells line {line:?}: a colour out of 0 to 1"))
        };
        let (left, top) = (round(dx as f64 + x * scale), round(dy as f64 + y * scale));
        let colour = [channel(r)?, channel(g)?, channel(b)?];
        rect(
            left,
            top,
            round(dx as f64 + (x + cw) * scale) - left,
            round(dy as f64 + (y + ch) * scale) - top,
            colour,
        );
    }
    // The header screencapture writes: 124 bytes, 32 bits, bit fields, rows from the top.
    let mut header = Vec::with_capacity(124);
    for v in [124u32, width as u32, (-(height as i32)) as u32] {
        header.extend(v.to_le_bytes());
    }
    header.extend(1u16.to_le_bytes());
    header.extend(32u16.to_le_bytes());
    for v in [
        3u32,
        px.len() as u32,
        2835,
        2835,
        0,
        0,
        0x00FF0000,
        0x0000FF00,
        0x000000FF,
        0xFF000000,
    ] {
        header.extend(v.to_le_bytes());
    }
    header.resize(124, 0);
    let mut out = b"BM".to_vec();
    out.extend((14 + 124 + px.len() as u32).to_le_bytes());
    out.extend([0; 4]);
    out.extend((14u32 + 124).to_le_bytes());
    out.extend(header);
    out.extend(px);
    Ok(out)
}
