# plan/ — work for someone with the game client or more GitHub access

Tasks the cloud session that reviewed 0.6.0 (11 Nov 2026) could not do itself: they need
the WoW Forever client, or GitHub permissions it did not have. Each file says what to do,
why, and how to tell it is done. Delete a file (and its line here) when its task is
finished.

| File | Task | Needs |
|------|------|-------|
| [01-in-game-verification.md](01-in-game-verification.md) | Verify the fight capture in the client (written for 0.6.0; 0.18.3 is installed), starting with `/hello selftest` | the game, with fights |
| [03-release.md](03-release.md) | Publish the release that task 01 verified (`v0.5.0` is the last tag) | task 01 finished |
| [04-matty-hunter-contract.md](04-matty-hunter-contract.md) | Matty Hunter is recorded (`status = ok`); still to check: the two commands, the key against the hint on screen, and that MH is never written to | the game, with MH |
| [05-assistant-link.md](05-assistant-link.md) | The record of what the game showed for the assistant's two channels (the slots, the live-state strip), the fight baseline and the probes of `docs/specs/115.md`; the open boxes are what is still to see | the game; the owner's play for fights |

Done on 11 Nov 2026: the CI workflow (now `.github/workflows/ci.yml`), the `v0.5.0` tag,
and the GitHub housekeeping (merged branches deleted, head branches deleted on merge).

The order of the work is in [`docs/roadmap.md`](../docs/roadmap.md).

## Open at the end of the session of 16 Nov 2026

- **#161 (HelloLink 0.5.1, object 17's step)** was merged after the brownout (19:21 UTC, 16 Nov
  2026) and installed; the local program was told that `step` is `null` past the list.
- **The owner's decision.** The brownout comes before a new GitHub default (blocked by default
  from 2 Dec 2026, GitHub's changelog of 2 Nov 2026): the AI-SDLC checks then run only if the
  owner allows `pull_request_target` in the repository's Actions event policy
  (https://gh.io/securely-using-pull_request_target). The workflow reads the PR as data and never
  runs its code. If the owner does not allow it, the checks need another design.
- **Installed now:**
  - HelloForever 0.18.3: the folder replaced with the build on 17 Nov 2026, the game closed. The
    seven installed files' SHA-256 equal the build's. Before that, its `.lua` files were copied in
    while the game ran (16 Nov 2026). The saved data of both accounts is backed up in
    `dist/sv-backup-before-0.18.3/`. Not yet seen: `/hello debug` with 0.18.3 twice.
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
  - HelloLink 1.3.0 (object 24 in binary; a binary object too large goes deflated, #251): on
    21 Nov 2026 at about 15:00, the game at its character screen, `Strip.lua` of main 22e6765
    copied in (the only Lua file that changed) and loaded at the banker's login. **When the game
    next closes, the TOC of main (1.3.0) goes in.** Backups: `dist/sv-backup-before-hellolink-1.3.0/`.
    The reader of main 22e6765 put in by `hellolink install-reader` while the local program had quit
    (`reader-previous-6` kept).
  - HelloLink 1.2.0 (object 26 in binary in format 3, #248): on 21 Nov 2026 at about 14:10, the
    game at its character screen, `Strip.lua` of main 5f480a8 copied in (the only Lua file that
    changed) and loaded at the banker's login. The TOC: as for 1.3.0 above (history). Backups: `dist/sv-backup-before-hellolink-1.2.0/`. The reader of main 5f480a8 put in by
    `hellolink install-reader` while the local program had quit (`reader-previous-5` kept).
  - HelloLink 1.1.0 (format 3 by default, #246): on 21 Nov 2026 at about 11:45, the game at its
    character screen, the Lua files of `HelloLink/` of main 80ad3cb copied in and loaded at the
    banker's login (hot-loaded, as the owner decision of 2026-11-12 allows for a changed Lua file;
    no file is new to the TOC). The TOC was copied too, against that decision, and put back to
    1.0.0's minutes later (history: 1.2.0 above replaced its Lua; the TOC to put in is 1.2.0's). The saved data moved to format 3 once, and
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
