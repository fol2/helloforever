# plan/ — work for someone with the game client or more GitHub access

Tasks the cloud session that reviewed 0.6.0 (11 Nov 2026) could not do itself: they need
the WoW Forever client, or GitHub permissions it did not have. Each file says what to do,
why, and how to tell it is done. Delete a file (and its line here) when its task is
finished.

| File | Task | Needs |
|------|------|-------|
| [01-in-game-verification.md](01-in-game-verification.md) | Verify 0.6.0 in the client, starting with `/hello selftest` | the game |
| [02-ci-workflow.md](02-ci-workflow.md) | Add the CI workflow (`plan/ci.yml`) | permission to push workflow files |
| [03-release.md](03-release.md) | Tag and publish releases (tags stop at v0.4.0) | push access for tags |
| [04-matty-hunter-contract.md](04-matty-hunter-contract.md) | Confirm what Matty Hunter exposes before building HelloAim on it | the game, with MH installed |
| [05-housekeeping.md](05-housekeeping.md) | Delete merged branches; enable auto-delete | GitHub web or `gh` |

The companion list for the offline pipeline is `plan/` in its own (private) repository.
