# LESSONS.md

Short live log of repeatable mistakes. Read it before every task. At most fifteen entries; older ones live in `docs/solutions/`, searched when a task touches their area.

- Add an entry as soon as a review finding, revert, follow-up fix, failed CI run, rework or incident shows a repeatable mistake. Add one at once when an agent makes the same mistake twice.
- The nightly audit bumps `Seen` (one count per day), merges duplicates, deletes obsolete entries and moves overflow to `docs/solutions/`.
- A lesson seen on three different days moves by PR into `docs/code-standards.md` as a hard rule and leaves this file.

Entry format (newest first):

```markdown
### <one-line rule, imperative>
- Cause: <what went wrong and why>
- Fix: <commit sha or PR #>
- Done right: <what the correct approach looks like>
- Seen: 1× (YYYY-MM-DD)
```

## Entries

### A gate that reads a config file validates the whole file once, strictly
- Cause: the adoption test first searched `.claude/settings.json` for hook file names. Then it piped `jq` into `head`, which hid a parse failure and cut a multi-line command. Then it accepted a file with two top-level JSON values. The reviewer found a new hole on three rounds.
- Fix: #9 (`.github/ai_sdlc_adoption.sh`)
- Done right: slurp the file and require exactly one object. Read every value from that validated object. Let the parser's own exit status decide. Give the validator its own refusal cases. After the second hole of one kind, ship the strict version, not another patch.
- Seen: 1× (2026-11-12)

### Claim a GitHub action as done only after its command returned
- Cause: a PR body and `plan/README.md` said merged branches were deleted, but the delete command had been refused by the session's permission check. A follow-up commit had to restore the task.
- Fix: #6 (second commit), #7
- Done right: write "done" into a doc or a PR body after the command's exit code is seen, never in the same batch that runs it.
- Seen: 1× (2026-11-11)

### Check which version the game loads before planning in-game work
- Cause: the plan assumed 0.6.0 could be verified in the client, but the game loads the addon through a symbolic link to an older copy (0.5.0), and the game was running.
- Fix: #6 (`plan/01-in-game-verification.md`)
- Done right: read the installed TOC version first; never change the installed addon while the game runs.
- Seen: 1× (2026-11-11)

