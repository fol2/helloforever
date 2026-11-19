//! A stand-in for tools/strip_capture.swift, for the tests only: the Python tests' small
//! fake captures, as one program with modes.
//!
//!     fake_capture feed FILE A B     FILE's bytes, A seconds, FILE's bytes again, B seconds
//!     fake_capture flood FILE        FILE's bytes again and again, until it is stopped
//!     fake_capture junk              bytes that are not a frame, then the end
//!     fake_capture junk-hang         the same, then 60 s
//!     fake_capture fail              "no display" on stderr, exit 3
//!     fake_capture pass              nothing, exit 0
//!     fake_capture slow S            S seconds, then a 2 x 1 frame (none when S is 99)
//!     fake_capture hang              60 s, nothing
//!     fake_capture escape S          leaves a child that keeps stdout and stderr open for S
//!                                    seconds, in a process group of its own, then exits 0
//!
//! With HELLOLINK_FAKE_SCRIPT and HELLOLINK_FAKE_STATE set it is a capture tool that a reader
//! runs (`list`, `stream ...`): each run takes the next line of the script (its number is
//! kept in STATE/n, its arguments are added to STATE/calls, its process id to STATE/pids). A
//! line is one of
//!
//!     list TEXT        TEXT as the list of the displays
//!     fail TEXT        TEXT on stderr, exit 3 (also every run after the script's end)
//!     stream TOKEN...  frames of 2560 x 4, one a token:
//!         N            a good frame of seq N (session 4711, depth 4, health 0.75, power 1)
//!         N:MOD...     with each MOD: crush (no palette to tell apart), bad (a byte of the
//!                      fast block wrong), health=H, session=S, obj=I (chunk I of the
//!                      tests' object)
//!         blank        black pixels
//!         junk         bytes that are not a frame (and the end of the output)
//!         tiny         a frame of 2 x 1 black pixels (no row; 20 bytes on the pipe)
//!         escape=S     a child that keeps stdout and stderr open for S seconds, in a process
//!                      group of its own (out of the reach of a kill of the capture's group)
//!         err=TEXT     TEXT on stderr
//!         +S           S seconds without a frame
//!         hold         60 s at the end, until the reader stops it
//!         exit=C       exit C at the end (0 when not given)
//!
//! A SIGTERM ends it at once (the default), as it ends the real tool.
#![forbid(unsafe_code)]

use hellolink::bitmap::{Bitmap, render};
use hellolink::strip1::{Chunk, chunks_of, pack_fast, pack_frame, pack_object, row_colours};
use std::io::{self, Write};
use std::process::ExitCode;
use std::time::Duration;
use std::{env, fs, thread};

const STATE: &[(&str, &[(&str, i64)])] = &[
    ("clock", &[("clock", 1)]),
    ("health", &[("healthMax", 1158)]),
];
const OBJECT: &str = r#"{"map": 1437, "zone": "Wetlands", "sub": ""}"#;
const JUNK: &[u8] = b"JUNKJUNKJUNKJUNKJUNK";

fn nap(seconds: &str) -> Result<(), String> {
    let s: f64 = seconds
        .parse()
        .map_err(|_| format!("not seconds: {seconds}"))?;
    thread::sleep(Duration::from_secs_f64(s));
    Ok(())
}

/// A `sleep` that inherits stdout and stderr, in a process group of its own.
fn escape(seconds: &str) -> Result<(), String> {
    use std::os::unix::process::CommandExt;
    std::process::Command::new("sleep")
        .arg(seconds)
        .process_group(0)
        .spawn()
        .map(|_| ())
        .map_err(|e| format!("sleep: {e}"))
}

fn tiny() -> Vec<u8> {
    let mut out = b"HLC1".to_vec();
    out.extend(2u32.to_le_bytes());
    out.extend(1u32.to_le_bytes());
    out.extend([0; 8]);
    out
}

/// One frame of the script: the row's squares from x = 2 on 2560 x 4, as the tests draw it.
fn frame(token: &str) -> Result<Vec<u8>, String> {
    let (width, height) = (2560usize, 4usize);
    let mut raw = vec![0u8; width * height * 4];
    if token != "blank" {
        let mut words = token.split(':');
        let seq: u32 = words
            .next()
            .and_then(|s| s.parse().ok())
            .ok_or(format!("not a frame: {token}"))?;
        let (mut session, mut health, mut crush, mut bad, mut chunk) =
            (4711u16, 0.75, false, false, None);
        for word in words {
            match word.split_once('=') {
                None if word == "crush" => crush = true,
                None if word == "bad" => bad = true,
                Some(("health", v)) => health = v.parse().map_err(|_| token.to_string())?,
                Some(("session", v)) => session = v.parse().map_err(|_| token.to_string())?,
                Some(("obj", v)) => {
                    let parts = chunks_of(&pack_object(Some(OBJECT), false), 20);
                    let index: usize = v.parse().map_err(|_| token.to_string())?;
                    chunk = Some(Chunk {
                        oid: 3,
                        version: 500,
                        index: index as u8,
                        count: parts.len() as u8,
                        data: parts.get(index).ok_or(token.to_string())?.clone(),
                    });
                }
                _ => return Err(format!("not a frame: {token}")),
            }
        }
        let mut data = pack_frame(session, seq, 10, &pack_fast(STATE), chunk.as_ref())?;
        if bad {
            data[8] ^= 1; // a byte of the fast block read wrong: the check fails
        }
        let cells: String = row_colours(session, 4, [Some(health), Some(1.0), None, None], &data)
            .iter()
            .enumerate()
            .map(|(i, [r, g, b])| format!("{} 1 2 2 {r:.6} {g:.6} {b:.6}\n", 2 + i * 2))
            .collect();
        let bmp = Bitmap::new(&render(&cells, 1.0, 0, 0, width, height)?)?;
        for y in 0..height {
            for x in 0..width {
                let mut c = bmp.rgb(x as f64, y as f64).ok_or("off the image")?;
                if crush {
                    c = c.map(|v| if v > 127 { 255 } else { 0 });
                }
                let at = (y * width + x) * 4;
                raw[at..at + 4].copy_from_slice(&[c[2], c[1], c[0], 255]);
            }
        }
    }
    let mut out = b"HLC1".to_vec();
    out.extend((width as u32).to_le_bytes());
    out.extend((height as u32).to_le_bytes());
    out.extend(raw);
    Ok(out)
}

/// A run of the script; the exit code.
fn script(path: &str, state: &str, args: &[String]) -> Result<u8, String> {
    let at = |name: &str| format!("{state}/{name}");
    let n: usize = fs::read_to_string(at("n"))
        .ok()
        .and_then(|s| s.trim().parse().ok())
        .unwrap_or(0);
    fs::write(at("n"), (n + 1).to_string()).map_err(|e| e.to_string())?;
    let mut calls = fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(at("calls"))
        .map_err(|e| e.to_string())?;
    writeln!(calls, "{}", args.join(" ")).map_err(|e| e.to_string())?;
    let mut pids = fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(at("pids"))
        .map_err(|e| e.to_string())?;
    writeln!(pids, "{}", std::process::id()).map_err(|e| e.to_string())?;
    let text = fs::read_to_string(path).map_err(|e| format!("{path}: {e}"))?;
    let line = text
        .lines()
        .filter(|l| !l.starts_with('#') && !l.trim().is_empty())
        .nth(n)
        .unwrap_or("fail fake: done");
    let (kind, rest) = line.split_once(' ').unwrap_or((line, ""));
    let out = &mut io::stdout().lock();
    let io = |e: io::Error| e.to_string();
    match kind {
        "list" => {
            writeln!(out, "{rest}").map_err(io)?;
            Ok(0)
        }
        "fail" => {
            eprint!("{rest}");
            Ok(3)
        }
        "stream" => {
            let mut code = 0;
            for token in rest.split_whitespace() {
                if let Some(s) = token.strip_prefix('+') {
                    nap(s)?;
                } else if token == "hold" {
                    nap("60")?;
                } else if let Some(c) = token.strip_prefix("exit=") {
                    code = c.parse().map_err(|_| token.to_string())?;
                } else if let Some(text) = token.strip_prefix("err=") {
                    eprint!("{text}");
                } else if let Some(seconds) = token.strip_prefix("escape=") {
                    escape(seconds)?;
                } else if token == "tiny" {
                    out.write_all(&tiny())
                        .and_then(|_| out.flush())
                        .map_err(io)?;
                } else if token == "junk" {
                    out.write_all(JUNK).and_then(|_| out.flush()).map_err(io)?;
                } else {
                    out.write_all(&frame(token)?)
                        .and_then(|_| out.flush())
                        .map_err(io)?;
                }
            }
            Ok(code)
        }
        _ => Err(format!("not a script line: {line}")),
    }
}

fn run(args: &[String]) -> Result<u8, String> {
    if let (Ok(path), Ok(state)) = (
        env::var("HELLOLINK_FAKE_SCRIPT"),
        env::var("HELLOLINK_FAKE_STATE"),
    ) {
        return script(&path, &state, args);
    }
    let out = &mut io::stdout().lock();
    let io = |e: io::Error| e.to_string();
    let read = |path: &String| fs::read(path).map_err(|e| format!("{path}: {e}"));
    match args {
        [mode, file, a, b] if mode == "feed" => {
            let data = read(file)?;
            out.write_all(&data).and_then(|_| out.flush()).map_err(io)?;
            nap(a)?;
            out.write_all(&data).and_then(|_| out.flush()).map_err(io)?;
            nap(b)?;
        }
        [mode, file] if mode == "flood" => {
            let data = read(file)?;
            loop {
                out.write_all(&data).and_then(|_| out.flush()).map_err(io)?;
            }
        }
        [mode] if mode == "junk" => out.write_all(JUNK).map_err(io)?,
        [mode] if mode == "junk-hang" => {
            out.write_all(JUNK).and_then(|_| out.flush()).map_err(io)?;
            nap("60")?;
        }
        [mode] if mode == "fail" => {
            eprint!("no display");
            return Ok(3);
        }
        [mode] if mode == "pass" => {}
        [mode, s] if mode == "slow" => {
            nap(s)?;
            if s != "99" {
                out.write_all(&tiny())
                    .and_then(|_| out.flush())
                    .map_err(io)?;
            }
        }
        [mode] if mode == "hang" => nap("60")?,
        [mode, s] if mode == "escape" => escape(s)?,
        _ => return Err("usage: see the source's head".into()),
    }
    Ok(0)
}

fn main() -> ExitCode {
    let args: Vec<String> = env::args().skip(1).collect();
    match run(&args) {
        Ok(code) => ExitCode::from(code),
        Err(e) => {
            eprintln!("fake_capture: {e}");
            ExitCode::from(4)
        }
    }
}
