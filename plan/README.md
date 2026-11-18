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
  - HelloLink 0.7.0: the folder replaced with `HelloLink/` of `main` 9f32fd9 on 18 Nov 2026, the
    game closed. The four installed files equal it. The 200 slots were not changed. HelloLink's
    saved data, one account's, is backed up in `dist/sv-backup-before-hellolink-0.7.0/`. Not yet
    run in the game: object 18, the hearthstone, is unseen (`plan/05-assistant-link.md`,
    section 22).
  - The reader of `main` 9f32fd9: 18 objects. Its six installed files equal `tools/` of `main`.
    It was installed while no reader ran. It runs again from the installed folder, and port 8787
    answers.
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
