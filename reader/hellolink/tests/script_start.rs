//! A script that a test writes and runs at once starts, while other threads of the same test
//! program start processes too. CI, 20 Nov 2026 (PR #214): "could not be started: Text file
//! busy (os error 26)" for a script `tests/processes/capture.rs` had just written.

#[path = "common/mod.rs"]
mod common;

use std::fs;
use std::path::Path;
use std::process::Command;
use std::thread;

const THREADS: usize = 8;
const EACH: usize = 40;

#[test]
fn scripts_written_while_other_threads_start_processes_all_start() {
    let dir = Path::new(env!("CARGO_TARGET_TMPDIR")).join("script-start");
    let _ = fs::remove_dir_all(&dir);
    fs::create_dir_all(&dir).unwrap();
    let busy: usize = thread::scope(|s| {
        let runs: Vec<_> = (0..THREADS)
            .map(|t| {
                let dir = &dir;
                s.spawn(move || {
                    let mut busy = 0;
                    for i in 0..EACH {
                        let path = dir.join(format!("s{t}-{i}"));
                        common::executable(&path, "#!/bin/sh\nexit 0\n");
                        match Command::new(&path).status() {
                            Err(e) if e.raw_os_error() == Some(26) => busy += 1,
                            got => assert!(got.unwrap().success(), "{path:?} did not exit 0"),
                        }
                    }
                    busy
                })
            })
            .collect();
        runs.into_iter().map(|r| r.join().unwrap()).sum()
    });
    assert_eq!(
        busy,
        0,
        "{busy} of {} scripts were busy (ETXTBSY) when they were started",
        THREADS * EACH
    );
}
