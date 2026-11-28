# Give a test image what the real screen has around the thing

Moved from `LESSONS.md` on 2026-11-28, when the live log passed fifteen entries.

- Cause: the strip reader's width fit used every colour change on the line. The test images held the row and 40 pixels more, so the fit passed. On a screen the game's own pixels follow the row for two thousand pixels; with them the fit failed. A narrow-game test in the next pull request showed it, by accident.
- Fix: #35 (`tools/strip1.py`, `_fit`)
- Done right: a reader's test images carry noise before, after and under what is read, as wide as a display. When a reader passes only on tidy images, the test is the bug.
- Seen: 1× (2026-11-13)
