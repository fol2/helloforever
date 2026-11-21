# Check which version the game loads before planning in-game work

Moved from `LESSONS.md` on 2026-11-21, when the live log passed fifteen entries (#232).

- Cause: the plan assumed 0.6.0 could be verified in the client, but the game loads the addon through a symbolic link to an older copy (0.5.0), and the game was running.
- Fix: #6 (`plan/01-in-game-verification.md`)
- Done right: read the installed TOC version first; never change the installed addon while the game runs.
- Seen: 1× (2026-11-11)
