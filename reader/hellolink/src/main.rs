//! hellolink: the strip reader's commands.
//!
//!     hellolink rows [--step T] a.bmp b.bmp ...          each image's row, as JSON lines
//!     hellolink render cells.txt out.bmp [--scale S] [--dx X] [--dy Y] [--width W] [--height H]
//!     hellolink render-rows --scale S [--step T] a.txt b.txt ...   render each cells file, then rows
//!     hellolink serve REQUESTS REPLIES                   the addon test's server
//!
//! `rows` and `render` are those of tools/hellolink_strip.py; `render-rows` and `serve` are
//! those of tests/render_rows.py. `serve` reads one request a line ("S T a.txt b.txt ...")
//! and writes the batch's lines, then "END"; it tries the last good grid first.
#![forbid(unsafe_code)]

use hellolink::bitmap::{Bitmap, render};
use hellolink::rows::rows_of_images;
use std::collections::HashMap;
use std::fs;
use std::io::{self, BufRead, BufReader, BufWriter, Write};
use std::process::ExitCode;

/// The options (`--name value` or `--name=value`) and the other arguments.
fn parse(args: &[String]) -> Result<(HashMap<String, String>, Vec<String>), String> {
    let (mut opts, mut rest) = (HashMap::new(), Vec::new());
    let mut it = args.iter();
    while let Some(a) = it.next() {
        match a.strip_prefix("--") {
            Some(name) => {
                let (name, value) = match name.split_once('=') {
                    Some((n, v)) => (n.to_string(), v.to_string()),
                    None => (
                        name.to_string(),
                        it.next().ok_or(format!("{a} needs a value"))?.clone(),
                    ),
                };
                opts.insert(name, value);
            }
            None => rest.push(a.clone()),
        }
    }
    Ok((opts, rest))
}

fn number<T: std::str::FromStr>(
    opts: &HashMap<String, String>,
    name: &str,
    default: Option<T>,
) -> Result<T, String> {
    match opts.get(name) {
        Some(v) => v
            .parse()
            .map_err(|_| format!("--{name}: not a number: {v}")),
        None => default.ok_or(format!("--{name} is required")),
    }
}

fn read(path: &str) -> Result<Vec<u8>, String> {
    fs::read(path).map_err(|e| format!("{path}: {e}"))
}

/// The cells files drawn as tests/render_rows.py draws them: 2560 by 12 pixels.
fn rendered(scale: f64, cells: &[String]) -> Result<Vec<Bitmap>, String> {
    cells
        .iter()
        .map(|c| {
            let text = String::from_utf8(read(c)?).map_err(|e| format!("{c}: {e}"))?;
            Bitmap::new(&render(&text, scale, 0, 0, 2560, 12)?)
        })
        .collect()
}

fn run(args: &[String]) -> Result<(), String> {
    let usage = "usage: hellolink rows|render|render-rows|serve ... (see the source's head)";
    let (cmd, rest) = args.split_first().ok_or(usage)?;
    let (opts, files) = parse(rest)?;
    let out = &mut BufWriter::new(io::stdout().lock());
    let io = |e: io::Error| e.to_string();
    match cmd.as_str() {
        "rows" if !files.is_empty() => {
            let images: Vec<Bitmap> = files
                .iter()
                .map(|f| Bitmap::new(&read(f)?))
                .collect::<Result<_, String>>()?;
            rows_of_images(&images, number(&opts, "step", Some(0.1))?, false, out).map_err(io)
        }
        "render" if files.len() == 2 => {
            let text =
                String::from_utf8(read(&files[0])?).map_err(|e| format!("{}: {e}", files[0]))?;
            let bmp = render(
                &text,
                number(&opts, "scale", Some(1.0))?,
                number(&opts, "dx", Some(0))?,
                number(&opts, "dy", Some(0))?,
                number(&opts, "width", Some(800))?,
                number(&opts, "height", Some(300))?,
            )?;
            fs::write(&files[1], bmp).map_err(|e| format!("{}: {e}", files[1]))
        }
        "render-rows" if !files.is_empty() => {
            let images = rendered(number(&opts, "scale", None)?, &files)?;
            rows_of_images(&images, number(&opts, "step", Some(0.1))?, false, out).map_err(io)
        }
        "serve" if files.len() == 2 => {
            // The requests first, then the replies: the order the test opens its fifos in.
            let requests = fs::File::open(&files[0]).map_err(|e| format!("{}: {e}", files[0]))?;
            let mut replies = BufWriter::new(
                fs::File::create(&files[1]).map_err(|e| format!("{}: {e}", files[1]))?,
            );
            for line in BufReader::new(requests).lines() {
                let line = line.map_err(io)?;
                let words: Vec<String> = line.split_whitespace().map(String::from).collect();
                let [scale, step, cells @ ..] = &words[..] else {
                    continue;
                };
                let number = |v: &str| v.parse::<f64>().map_err(|_| format!("not a number: {v}"));
                let images = rendered(number(scale)?, cells)?;
                rows_of_images(&images, number(step)?, true, &mut replies).map_err(io)?;
                writeln!(replies, "END")
                    .and_then(|_| replies.flush())
                    .map_err(io)?;
            }
            Ok(())
        }
        _ => Err(usage.into()),
    }?;
    out.flush().map_err(io)
}

fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().skip(1).collect();
    match run(&args) {
        Ok(()) => ExitCode::SUCCESS,
        Err(e) => {
            eprintln!("hellolink: {e}");
            ExitCode::FAILURE
        }
    }
}
