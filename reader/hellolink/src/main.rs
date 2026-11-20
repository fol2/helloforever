//! hellolink: the strip reader's commands.
//!
//!     hellolink rows [--step T] a.bmp b.bmp ...          each image's row, as JSON lines
//!     hellolink render cells.txt out.bmp [--scale S] [--dx X] [--dy Y] [--width W] [--height H]
//!     hellolink render-rows --scale S [--step T] a.txt b.txt ...   render each cells file, then rows
//!     hellolink serve REQUESTS REPLIES                   the addon test's server
//!     hellolink watch [--json] [--fps N] [--addons DIR] [--serve PORT] [--capture TOOL]
//!                     [--remember FILE] [--record FILE]
//!     hellolink write ADDONS [TEXT | -] [--strip-session N] [--assist FILE | -]
//!     hellolink assist --addons DIR [--reader URL] [--log FILE]
//!     hellolink install ADDONS [--slots N]               HelloLink and its slots; the game closed
//!     hellolink install-reader [--to DIR] [--checkout DIR]   this program, outside any checkout
//!     hellolink package [--check] [--no-tests] [--root DIR]  check and zip a HelloForever release
//!     hellolink replay RECORD                            a `watch --record` file back into events
//!     hellolink depth IMAGE...                           the rows of `/hlink probe depth` in screenshots
//!
//! `rows` and `render` are those of tools/hellolink_strip.py; `render-rows` and `serve` are
//! those of tests/render_rows.py. `serve` reads one request a line ("S T a.txt b.txt ...")
//! and writes the batch's lines, then "END"; it tries the last good grid first. `watch` is
//! that of tools/hellolink_strip.py. `write` is that of tools/hellolink.py: it puts the slot
//! file into every slot (docs/specs/115.md, section 6). `assist` is tools/assistant.py: it
//! answers the player's questions with cards (section 7). `install` is that of
//! tools/hellolink.py, `install-reader` that of tools/install_reader.py (it installs this
//! program and the capture source), `package` tools/package.py.
#![forbid(unsafe_code)]

use hellolink::api::{Api, SEND_WAIT};
use hellolink::bitmap::{Bitmap, render};
use hellolink::capture;
use hellolink::follow::{WATCH_HELP, World, follow, parse_watch};
use hellolink::rows::rows_of_images;
use hellolink::slots;
use hellolink::{install, package};
use std::collections::HashMap;
use std::fs;
use std::io::{self, BufRead, BufReader, BufWriter, Write};
use std::num::IntErrorKind::{NegOverflow, PosOverflow};
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
                    // as argparse: an option is not a value ("-" and "-7" are)
                    None => match it.next() {
                        Some(v) if !is_option(v) => (name.to_string(), v.clone()),
                        _ => return Err(format!("{a} needs a value")),
                    },
                };
                opts.insert(name, value);
            }
            None => rest.push(a.clone()),
        }
    }
    Ok((opts, rest))
}

/// True for a word argparse takes as an option: it starts with "-" and is neither "-" nor a
/// negative number.
fn is_option(word: &str) -> bool {
    // argparse's negative number: ^-\d+$|^-\d*\.\d+$
    let negative = word.strip_prefix('-').is_some_and(|n| {
        let (whole, part) = n.split_once('.').unwrap_or((n, ""));
        let digits = |d: &str| d.bytes().all(|b| b.is_ascii_digit());
        digits(whole)
            && digits(part)
            && (if n.contains('.') {
                !part.is_empty()
            } else {
                !whole.is_empty()
            })
    });
    word.len() > 1 && word.starts_with('-') && !negative
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

/// A leading `~/` as the home folder, as Python's expanduser().
fn expand_home(path: &str) -> std::path::PathBuf {
    match (path.strip_prefix("~/"), std::env::var_os("HOME")) {
        (Some(rest), Some(home)) => std::path::PathBuf::from(home).join(rest),
        _ => path.into(),
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
    let usage = "usage: hellolink rows|render|render-rows|serve|watch|write|assist|install|install-reader|package|replay|depth ... (see the source's head)";
    let (cmd, rest) = args.split_first().ok_or(usage)?;
    if cmd == "-h" || cmd == "--help" {
        println!("{usage}");
        return Ok(());
    }
    // a reader or assistant run from an install holds its lock (install::hold_lock)
    let _lock = match (cmd == "watch" || cmd == "assist", std::env::current_exe()) {
        (true, Ok(exe)) => install::hold_lock(&exe)?,
        _ => None,
    };
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
                // through the World's writer thread: a stderr nobody reads does not hold the start
                writeln!(
                    world.err,
                    "the local API is at http://127.0.0.1:{} (GET /state, GET /events)",
                    api.port
                )
                .map_err(|e| format!("stderr: {e}"))?;
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
    if cmd == "built-from" {
        // what this program is built from, for `install-reader`'s check of its copy
        println!("{}", install::BUILT_FROM);
        return Ok(());
    }
    if cmd == "install-reader" {
        let (opts, rest) = parse(rest)?;
        if !rest.is_empty() || opts.keys().any(|k| k != "to" && k != "checkout") {
            return Err("usage: hellolink install-reader [--to DIR] [--checkout DIR]".into());
        }
        let to = match opts.get("to") {
            Some(to) => expand_home(to),
            None => install::default_folder()?,
        };
        let checkout = opts
            .get("checkout")
            .map_or(install::CHECKOUT, String::as_str);
        let exe = std::env::current_exe().map_err(|e| format!("this program: {e}"))?;
        let done = install::install_reader(&to, checkout.as_ref(), &exe, install::BUILT_FROM)?;
        println!("install-reader: {done}");
        return Ok(());
    }
    if cmd == "package" {
        let flags = ["--check", "--no-tests"];
        let (given, rest): (Vec<String>, Vec<String>) = rest
            .iter()
            .cloned()
            .partition(|a| flags.contains(&a.as_str()));
        let (opts, rest) = parse(&rest)?;
        if !rest.is_empty() || opts.keys().any(|k| k != "root") {
            return Err("usage: hellolink package [--check] [--no-tests] [--root DIR]".into());
        }
        let root = opts.get("root").map_or(install::CHECKOUT, String::as_str);
        let has = |f: &str| given.iter().any(|g| g == f);
        let mut say = |line: String| println!("{line}");
        return package::package(root.as_ref(), has("--check"), has("--no-tests"), &mut say);
    }
    if cmd == "install" {
        let (opts, rest) = parse(rest)?;
        let ([addons], true) = (&rest[..], opts.keys().all(|k| k == "slots")) else {
            return Err("usage: hellolink install ADDONS [--slots N]".into());
        };
        let n = match opts.get("slots") {
            None => 200,
            // a whole number too big for i64 is out of range, as in Python
            Some(v) => match v.trim().parse::<i64>() {
                Ok(n) => n,
                Err(e) if matches!(e.kind(), PosOverflow | NegOverflow) => 0,
                Err(_) => {
                    return Err(format!(
                        "install: argument --slots: invalid int value: {v:?}"
                    ));
                }
            },
        };
        if !(1..=999).contains(&n) {
            return Err("--slots must be 1 to 999".into());
        }
        slots::install(addons.as_ref(), n as usize)?;
        println!(
            "installed HelloLink and {n} slots in {}",
            slots::python_path(addons)
        );
        return Ok(());
    }
    if cmd == "assist" {
        let (opts, rest) = parse(rest)?;
        let usage = "usage: hellolink assist --addons DIR [--reader URL] [--log FILE]";
        if !rest.is_empty()
            || opts
                .keys()
                .any(|k| !["addons", "reader", "log"].contains(&k.as_str()))
        {
            return Err(usage.into());
        }
        let addons = opts.get("addons").ok_or(usage)?;
        let reader = opts
            .get("reader")
            .map_or("http://127.0.0.1:8787", |r| r.trim_end_matches('/'));
        let log = opts.get("log").map(std::path::Path::new);
        return hellolink::assistant::run(addons.as_ref(), reader, log, &Default::default());
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
        "depth" if !files.is_empty() => {
            let mut found = false;
            for f in &files {
                let line = match hellolink::depth::probe_depth(&Bitmap::new(&read(f)?)?) {
                    Some(d) => {
                        found = true;
                        serde_json::json!({"image": f, "levels": d.levels, "px": d.px,
                            "wrong": d.wrong, "of": d.of, "apart": d.apart,
                            "bits": 3.0 * (d.levels as f64).log2()})
                    }
                    None => serde_json::json!({"image": f, "row": false}),
                };
                writeln!(out, "{}", hellolink::rows::dumps(&line)).map_err(io)?;
            }
            if found {
                Ok(())
            } else {
                Err("no row of /hlink probe depth in any image".into())
            }
        }
        "replay" if files.len() == 1 => {
            let file = fs::File::open(&files[0]).map_err(|e| format!("{}: {e}", files[0]))?;
            hellolink::replay::replay(BufReader::new(file), out)
                .map_err(|e| format!("{}: {e}", files[0]))
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
