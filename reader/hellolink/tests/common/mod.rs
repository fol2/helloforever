//! The captures of tests/strip_watch_test.py and tests/strip_record_test.py, built the same
//! way: the row's squares from x = 2, drawn by `render` on 2560 x 4, as a stream gives them.
#![allow(dead_code)] // each test file uses a part

use hellolink::bitmap::{Bitmap, render};
use hellolink::strip1::{Chunk, pack_fast, pack_frame, row_colours};

pub const STATE: &[(&str, &[(&str, i64)])] = &[
    ("clock", &[("clock", 1)]),
    ("health", &[("healthMax", 1158)]),
];
pub const LEVELS: [Option<f64>; 4] = [Some(0.75), Some(1.0), None, None];
pub const WIDE: usize = 2560;

/// A change to every pixel's (red, green, blue), as the tests' `bend`.
pub type Bend = fn([u8; 3]) -> [u8; 3];

/// Every channel to 0 or 255: a palette that cannot be told apart.
pub fn crush(c: [u8; 3]) -> [u8; 3] {
    c.map(|v| if v > 127 { 255 } else { 0 })
}

/// Every channel 6 lower.
pub fn darker(c: [u8; 3]) -> [u8; 3] {
    c.map(|v| v.saturating_sub(6))
}

/// The capture's pixels (blue, green, red, alpha), `width` of the 2560 columns drawn.
pub fn capture(
    session: u16,
    depth: u8,
    levels: [Option<f64>; 4],
    frame: &[u8],
    bend: Option<Bend>,
    width: usize,
) -> Vec<u8> {
    let cells: String = row_colours(session, depth, levels, frame)
        .iter()
        .enumerate()
        .map(|(i, [r, g, b])| format!("{} 1 2 2 {r:.6} {g:.6} {b:.6}\n", 2 + i * 2))
        .collect();
    let bmp = Bitmap::new(&render(&cells, 1.0, 0, 0, WIDE, 4).unwrap()).unwrap();
    let mut raw = Vec::with_capacity(width * 16);
    for y in 0..4 {
        for x in 0..width {
            let mut c = bmp.rgb(x as f64, y as f64).unwrap();
            if let Some(bend) = bend {
                c = bend(c);
            }
            raw.extend([c[2], c[1], c[0], 255]);
        }
    }
    raw
}

pub fn bitmap(raw: &[u8], width: usize) -> Bitmap {
    Bitmap::from_bgra(width, 4, raw).unwrap()
}

/// A frame of session 4711 at a dwell of 0.1 s with the tests' state.
pub fn frame(seq: u32) -> Vec<u8> {
    pack_frame(4711, seq, 10, &pack_fast(STATE), None).unwrap()
}

/// The `shot` of tests/strip_watch_test.py.
pub struct Shot {
    pub seq: u32,
    pub levels: [Option<f64>; 4],
    pub chunk: Option<Chunk>,
    pub session: u16,
    pub depth: u8,
    pub bend: Option<Bend>,
    pub dwell: u8,
}

impl Default for Shot {
    fn default() -> Self {
        Shot {
            seq: 1,
            levels: LEVELS,
            chunk: None,
            session: 4711,
            depth: 4,
            bend: None,
            dwell: 10,
        }
    }
}

pub fn shot(s: Shot) -> Bitmap {
    let frame = pack_frame(
        s.session,
        s.seq,
        s.dwell,
        &pack_fast(STATE),
        s.chunk.as_ref(),
    )
    .unwrap();
    bitmap(
        &capture(s.session, s.depth, s.levels, &frame, s.bend, WIDE),
        WIDE,
    )
}

pub fn seq(seq: u32) -> Bitmap {
    shot(Shot {
        seq,
        ..Shot::default()
    })
}

pub fn blank() -> Bitmap {
    bitmap(&vec![0; WIDE * 4 * 4], WIDE)
}

/// Writes `body` to `path` as a script that may be run (mode 755).
///
/// A child `sh` writes it, so this test program never holds the file open for writing. When it
/// did (`fs::write`), another test thread that started a process at that moment gave its child
/// a copy of the descriptor until that child's exec, and running the script failed on Linux with
/// ETXTBSY, "Text file busy" (CI, 20 Nov 2026).
pub fn executable(path: &std::path::Path, body: &str) {
    let path = path.to_str().expect("a test path is UTF-8");
    let mut sh = std::process::Command::new("sh");
    sh.args([
        "-c",
        "printf '%s' \"$1\" > \"$2\" && chmod 755 \"$2\"",
        "sh",
        body,
        path,
    ]);
    let written = run_within(&mut sh, 10.0);
    assert!(written.success(), "{path} could not be written");
}

/// Runs `command` to its end, within `seconds`: past them it is killed and reaped, and the test
/// fails. Every wait on another process has a limit.
pub fn run_within(command: &mut std::process::Command, seconds: f64) -> std::process::ExitStatus {
    wait_within(command.spawn().expect("the command starts"), seconds)
}

/// Waits for `child` to end, within `seconds`: past them it is killed and reaped, and the test
/// fails.
pub fn wait_within(mut child: std::process::Child, seconds: f64) -> std::process::ExitStatus {
    let end = std::time::Instant::now() + std::time::Duration::from_secs_f64(seconds);
    loop {
        if let Some(status) = child.try_wait().expect("the command can be waited on") {
            return status;
        }
        if std::time::Instant::now() >= end {
            let _ = child.kill();
            let _ = child.wait();
            panic!("process {} did not end within {seconds} s", child.id());
        }
        std::thread::sleep(std::time::Duration::from_millis(5));
    }
}

/// A stand-in for the game's process (#348): a `sleep` with a command line of its own, stopped on
/// drop (a panic included). `pattern` finds it with `pgrep -f`; a test gives it to the reader in
/// HELLOLINK_GAME_PROCESS, so that `watch` sees a game that runs.
pub struct Game {
    child: std::process::Child,
    pub pattern: String,
}

impl Game {
    pub fn start() -> Game {
        static N: std::sync::atomic::AtomicU32 = std::sync::atomic::AtomicU32::new(0);
        let n = N.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
        let seconds = format!("600.{}{n:04}", std::process::id());
        let child = std::process::Command::new("/bin/sleep")
            .arg(&seconds)
            .spawn()
            .unwrap();
        Game {
            child,
            pattern: format!("sleep {seconds}$"),
        }
    }
}

impl Drop for Game {
    /// Kills the stand-in and reaps it, waiting at most 5 s (LESSONS: a limit on every wait).
    fn drop(&mut self) {
        let _ = self.child.kill();
        let end = std::time::Instant::now() + std::time::Duration::from_secs(5);
        while matches!(self.child.try_wait(), Ok(None)) && std::time::Instant::now() < end {
            std::thread::sleep(std::time::Duration::from_millis(20));
        }
    }
}
