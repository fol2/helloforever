//! The game check (#348) is the game's own executable, as the kernel knows it: not a process that
//! names itself so (its `argv[0]`, which macOS's `pgrep` compares), and not the game's launcher,
//! whose name begins as the game's ("World of Warcraft Launcher"; review of #351, round 2).

use std::os::unix::process::CommandExt;
use std::process::{Child, Command};

/// A stand-in, stopped on drop (a panic included), reaped within 5 s (LESSONS: a limit on every
/// wait). One process: `arg0` sets its name, no shell.
struct Named(Child);

impl Named {
    fn start(arg0: &str) -> Named {
        let child = Command::new("/bin/sleep").arg0(arg0).arg("30").spawn().unwrap();
        std::thread::sleep(std::time::Duration::from_millis(200));
        Named(child)
    }
}

impl Drop for Named {
    fn drop(&mut self) {
        let _ = self.0.kill();
        let end = std::time::Instant::now() + std::time::Duration::from_secs(5);
        while matches!(self.0.try_wait(), Ok(None)) && std::time::Instant::now() < end {
            std::thread::sleep(std::time::Duration::from_millis(20));
        }
    }
}

#[test]
fn a_process_named_as_the_game_or_its_launcher_is_not_the_game() {
    let before = hellolink::capture::game_runs();
    for arg0 in [
        "World of Warcraft",
        "World of Warcraft Launcher",
        "/Fake/World of Warcraft.app/Contents/MacOS/World of Warcraft",
    ] {
        let named = Named::start(arg0);
        assert_eq!(
            hellolink::capture::game_runs(),
            before,
            "a process named {arg0:?} does not make the game run (whether the game runs on this \
             machine or not)"
        );
        let path = hellolink::capture::executable(named.0.id() as i32);
        assert!(
            path.as_deref().is_some_and(|p| p.ends_with("/sleep")),
            "the kernel gives the executable's own path, not the name {arg0:?} (got {path:?})"
        );
    }
}
