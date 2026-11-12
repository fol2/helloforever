# plan/ — work for someone with the game client or more GitHub access

Tasks the cloud session that reviewed 0.6.0 (11 Nov 2026) could not do itself: they need
the WoW Forever client, or GitHub permissions it did not have. Each file says what to do,
why, and how to tell it is done. Delete a file (and its line here) when its task is
finished.

| File | Task | Needs |
|------|------|-------|
| [01-in-game-verification.md](01-in-game-verification.md) | Verify 0.6.0 in the client, starting with `/hello selftest` | the game |
| [03-release.md](03-release.md) | Publish the verified 0.6.x release (`v0.5.0` is tagged) | task 01 finished |
| [04-matty-hunter-contract.md](04-matty-hunter-contract.md) | Matty Hunter is recorded (`status = ok`); still to check: the two commands, the key against the hint on screen, and that MH is never written to | the game, with MH |
| [05-assistant-link.md](05-assistant-link.md) | Find out whether text from a program reaches the running game without `/reload`, and whether `ReloadUI` works without a key press | the game |

Done on 11 Nov 2026: the CI workflow (now `.github/workflows/ci.yml`), the `v0.5.0` tag,
and the GitHub housekeeping (merged branches deleted, head branches deleted on merge).

The companion list for the offline pipeline is `plan/` in its own (private) repository.
