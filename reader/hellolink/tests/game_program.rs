//! The installed game's program (#348; review of #351, round 3): with `--addons` the reader knows
//! the install, and only that program counts as the game, not any path that ends as it does.

use hellolink::capture::{game_program, is_game};
use std::path::Path;

const FOREVER: &str = "/Applications/World of Warcraft/_forever_/World of Warcraft.app/Contents/MacOS/World of Warcraft";

#[test]
fn the_program_of_an_addons_folder() {
    assert_eq!(
        game_program(Path::new(
            "/Applications/World of Warcraft/_forever_/Interface/AddOns"
        )),
        Some(FOREVER.into()),
        "<flavour>/Interface/AddOns gives <flavour>/World of Warcraft.app/Contents/MacOS/World of Warcraft"
    );
}

#[test]
fn with_the_install_known_only_its_program_is_the_game() {
    let program = Some(Path::new(FOREVER));
    assert!(
        is_game(FOREVER, program),
        "the installed program is the game"
    );
    for other in [
        "/Applications/World of Warcraft/_retail_/World of Warcraft.app/Contents/MacOS/World of Warcraft",
        "/tmp/x/World of Warcraft.app/Contents/MacOS/World of Warcraft",
        "/Applications/World of Warcraft/World of Warcraft Launcher.app/Contents/MacOS/World of Warcraft Launcher",
    ] {
        assert!(
            !is_game(other, program),
            "{other} is not the installed game"
        );
    }
}

#[test]
fn with_the_install_not_known_the_path_s_end_is_the_game() {
    assert!(
        is_game(FOREVER, None),
        "the game's program, by its path's end"
    );
    assert!(
        !is_game(
            "/Applications/World of Warcraft/World of Warcraft Launcher.app/Contents/MacOS/World of Warcraft Launcher",
            None
        ),
        "the launcher is not the game"
    );
}
