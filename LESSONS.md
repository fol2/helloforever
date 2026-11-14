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

### See a new test fail on the code without the fix before trusting it
- Cause: twice a test was written for a review finding and passed on the code that had the fault. In #59 the test's client had already been dropped, so the close it checked did nothing. In #65 a secret value compared with nil raises nothing in Lua, so the check for an error could not fail. The reviewer found both; the suite was green both times.
- Fix: #59 (round 2), #65 (round 2)
- Done right: run each new test once against the source without the fix (restore the old file, or take the fix out) and read the failure. When a fault raises nothing, record the order of the calls and check that. A test that was never seen red proves nothing.
- Seen: 2× (2026-11-13, 2026-11-14)

### Put the merge command in its own call, after the checks are read as green
- Cause: #54 was merged five seconds before its two review checks went green. One shell call held the wait for the checks and, after a `;`, the merge; the wait ended with exit 1 and the merge ran anyway. The review was a true APPROVE of that head, so nothing wrong was merged, but the gate was not what stopped it.
- Fix: #54 (the merge), this entry
- Done right: wait for the checks in one call and read the result. Run `gh pr merge --match-head-commit` in the next call, or chain it with `&&` after a command whose exit code is the checks' result. A `;` between a gate and the thing it gates is no gate.
- Seen: 1× (2026-11-13)

### Measure a cause before writing it down; put a limit on every wait
- Cause: 40 minutes into the acceptance the capture service gave the strip reader no frame. The reader waited for one frame without a limit, for 4.5 minutes, and a fight was not recorded. The diagnosis ("killed capture processes leave streams open until the service is exhausted") went into the issue, the PR, `docs/STRIP.md` and this file before it was tested. Three small experiments then did not reproduce it: kills in a row left nothing behind. The real cause is not known.
- Fix: #38
- Done right: a wait on another process always has a limit and a fall-back. A cause goes into a document only after the smallest experiment that could contradict it has been run; until then the document says "not known" and lists what was seen.
- Seen: 1× (2026-11-13)

### Check an encoder against bytes written by hand, not against its own decoder
- Cause: the format-1 codec packed `session, seq, dwell` where the spec has `session, dwell, seq`. Every test packed and unpacked with the same code, so both sides were wrong the same way and 57 checks passed. The reviewer found it by reading the spec's table against the code.
- Fix: #34
- Done right: for each format, at least one frame whose bytes are written out by hand from the spec's table, and one committed vector (`tests/vectors/`) that a second implementation reads. A round trip proves only that the two halves agree with each other.
- Seen: 1× (2026-11-13)

### Give a test image what the real screen has around the thing
- Cause: the strip reader's width fit used every colour change on the line. The test images held the row and 40 pixels more, so the fit passed. On a screen the game's own pixels follow the row for two thousand pixels; with them the fit failed. A narrow-game test in the next pull request showed it, by accident.
- Fix: #35 (`tools/strip1.py`, `_fit`)
- Done right: a reader's test images carry noise before, after and under what is read, as wide as a display. When a reader passes only on tidy images, the test is the bug.
- Seen: 1× (2026-11-13)

### Probe a client capability in the game before building a feature on it
- Cause: 0.8.0 shipped a reload when AFK that calls `ReloadUI` from a timer. The harness mock allowed it; the client refuses a reload without a key press. The feature could never work and was removed one release later. A one-line probe in the game (`/hlink reloadtest`) settled it in a minute.
- Fix: #20 (0.8.1)
- Done right: when a feature stands on one client behaviour nobody has seen, ship the probe first (a slash command that tries it and reports), get the result, then build. "Fails safe" does not make an unproven feature worth a release.
- Seen: 1× (2026-11-12)

### Model a client event from what the client does, not from its name
- Cause: the mock client emptied its session list whenever it fired `DAMAGE_METER_RESET`. The real client fires it at login and keeps the list, so every login filed about 30 fights again, from 0.5.0 on. 230 green harness checks said nothing, because the mock agreed with the code.
- Fix: #14
- Done right: decode the real SavedVariables after the first run of a change and compare them with what the harness predicts. Write a mock from an observation; mark every assumed behaviour as unverified in `plan/01`.
- Seen: 1× (2026-11-12)

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

