# Claim a GitHub action as done only after its command returned

Moved from `LESSONS.md` on 2026-11-22, when the live log passed fifteen entries (#232).

- Cause: a PR body and `plan/README.md` said merged branches were deleted, but the delete command had been refused by the session's permission check. A follow-up commit had to restore the task.
- Fix: #6 (second commit), #7
- Done right: write "done" into a doc or a PR body after the command's exit code is seen, never in the same batch that runs it.
- Seen: 1× (2026-11-11)
