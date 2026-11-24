# plan/ — work for someone with the game client or more GitHub access

Tasks the cloud session that reviewed 0.6.0 (11 Nov 2026) could not do itself: they need
the WoW Forever client, or GitHub permissions it did not have. Each file says what to do,
why, and how to tell it is done. Delete a file (and its line here) when its task is
finished.

| File | Task | Needs |
|------|------|-------|
| [01-in-game-verification.md](01-in-game-verification.md) | Verify the fight capture in the client (written for 0.6.0; 0.19.0 is installed), starting with `/hello selftest` | the game, with fights |
| [03-release.md](03-release.md) | Publish the release that task 01 verified (`v0.5.0` is the last tag) | task 01 finished |
| [04-matty-hunter-contract.md](04-matty-hunter-contract.md) | Matty Hunter is recorded (`status = ok`); still to check: the two commands, the key against the hint on screen, and that MH is never written to | the game, with MH |
| [05-assistant-link.md](05-assistant-link.md) | The record of what the game showed for the assistant's two channels (the slots, the live-state strip), the fight baseline and the probes of `docs/specs/115.md`; the open boxes are what is still to see | the game; the owner's play for fights |

Done on 11 Nov 2026: the CI workflow (now `.github/workflows/ci.yml`), the `v0.5.0` tag,
and the GitHub housekeeping (merged branches deleted, head branches deleted on merge).

The order of the work is in [`docs/roadmap.md`](../docs/roadmap.md).

## Open at the end of the session of 16 Nov 2026

- **#161 (HelloLink 0.5.1, object 17's step)** was merged after the brownout (19:21 UTC, 16 Nov
  2026) and installed; the local program was told that `step` is `null` past the list.
- **The owner's decision, made.** GitHub blocks `pull_request_target` by default from 2 Dec 2026 (its changelog of 2 Nov
  2026). On 24 Nov 2026 the owner allowed it (in chat: "I'll allow it"): the repository's Actions policy
  `allow-ai-sdlc-pull_request_target` (id 17366, active) targets `.github/workflows/ai-sdlc-checks.yml` and
  `ai-sdlc-checks-impl.yml`, and allows the default events and `pull_request_target`. The list first saved had no
  `pull_request_target` (an active list without it blocks the event); at the owner's word the agent added
  it and the second path by the REST API (`PUT repos/fol2/helloforever/actions/policies/17366`, 09:58 UTC) and read it
  back. The workflow reads the PR as data and never runs its code.
- **Installed now:**
  - The reader of main f4c8ffd (#351: the game check is the installed game's program, not a command line or a name):
    on 24 Nov 2026 at 13:16, the game closed (`pgrep -l '^World of Warcra'`: exit 1), JevCompanion stopped `watch`
    and `assist` (it quit its app; `pgrep` then found neither), `hellolink install-reader` put the build of clean main
    in `~/Library/Application Support/HelloLink/reader` (`VERSION` f4c8ffd332ad, the program equal to the build by
    `cmp`; the earlier one kept as `reader-previous-2`), and JevCompanion started both again with the absolute
    `--addons` of the game. Seen with the game closed, while two decoys ran for 15 s (a `/bin/sh` whose arguments held
    the installed game's path, which #349's `pgrep -f` counted as the game; a `/bin/sleep` named "World of Warcraft" by
    its `argv[0]`, which a check by name alone counts): `pgrep -lf strip_capture`, sampled once a second, found none;
    the run's record (`records/2026-11-24-1316.jsonl`) held only its header; `/state` said `"condition": "waiting"`.
    Still to see: the installed game found by the check when it starts (the next start of the game). Why a second
    install: at 11:33, with the game closed, the reader of #349 took one capture (`records/2026-11-24-1124.jsonl`, its
    second line), the game's own logs showing no start before 12:38.
  - The reader of main 1573870 (#349: no picture while the game is not running): on 24 Nov 2026 at 11:24, the game closed
    (`pgrep -f 'World of Warcraft.app/Contents/MacOS/World of Warcraft'`: exit 1), JevCompanion stopped `watch` and
    `assist` (it quit its app; `pgrep` then found neither),
    `hellolink install-reader` put the build of clean main in `~/Library/Application Support/HelloLink/reader` (`VERSION`
    1573870003c1, the program equal to the build by `cmp`; the earlier one kept as `reader-previous-18`), and JevCompanion
    started both again: `pgrep -lf` showed `watch` and `assist` with the flags they had at 08:48 (only `--record`'s file
    new). Seen with the game closed: the run's record (`records/2026-11-24-1124.jsonl`) held only its header line after
    12 s and again at 11:28; `pgrep -lf strip_capture`, sampled once a second for 6 s, found none; `/events` gave
    a snapshot with `"condition": "waiting"` (it carries no `why`). Before it, the record of 04:01 grew to 215 KB by
    08:48, the game closed throughout (its saved data last written 01:19). Still to see: the `why` "the game is not
    running" through the API (the snapshot has no such field), and the game found by the check when it starts (the next
    start of the game).
  - HelloLink 2.6.1 (#344: `eventsSessions`, the last 6 sessions' event counts): on 24 Nov 2026 at 01:34:07, the game closed
    (`pgrep -f 'Warcraft.app/Contents/MacOS/'`: exit 1), the five files of main 6db58a7 copied over the installed ones, each
    equal to main by `cmp` (`## Version: 2.6.1`). Loads at the next start of the game. Backups:
    `dist/sv-backup-before-hellolink-2.6.1/`.
  - HelloLink 2.6.0 (#340: object 10's `spells`): on 23 Nov 2026 at 20:35:27, the game closed (`pgrep -f
    'Warcraft.app/Contents/MacOS/'`: exit 1), the five files of main f94d7e1 copied over the installed ones, each equal to
    main by `cmp` (`## Version: 2.6.0`). Seen in the game at 20:37 on the level 1 test character (`plan/05`, the 2.6.0
    box). Backups: `dist/sv-backup-before-hellolink-2.6.0/`.
  - HelloLink 2.5.1's Lua (#337: object 28, the open windows; #338: the spellbook and professions probe): on 23 Nov 2026
    at 19:40:36, the game running (the owner playing, in chat: "don't need to wait for me. if you ened you can ask me to
    reload"),
    `Strip.lua` and `Probe.lua` of main 7e08eb7 copied over the installed ones (each equal to main by `cmp`;
    `Assist.lua` and `HelloLink.lua` were already equal). Loaded by the owner's `/reload`s at about 19:42: `/state`
    has object 28 (`null`: none of the merchant, loot and quest windows open), and the login run of 19:42:18 has the new
    probe lines (`plan/05`, the 2.5.1 box), so the 2.5.1 Lua was loaded while the installed TOC still said 2.4.0. The TOC
    went in at 19:48:26, after the owner closed the game at 19:48:15 (`pgrep -f 'Warcraft.app/Contents/MacOS/'`: exit
    1); then all five files equal main 7e08eb7 by `cmp` (`## Version: 2.5.1`). Backups:
    `dist/sv-backup-before-hellolink-2.5.1/`.
  - The reader of main 91bdb81 (#332: `hellolink history` and `assist --history`, the saved data's usual time): installed
    on 23 Nov 2026 at 15:31, the game closed (`pgrep -f 'Warcraft.app/Contents/MacOS/'`: exit 1 at 14:02 and at 15:34), after
    the local program's session said it had stopped `watch` and `assist` (none ran, by `pgrep`); `VERSION` names 91bdb81, the earlier install is `reader-previous-17`. The local program starts `assist`
    without `--history` for now (its arguments by `ps`: `--addons` and `--reader` only), so the card is as before. `watch`
    did not change. The local program started both again from the install at 15:31:54 (`ps -o lstart`).
  - Before it, the reader of main 765e79f (#321: a game window with no row is searched again, five times, before the displays):
    installed on 23 Nov 2026 at about 04:11, the local program stopped and started it; it runs `strip_capture --window
    Wow stream 0 0 0 2560 6 60`, and the place file holds `{"display": -1, ...}` (by `ps` and the file, 04:12).
    Before it, the reader of main 5bcd97b (#316, #317), installed at about 03:02, read the window too, but after the
    owner's `/reload`s at 03:43 and 03:53 it said "the row is read from display 1, not from the game's window" and
    streamed display 1 (the place file held display 1 at 03:53): #321's cause. The first install, main f718ef0 at
    02:50, had started on a remembered display, fixed by #317. Earlier installs: `reader-previous-14` to `-16`.
  - HelloLink 2.4.0 (#328: object 10's talents gain the bought `nodes`), with 2.3.1 (#326: the names (25) are not
    built while the refresh round sends them): on 23 Nov 2026 at 14:02, the game closed (`pgrep -f
    'Warcraft.app/Contents/MacOS/'`: exit 1, no match), the five files of main 2ce54a4 copied over the five installed
    ones, as for 2.3.0 (`## Version: 2.4.0`; each file equal to main by `cmp`). Loads at the next start of the game.
    Backups: `dist/sv-backup-before-hellolink-2.4.0/` (the addon and `SavedVariables/HelloLink.lua`).
  - HelloLink 2.3.0 (#325: object 11's current step gains `lines`), with 2.2.0 (#323: object 10's `talents`) and
    2.2.1 (#324: the probe counts the quest and talent events, `eventsAtLogout`): on 23 Nov 2026 at 08:54, the game
    closed (`pgrep -f 'Warcraft.app/Contents/MacOS/'`: exit 1, no match), the five files of main bb61998 copied over
    the five installed ones, the TOC included, in place of a folder replacement: the folder holds the same five
    files before and after, none added or removed (`## Version: 2.3.0`; each file equal to main by `cmp`). Loads at the next start of the game.
    Backups: `dist/sv-backup-before-hellolink-2.3.0/` (the addon and `SavedVariables/HelloLink.lua`).
  - HelloLink 2.1.1 (#319: object 7, the waypoint, asked for every 5th decision; the squash title says "(7) and the
    quests (5)", but the code merged asks for 7 only, the review's round 2): on 23 Nov 2026 at 03:51:58, the game
    running, the four Lua files of main 936865b copied in (their times on disk); loaded by the owner's `/reload` at
    about 03:53 (session 21598 in `/state`, live). The TOC goes in when the game next closes (a background wait).
  - HelloLink 2.1.0 (#318: 4096, on a flight path): on 23 Nov 2026 at about 03:24, the game running, the Lua files
    of main b8a95e2 copied in; loaded by the owner's `/reload` at about 03:43 (session 21597, live, 26 objects).
    Backups: `dist/sv-backup-before-hellolink-2.1.0/`.
  - HelloLink 2.0.2 (a line in the chat keeps its "|", #312): on 23 Nov 2026 at about 00:25, the game running, the
    four Lua files of main 3441016 copied in over 2.0.1's; loaded by a `/reload` at about 00:55 (the reader's session 21594
    in `/state`, read by `curl`; the usage line seen in the owner's screenshot: the 2.0.2 box of `plan/05`). The TOC of main goes in when the game next closes (a background wait, now 2.0.2's).
  - HelloLink 2.0.1 (the JSON encoders of the binary objects leave the addon, #310): on 22 Nov 2026 at about
    23:50, the game running, the four Lua files of main 9a94923 copied in over 2.0.0's (never loaded); loaded by
    the owner's `/reload` at about 00:05 on 23 Nov (the 2.0.0 box of `plan/05`). Backups of 1.26.0 and the saved data: `dist/sv-backup-before-hellolink-2.0.0/`.
  - HelloLink 2.0.0 (format 3 only, #309): on 22 Nov 2026 at about 23:37, the game running, the four Lua files
    of main 3de81a3 copied in; replaced by 2.0.1's before any `/reload`.
  - HelloLink 1.26.0 (format 3's refresh on every 6th decision, #308): on 22 Nov 2026 at about 22:30, the game
    closed, every file of main dae880c, the TOC included; the owner's hour of play ran on it (the 1.26.0 box of
    `plan/05`). The 1.25.1 TOC had gone in at 21:13, when the game closed. Backups:
    `dist/sv-backup-before-hellolink-1.26.0/`.
  - HelloLink 1.25.1 (the settings line wraps inside the window, #305): on 22 Nov 2026, the game running,
    `HelloLink.lua` of main 14e197f copied in; loaded by a `/reload` the same day (checked: the 1.25.1 box of
    `plan/05`). The TOC of main went in at 21:13, when the game closed.
    Backups: `dist/sv-backup-before-hellolink-1.25.1/`.
  - HelloLink 1.25.0 (the strip says when its row has no room for a chunk, #303): on 22 Nov 2026, the game running,
    `HelloLink.lua` and `Strip.lua` of main 6bc20dd copied in; loaded by a `/reload` the same day (checked: the
    1.25.0 box of `plan/05`). **The TOC of main goes in when the game next closes** (a background wait; the installed
    TOC still says 1.18.0, since the game has not closed since that install). Backups:
    `dist/sv-backup-before-hellolink-1.25.0/`. The reader is unchanged (6bcb7a5).
  - HelloLink 1.23.0 (#201: an empty GUID is no GUID, #298) and 1.24.0 (lanes behind `/hlink strip lanes`, #299):
    on 22 Nov 2026, the game running, `HelloLink.lua`, `Strip.lua` and `Probe.lua` of main 6bcb7a5 copied in;
    they load at the next login or `/reload`. **When the game next closes, the TOC of main goes in** (a
    background wait copies it then). Backups: `dist/sv-backup-before-hellolink-1.24.0/`. The reader of 6bcb7a5 put in
    by `hellolink install-reader` after JevCompanion stopped the local program (`reader-previous-13` kept);
    JevCompanion started it again.
  - HelloLink 1.22.0 (ramp and 9-bit rows behind switches, #294): on 22 Nov 2026, the game running, `HelloLink.lua`
    and `Strip.lua` of main 8f6c11a copied in; loaded at the next login the same day. The TOC at the next close.
    Backups: `dist/sv-backup-before-hellolink-1.22.0/`. The reader of main 8f6c11a put in by `hellolink install-reader`
    after JevCompanion stopped the local program (`reader-previous-12` kept); JevCompanion started it again.
  - HelloLink 1.21.0 (the probe's floor, #288; the fall-back by bits, #290): on 22 Nov 2026, the game running,
    `HelloLink.lua` and `Strip.lua` of main d6fa792 copied in; loaded at the level 1 test character's next
    login the same day. **When the game next closes, the TOC of main goes in** (1.19.0 and 1.20.0 too).
    Backups: `dist/sv-backup-before-hellolink-1.21.0/`.
  - HelloLink 1.19.0 (object 10's `realmSaved`, #285): on 22 Nov 2026, the game running, `Strip.lua` and
    `Probe.lua` of main 6792e51 copied in (each written beside its copy, then renamed); they load at the
    next `/reload` or login. **When the game next closes, the TOC of main goes in** (the only file that
    differs). Backups: `dist/sv-backup-before-hellolink-1.19.0/`.
  - HelloForever 0.19.0 (a GUID in each record, #280) and HelloLink 1.18.0 (object 10's `guid`;
    `seen` and `looks` under the GUID, #281), spec 276 step 2: on 22 Nov 2026, the game closed.
    HelloForever: the folder replaced with the build of main 6a5a943 (the seven files' SHA-256 equal
    the build's); backups in `dist/sv-backup-before-0.19.0/` (both accounts and the 0.18.4 folder).
    A dry run on a copy of the saved data: both characters with a HelloLink full name claim their
    record by name, both `Name-` records are marked `split`, no new record. HelloLink: `Strip.lua`
    and the TOC of main a6a19a7 copied in; the folder equals main; backups in
    `dist/sv-backup-before-hellolink-1.18.0/`. Both load at the next login (not yet seen).
  - HelloLink 1.17.0 (the probe's `account` line, #278): on 22 Nov 2026, the game closed, `Probe.lua`
    and the TOC of main 477ecd4 copied in (each written beside its copy, then renamed); the HelloLink
    folder equals main. Replaced by 1.18.0 before a login; 1.18.0 keeps its probe line. Backups: `dist/sv-backup-before-hellolink-1.17.0/`.
  - HelloForever 0.18.4 (a character keeps its saved realm when the client gives none, #275): the
    folder replaced with the build of main 8d4e422 on 22 Nov 2026, the game closed. The seven
    installed files' SHA-256 equal the build's. The saved data of both accounts and the 0.18.3
    folder are backed up in `dist/sv-backup-before-0.18.4/`. A dry run of `ns.Char` on a copy of
    the saved data: both characters with a `Name-` record go back to their `Name-<realm>` record,
    and one's fight read state (41 markers) moves once. Not yet seen in the game: the first login
    with 0.18.4 (the key it uses, and no fight filed again). The same day, `HelloLink/Strip.lua` of
    8d4e422 (a comment only) was copied in; the HelloLink folder equals main.
  - HelloForever 0.18.3 (history): the folder replaced with the build on 17 Nov 2026, the game
    closed. Backups in `dist/sv-backup-before-0.18.3/`.
  - HelloLink 0.8.3: the folder replaced with `HelloLink/` of `main` 32186fa (#216) on 20 Nov 2026,
    the game closed. The installed files equal it (`diff -r`). The 200 slots were not changed.
    HelloLink's saved data, one account's, and the 0.8.2 folder are backed up in
    `dist/sv-backup-before-hellolink-0.8.3/`. The format-2 probe (`plan/05`, section 26) ran in the
    play session of 20 Nov 2026 with 0.8.2 (16:03 to 16:06); 0.8.3 is not yet run in the game.
    Not yet run in the game: objects 18 to 23 and the grown 11, 14, 15 (`plan/05-assistant-link.md`,
    sections 22 and 24), and 0.8.1's step elements. Its full name was seen in the reader's `/state`
    on 20 Nov 2026 (object 10, source `loot`); not yet checked in the saved data.
  - The reader in Rust, `main` bcaecdf (#195, the switch): `hellolink`, `strip_capture.swift` and
    `VERSION` in `~/Library/Application Support/HelloLink/reader/`, put there by
    `hellolink install-reader` on 20 Nov 2026 while the local program had stopped its reader. The
    installed program equals the build (`cmp`), and `hellolink built-from` gives 01a70ea368270992.
    The Python install is kept beside it as `reader-previous-1`. The local
    program now starts `hellolink watch` and `hellolink assist` with the options it gave the Python
    files. One play session on it, 20 Nov 2026, 10:54 to about 11:27: at 11:04 `/state` was `live`
    with 22 objects, object 10 with 0.8.1's `fullName` (source `loot`) and object 11 with the guide's
    steps; `watch` used 0.2% CPU and 4.7 MB. The local program restarted both at 11:17; that run
    read the row in 5.6 s and logged 42 lines, none an error. `assist` wrote the 200 slots (last at
    11:28, assist seq 3). The restart overwrote the log of the first run. If the Rust reader fails,
    it is fixed, not replaced: the owner, 19 Nov 2026, "we won't return to python. we'll fix the
    rust instead".
  - HelloLink 0.10.0 (format 2 by setting, objects 24 to 27; #227, #229): its files copied
    into the folder on 20 Nov 2026 with the game running, at the owner's word ("i'll do
    hotload"): every file of `HelloLink/`, the TOC included. 0.9.0 at 23:08: its Lua files were
    loaded by the owner's `/reload` (the reader then read format 2 after `/hlink strip format
    2`). The client reads a TOC only at its start, so the TOC's version 0.9.0 was not loaded
    then; no file is new to the TOC, so the files it lists are the same. 0.10.0 at 23:55; the
    game closed after it, so it is loaded at the next start. The installed
    folder equals main 102e804 (`diff -r`). Backups: `dist/sv-backup-before-hellolink-0.9.0/`
    and `-0.10.0/` (the saved data and the folder before). Format 1 is the default; the owner
    switched to format 2 for the play of `plan/05`, section 27.
  - The reader of main 43f0141 (format 2, #226 and #228): put in by `hellolink install-reader`
    on 20 Nov 2026 at 23:11 while the local program had quit; the program equals the build
    (`cmp`); the earlier install is kept as `reader-previous-2`.
  - The reader of main e87c214 (its first line names its start and its build, #270): put in by
    `hellolink install-reader` on 21 Nov 2026 at 23:25, after JevCompanion stopped the local program
    (`reader-previous-11` kept). JevCompanion now appends `reader.log` with a launch line, so a relaunch
    keeps the runs before it: seen at once, the 29 lines from before unchanged, then the line
    `=== launch 2026-11-21T23:25:07Z` and a reader note that reads `started 2026-11-21T23:25:07+00:00,
    hellolink e87c21434000` (the log puts the seconds and `note` before it).
  - HelloLink 1.16.0 (object 10 with this client's empty realm; an empty ammunition slot left out,
    #273): on 22 Nov 2026, the game closed, `Strip.lua` and the TOC of main ca02282 copied in (the only
    files that changed since 1.15.0; each written beside its copy, then renamed). The installed folder
    equals main (`diff -rq`); it loads at the next game start. No reader change. Backups:
    `dist/sv-backup-before-hellolink-1.16.0/` (the saved data and the folder before).
  - HelloLink 1.15.0 (objects 3, 8, 12, 4 and 14 in binary, the lanes probe, the window probes: #264 to
    #268): on 21 Nov 2026 at 20:33, the game at its character screen. The reader of main c3b5554 went in
    first by `hellolink install-reader`, after JevCompanion stopped the local program
    (`reader-previous-10` kept; the reader before it could not read the new shapes). Then `Strip.lua`,
    `Probe.lua` and `HelloLink.lua` of c3b5554 were copied in (the Lua files that changed since 1.10.0);
    they load at the next login. The TOC: as for 1.6.0 below. Backups:
    `dist/sv-backup-before-hellolink-1.15.0/`.
  - HelloLink 1.10.0 (objects 9, 2 and 13 in binary in format 3, #260, #261, #262): on 21 Nov 2026
    at 18:31, the game at its character screen, the reader of main f7673f8 put in first by
    `hellolink install-reader`, after JevCompanion stopped the local program and said port 8787 was
    free (`reader-previous-9` kept; the reader before it could not read those shapes). Then
    `Strip.lua` of f7673f8 copied in (the only Lua file that changed since 1.7.0); it loads at the next
    login. The TOC: as for 1.6.0 below. Backups: `dist/sv-backup-before-hellolink-1.10.0/`.
  - HelloLink 1.7.0 (the events probe, #259): on 21 Nov 2026 at 17:41, the game at its character
    screen, `Probe.lua` of main ef5a203 copied in (the only Lua file that changed since 1.6.0); it
    loads at the next login. The TOC: as for 1.6.0 below.
  - HelloLink 1.6.0 (the event ring of 1.5.0, #255, and the back-off, #257): on 21 Nov 2026 at
    17:27, the game at its character screen, `Strip.lua` of main 550eefc copied in (the only Lua
    file that changed since 1.4.0); it loads at the next login. **When the game next closes, the TOC
    of main goes in.** Backups: `dist/sv-backup-before-hellolink-1.6.0/`. The reader of main 550eefc
    put in by `hellolink install-reader` at 17:28, after JevCompanion stopped the local program and
    asked for it (`reader-previous-8` kept); JevCompanion started it again.
  - HelloLink 1.4.0 (object 27 in binary, #253): on 21 Nov 2026 at 15:34, the game at its
    character screen, `Strip.lua` of main cc34c56 copied in (the only Lua file that changed) and
    loaded at the level 1 test character's login. **When the game next closes, the TOC of main goes in (history: 1.6.0 above).**
    Backups: `dist/sv-backup-before-hellolink-1.4.0/`. The reader of main cc34c56 put in by
    `hellolink install-reader` while the local program had quit (`reader-previous-7` kept). The
    saved format after the logout: 3.
  - HelloLink 1.3.0 (object 24 in binary; a binary object too large goes deflated, #251): on
    21 Nov 2026 at about 15:00, the game at its character screen, `Strip.lua` of main 22e6765
    copied in (the only Lua file that changed) and loaded at the level 1 test character's login. **When the game
    next closes, the TOC of main goes in (history: 1.4.0 above).** Backups: `dist/sv-backup-before-hellolink-1.3.0/`.
    The reader of main 22e6765 put in by `hellolink install-reader` while the local program had quit
    (`reader-previous-6` kept).
  - HelloLink 1.2.0 (object 26 in binary in format 3, #248): on 21 Nov 2026 at about 14:10, the
    game at its character screen, `Strip.lua` of main 5f480a8 copied in (the only Lua file that
    changed) and loaded at the level 1 test character's login. The TOC: as for 1.3.0 above (history). Backups: `dist/sv-backup-before-hellolink-1.2.0/`. The reader of main 5f480a8 put in by
    `hellolink install-reader` while the local program had quit (`reader-previous-5` kept).
  - HelloLink 1.1.0 (format 3 by default, #246): on 21 Nov 2026 at about 11:45, the game at its
    character screen, the Lua files of `HelloLink/` of main 80ad3cb copied in and loaded at the
    level 1 test character's login (hot-loaded, as the owner decision of 2026-11-12 allows for a changed Lua file;
    no file is new to the TOC). The TOC was copied too, against that decision, and put back to
    1.0.0's minutes later (history: later releases above replaced its Lua; the pending TOC is in the 1.3.0 entry). The saved data moved to format 3 once, and
    says format 3 after the check of `plan/05`, section 28. Backups:
    `dist/sv-backup-before-hellolink-1.1.0/` (the saved data and the folder before), and before
    that `dist/sv-backup-before-hellolink-format3/` (11:00: `Strip.lua` of 86d91e9 alone).
  - The reader of main 86d91e9 (format 3, #243; a read a signal interrupts is read again, #237):
    put in by `hellolink install-reader` on 21 Nov 2026 at about 10:58, while the local program
    had quit at its holder's word; the earlier install is kept as `reader-previous-4`. The local
    program started it again at once.
  - The record for format 2 (#213, step 2): from 20 Nov 2026, 15:45, the local program starts
    `hellolink watch` with `--record ~/Library/Application Support/HelloLink/records/<YYYY-MM-DD-HHMM>.jsonl`
    (fol2/jev-playground#323), a file a reader start, the folder 0700. The first file grew about
    9 KB a second in play (15:56). It stays on this Mac; never commit one.
  - Saved-data backups before an install: HelloForever's in `dist/sv-backup-before-<version>/`,
    HelloLink's in `dist/sv-backup-before-hellolink-<version>/`.
- **Game checks still open:** `plan/05-assistant-link.md`, sections 12 to 20 (an enchanted or
  suffixed item, a class trainer, a trainer filter turned off, the cards' texts, a quiver or
  reagent bag with free slots, the AddOns options pages, the other settings controls), and most
  of `plan/01`. On the hunter's gear none had an enchant or a suffix: the owner to confirm.
- **Driving the game.** Game checks drive the client in the background only (no full-screen
  control; the owner works meanwhile): the owner presses Play in Battle.net (in the background it
  could not be clicked while the window sat as a Stage Manager thumbnail); Enter World, clicks,
  keys and chat lines (`Return`, the typed line, a look at the edit box, `Return`) go to the game's
  window in the background; long results are read from the SavedVariables after `/reload`.
  From the evening of 16 Nov 2026 the keys are sent with the `agent-desktop` CLI (`press <key>
  --app Wow`: the game keeps its place behind the other windows). A chat line: the `/` key
  opens the chat (the strip's flag 8192 says so), the rest is pasted (`cmd+v`; the clipboard's
  text is put back), one Return sends it. Typed letter by letter, about one key in forty was
  lost; a second Return after one that did work opens an empty Say box, so Return is pressed
  once and the edit box looked at. A click needs the real pointer and was not used: the AddOns
  options pages and the windows' controls are still to check.
- **Next by the roadmap:** the `quests` card is set aside (the owner, 16 Nov 2026: "please skip
  quest for now"); the `gear` card waits for a probe in fights; line 1 (`/hello selftest`) for
  fights.

The companion list for the offline pipeline is `plan/` in its own (private) repository.
