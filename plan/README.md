# plan/ — work for someone with the game client or more GitHub access

Tasks the cloud session that reviewed 0.6.0 (11 Nov 2026) could not do itself: they need
the WoW Forever client, or GitHub permissions it did not have. Each file says what to do,
why, and how to tell it is done. Delete a file (and its line here) when its task is
finished.

| File | Task | Needs |
|------|------|-------|
| [01-in-game-verification.md](01-in-game-verification.md) | Verify the fight capture in the client (written for 0.6.0; 0.18.2 is installed), starting with `/hello selftest` | the game, with fights |
| [03-release.md](03-release.md) | Publish the release that task 01 verified (`v0.5.0` is the last tag) | task 01 finished |
| [04-matty-hunter-contract.md](04-matty-hunter-contract.md) | Matty Hunter is recorded (`status = ok`); still to check: the two commands, the key against the hint on screen, and that MH is never written to | the game, with MH |
| [05-assistant-link.md](05-assistant-link.md) | The record of what the game showed for the assistant's two channels (the slots, the live-state strip), the fight baseline and the probes of `docs/specs/115.md`; the open boxes are what is still to see | the game; the owner's play for fights |

Done on 11 Nov 2026: the CI workflow (now `.github/workflows/ci.yml`), the `v0.5.0` tag,
and the GitHub housekeeping (merged branches deleted, head branches deleted on merge).

The order of the work is in [`docs/roadmap.md`](../docs/roadmap.md).

## Open at the end of the session of 16 Nov 2026

- **#161 (HelloLink 0.5.1, object 17's step).** Reviewed and approved on head `376ffea`; not merged:
  GitHub's `pull_request_target` brownout stopped the AI-SDLC checks from starting (until 18:00
  UTC, 16 Nov 2026). If it is still open: close and reopen it to run the checks again, read them
  green, run `.ai-sdlc/review_on_head.sh 161 376ffeac58be76759b4797dd6e928519e0fa6a94`, merge with
  `--match-head-commit`. Then install HelloLink (only `Strip.lua` and the TOC's version line change,
  so it may be hot-loaded), and tell the local program that `step` is `null` past the list.
- **The owner's decision.** The brownout comes before a new GitHub default: the AI-SDLC checks
  run only if the owner allows `pull_request_target` in the repository's Actions event policy
  (https://gh.io/securely-using-pull_request_target). The workflow reads the PR as data and never
  runs its code. If the owner does not allow it, the checks need another design.
- **Installed now:** HelloForever 0.18.2, HelloLink 0.5.0, the reader of `main` (17 objects).
  Saved-data backups before each install: `dist/sv-backup-before-<version>/` (two accounts).
- **Game checks still open:** `plan/05-assistant-link.md`, sections 12 to 20 (an enchanted or
  suffixed item, a class trainer, a trainer filter turned off, the cards' texts, a quiver or
  reagent bag with free slots, the AddOns options pages, the other settings controls), and most
  of `plan/01`. On the hunter's gear none had an enchant or a suffix: the owner to confirm.
- **Driving the game.** Game checks drive the client in the background only (no full-screen
  control; the owner works meanwhile): the owner presses Play in Battle.net (in the background it
  could not be clicked while the window sat as a Stage Manager thumbnail); Enter World, clicks,
  keys and chat lines (`Return`, the typed line, a look at the edit box, `Return`) go to the game's
  window in the background; long results are read from the SavedVariables after `/reload`.
- **Next by the roadmap:** the `quests` card waits for the owner's design; the `gear` card for a
  probe in fights; line 1 (`/hello selftest`) for fights.

The companion list for the offline pipeline is `plan/` in its own (private) repository.
