//! The game check of `watch` (#348) is the game's process, not any command line that names its
//! path. Seen on 24 Nov 2026: the reader of #349 took a capture at 11:33 with the game closed;
//! `pgrep -f` with the game's path also matches a shell whose arguments hold that path.

use std::process::{Child, Command};

/// A process whose command line holds the game's binary path, stopped on drop (a panic
/// included), reaped within 5 s (LESSONS: a limit on every wait).
struct Holder(Child);

impl Drop for Holder {
    fn drop(&mut self) {
        let _ = self.0.kill();
        let end = std::time::Instant::now() + std::time::Duration::from_secs(5);
        while matches!(self.0.try_wait(), Ok(None)) && std::time::Instant::now() < end {
            std::thread::sleep(std::time::Duration::from_millis(20));
        }
    }
}

#[test]
fn a_command_line_that_names_the_game_is_not_the_game() {
    let before = hellolink::capture::game_runs();
    let path = format!(
        "/Nowhere-{}/World of Warcraft.app/Contents/MacOS/World of Warcraft",
        std::process::id()
    );
    let _holder = Holder(
        Command::new("/bin/sh")
            .args(["-c", &format!("sleep 30; : '{path}'")])
            .spawn()
            .unwrap(),
    );
    std::thread::sleep(std::time::Duration::from_millis(200));
    assert_eq!(
        hellolink::capture::process_runs(&path),
        Ok(true),
        "the holder runs, and its command line names the game's path"
    );
    assert_eq!(
        hellolink::capture::game_runs(),
        before,
        "a shell that names the game's path does not make the game run (whether the game runs \
         on this machine or not)"
    );
}
