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

### When a measured cause points at our own design, propose the fix; test the spec's stated reason
- Cause: on 23 Nov 2026 the stops with no new frame were traced to another window over the game (the capture reads the display). The lead wrote "the stops are not format 3's: the row must be on the screen" and a side note advised the owner to move windows away. The fix was ours: capture the game's window. Spec 232 had ruled window capture out because "the owner plays full screen", but a full-screen game is a window too. The owner: "are we not agreed to get window not screen?", "think smartly next time".
- Fix: the owner decision of 2026-11-23 ("The reader captures the game's window, not the display"); the window-capture PR
- Done right: when a cause is found, ask what in our own design lets it happen and propose that change before advice to the owner. When a spec rules an option out, check its reason against the facts (here: what a window is) before relying on it.
- Seen: 1× (2026-11-23)

### Track the build that follows a probe, not only the probe
- Cause: format 3's parts C and D put each feature behind a probe (rule 1). `plan/05` got a box for each probe, but the build after it was written nowhere but the spec's prose. On 22 Nov 2026 a summary read only the boxes and said format 3's code was done; lanes in the frame, 9 bits, the fall-back by bits and four records of part D were not built. The owner asked why 9 bits was dropped.
- Fix: #284 (`docs/specs/232.md`, section 11: each unbuilt item, what it waits for, what to build)
- Done right: when a feature waits for a probe, track two items: the probe's game check and the build that follows it, with what it waits for. Before saying a spec is done, read its parts and its plan, not only the open boxes.
- Seen: 1× (2026-11-22)

### Give a check that compares two measures a stated margin; CI's own build is the judge
- Cause: in #266 every step passed on the MacBook Pro (Lua 5.1: format 1 11.9 KB a second, format 2 11.3), but CI's Lua 5.1 on Ubuntu gave 15.1 and 15.2, and "format 2 asks for no more memory than format 1" failed. The check had no margin, and a change that made format 1 cheaper broke it. `run_all.sh` prints a step's numbers only when it fails, so the local run hid how close they were.
- Fix: #266 (a 2 % margin, written in spec 213; a format switch rebuilds binary objects only across format 3)
- Done right: a check that compares two measures states its margin and the reason in the spec. After a change that moves memory or time, read the push's CI result before the review, not only the local run.
- Seen: 1× (2026-11-21)

### Never run Python, not even a version check
- Cause: the owner, 20 Nov 2026: "remember we wont go back to python. we are in fully rust". On 20 Nov an agent ran `python3 --version` and made an empty `.py` file; on 21 Nov, in the HelloLink 1.0.0 work, a shell call held `python3 --version >/dev/null` again, a line copied out of habit. Nothing read its output, but the rule is that nothing runs Python.
- Fix: #233 (this entry)
- Done right: before a shell call, read it for `python`, `python3`, `pip` and `.py`. A check uses `jq`, `luajit`, `perl`, `sed` or a Rust tool. Never test for Python's presence either. The rule holds for the reviewer too: in #262 codex ran Python in its own sandbox, so every review prompt says "Never run Python".)
- Seen: 2× (2026-11-20, 2026-11-21)

### Read the staged list before a commit that changes an ignore file
- Cause: in #210 a change removed two lines of `reader/.gitignore`. Those lines ignored rust-anything's recorded cases (11 MB). The next `git add -A` staged 1,853 files, 1,813 of them generated cases. The commit was seen and undone before the push.
- Fix: #210 (the generated folder deleted, the commit made again)
- Done right: when a change removes an ignore line, delete only what is confirmed disposable output, or stage the intended paths by name. Read `git diff --cached --stat` before the commit. Stop when the count does not fit the change.
- Seen: 1× (2026-11-20)

### Stop at two review rounds; then judge what is left yourself
- Cause: #206 had two full rounds and seven check reviews, each REQUEST CHANGES, while REVIEW.md allows two. Every finding was fixed as asked. The later ones were races that need two installs and a reader in the same few milliseconds (a link to the program, a folder named like a kept install, another case of that name), and each fix gave the reviewer a new corner. The owner, 20 Nov 2026: "do not overgate ... please do not blindless accept their review result ... the fix itself is not needed".
- Fix: #206 (lead decision in the PR body), #207 (the accepted races, as notes)
- Done right: after round two, read each finding against a real path on this machine. Fix a P0, or a P1 that can happen in use. For a rare race, make it visible (a warning, an error, no silent drop), write it under "ACCEPTED limits" with a note issue, and merge. Code that only answers a reviewer's corner makes the app heavier.
- Seen: 1× (2026-11-20)

### Count a mutation as red only when its test fails at the check it aims at
- Cause: in #206 the install tests installed from this repository's commit. Any mutation of `src/` changed the program's build digest, so the first install was refused and the test failed at its first line, whatever the mutation was. Several red runs of rounds 0 to 4 were that refusal, not the check they named; two "red" mutations did not even build. The review found the same blindness from the other side: a shell's `; :` made a test's exit-code check always pass.
- Fix: #206 (the tests install from a copy of the working tree; `mut3b-final` in the PR)
- Again on 20 Nov 2026 (#206): a mutation that panicked mid-test left its `sleep 60` runner in the test's folder, and the next eleven mutations went red at their first install ("runs from"), not at their own checks. Each runner is now a guard that stops its process group on drop, a panic included.
- Done right: read where each red run failed: the line must be the assertion the mutation targets, and the run must have built. A mutation script reports "did not build" and "timed out" apart from "red", and prints the failing file:line. A test whose first step depends on the code being unchanged (a digest, a commit, a cache) cannot judge a mutation. A test that starts processes stops them on drop, so a red run leaves nothing for the next one.
- Seen: 2× (2026-11-19, 2026-11-20)

### Tick a game-check box only when all of it was seen
- Cause: in #156 three boxes of `plan/` were ticked when only half of each was seen (`/hello debug`'s values read from the saved data, not from its output; the budget of a character with no fights; the free bag slots without a quiver). In #159 a count was given from the first event, not the first snapshot. The reviewer found all four.
- Fix: #156 (round 2), #159 (round 2)
- Done right: read the box word by word against what was seen. Tick it only when every part was seen; otherwise leave it open and write what was seen and what is still to see. Give a range as the smallest and largest values over all the evidence, the first snapshot included.
- Seen: 1× (2026-11-16)

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

