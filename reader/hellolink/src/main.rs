//! hellolink: the strip reader's commands.
//!
//!     hellolink rows [--step T] a.bmp b.bmp ...          each image's row, as JSON lines
//!     hellolink render cells.txt out.bmp [--scale S] [--dx X] [--dy Y] [--width W] [--height H]
//!     hellolink render-rows --scale S [--step T] a.txt b.txt ...   render each cells file, then rows
//!     hellolink serve REQUESTS REPLIES                   the addon test's server
//!     hellolink watch [--json] [--fps N] [--addons DIR] [--serve PORT] [--capture TOOL]
//!                     [--remember FILE] [--record FILE]
//!     hellolink write ADDONS [TEXT | -] [--strip-session N] [--assist FILE | -]
//!
//! `rows` and `render` are those of tools/hellolink_strip.py; `render-rows` and `serve` are
//! those of tests/render_rows.py. `serve` reads one request a line ("S T a.txt b.txt ...")
//! and writes the batch's lines, then "END"; it tries the last good grid first. `watch` is
//! that of tools/hellolink_strip.py. `write` is that of tools/hellolink.py: it puts the slot
//! file into every slot (docs/specs/115.md, section 6).
#![forbid(unsafe_code)]

use hellolink::api::{Api, SEND_WAIT};
use hellolink::bitmap::{Bitmap, render};
use hellolink::capture;
use hellolink::follow::{WATCH_HELP, World, follow, parse_watch};
use hellolink::rows::rows_of_images;
use hellolink::slots;
use std::collections::HashMap;
use std::fs;
use std::io::{self, BufRead, BufReader, BufWriter, Write};
use std::process::ExitCode;
use std::sync::Arc;
use std::time::Duration;

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
    let usage = "usage: hellolink rows|render|render-rows|serve|watch ... (see the source's head)";
    let (cmd, rest) = args.split_first().ok_or(usage)?;
    if cmd == "-h" || cmd == "--help" {
        println!("{usage}");
        return Ok(());
    }
    if cmd == "watch" {
        let args = parse_watch(rest)?;
        if args.help {
            print!("{WATCH_HELP}");
            return Ok(());
        }
        // Ctrl-C stops the capture and ends `watch` cleanly, as Python's KeyboardInterrupt
        capture::on_ctrl_c().map_err(|e| format!("Ctrl-C: {e}"))?;
        let mut world = World::real();
        let api = match args.serve.filter(|&port| port != 0) {
            None => None,
            Some(port) => {
                let api = Arc::new(
                    Api::start(port, Duration::from_secs_f64(SEND_WAIT))
                        .map_err(|e| format!("--serve {port}: {e}"))?,
                );
                eprintln!(
                    "the local API is at http://127.0.0.1:{} (GET /state, GET /events)",
                    api.port
                );
                let told = Arc::clone(&api);
                world.tell = Box::new(move |event| told.tell(event));
                Some(api)
            }
        };
        let done = follow(&args, &mut world);
        drop(world); // its `tell` holds the API too
        drop(api); // closed: its clients told to leave, its port free
        return done;
    }
    if cmd == "write" {
        return write(rest);
    }
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

/// `hellolink write ADDONS [TEXT | -] [--strip-session N] [--assist FILE | -]`.
fn write(args: &[String]) -> Result<(), String> {
    let usage = "usage: hellolink write ADDONS [TEXT | -] [--strip-session N] [--assist FILE | -]";
    let (opts, rest) = parse(args)?;
    let ([addons] | [addons, _]) = &rest[..] else {
        return Err(usage.into());
    };
    if let Some(bad) = opts
        .keys()
        .find(|k| !["strip-session", "assist"].contains(&k.as_str()))
    {
        return Err(format!("write: unrecognized argument: --{bad}"));
    }
    let text = rest.get(1);
    let strip =
        match opts.get("strip-session") {
            None => None,
            Some(v) => Some(v.parse::<i64>().map_err(|_| {
                format!("write: argument --strip-session: invalid int value: {v:?}")
            })?),
        };
    let assist = opts.get("assist");
    if text.is_none() && strip.is_none() && assist.is_none() {
        return Err("nothing to write: give a text, --strip-session or --assist".into());
    }
    if text.is_some_and(|t| t == "-") && assist.is_some_and(|a| a == "-") {
        return Err("only one of the text and --assist can come from stdin".into());
    }
    let stdin = || io::read_to_string(io::stdin());
    let assist = match assist {
        None => None,
        Some(from) => {
            let raw = if from == "-" {
                stdin()
            } else {
                fs::read_to_string(from)
            };
            let set = raw
                .map_err(|e| e.to_string())
                .and_then(|raw| serde_json::from_str(&raw).map_err(|e| e.to_string()))
                .and_then(|set| slots::check_assist(&set));
            Some(set.map_err(|e| format!("--assist: {e}"))?)
        }
    };
    let text = match text {
        Some(t) if t == "-" => Some(stdin().map_err(|e| e.to_string())?),
        t => t.cloned(),
    };
    let done = slots::write(addons.as_ref(), text.as_deref(), strip, assist)?;
    println!("wrote {} bytes to {} slots", done.bytes, done.slots);
    Ok(())
}

fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().skip(1).collect();
    match run(&args) {
        Ok(()) => ExitCode::SUCCESS,
        Err(e) => {
            // A stderr nobody reads (its pipe full) must not keep the process: the line gets
            // STOP_WAIT, then the exit.
            let (said, done) = std::sync::mpsc::channel();
            std::thread::spawn(move || {
                eprintln!("hellolink: {e}");
                let _ = said.send(());
            });
            let _ = done.recv_timeout(std::time::Duration::from_secs_f64(capture::STOP_WAIT));
            ExitCode::FAILURE
        }
    }
}
