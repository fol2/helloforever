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

### Check a transform over all the real data, not the newest part
- Cause: on 28 Nov 2026 `replay --pulls` (#362) was checked on the newest 40 of 136 records: every pull looked right. The simulator lane replayed all 136 and got 1,447 pulls; 117 of them, from three older records, were 65,536 s late, after their record had ended. The replay took the first frame's clock as at most 1 s behind the capture; in those records it was 2 s behind, and the rule picked the next cycle. The code assumed "the true time is never before the guess" without measuring a frame's age.
- Fix: #364 (the median of all frames' clocks; a test with a stale first frame, committed first)
- Done right: run a new transform over every real input there is, and check an invariant on each output (here: each pull inside its record's time span). A subset chosen for speed (`ls -t | head -40`) hides the old formats and the rare cases. Before relying on "X is never before Y", measure the gap on the data.
- Seen: 1× (2026-11-28)

### Never run a second reader while the live one runs
- Cause: on 28 Nov 2026 at about 05:07 a second `hellolink watch` ran for 150 s beside the live reader, to measure how soon a fresh reader gets object 10. Its capture stream broke the live reader's ("the capture stream does not answer (... application connection being interrupted)"): /state said `waiting` for about 3 minutes, a partner session ran `killall replayd` and nearly restarted the reader before a timed job, and the objects went stale.
- Fix: this entry (the measurement itself: object 10 came 8 s after the fresh reader's first frame, all 28 objects within 55 s, with no /reload)
- Done right: measure through the live reader (`:8787/state`, `/events`) or from a `--record` file, never with a second capture while one runs. If a test needs its own reader, ask the session that holds the reader, and stop the live one only with the owner's word.
- Seen: 1× (2026-11-28)

### Do not accept a limit that fails open on a privacy gate; match what a process cannot set itself
- Cause: #349 made the reader take no picture while the game is not running, by `pgrep -f` with the game's binary path (the pattern of the install checks). The PR wrote "a process whose command line holds the game's path ... makes the check say running" under ACCEPTED limits, as failing "towards the old behaviour". Within an hour of the install, on 24 Nov 2026 at 11:33, the reader took a capture with the game closed: some process's arguments held the path (the trigger is not known; a shell running `pgrep -f` with that pattern matches, shown by experiment). For a privacy gate the old behaviour is the failure.
- Fix: #351 (candidates by name, then the executable's path from `lsof`; `tests/game_check.rs`, `tests/game_executable.rs`)
- Done right: on a gate that exists to stop an action (privacy, money, deletion), a false "yes" is the defect, not an accepted limit. Match on what only the real thing has (the executable's path as the kernel knows it, a bundle id), never on text a process sets itself: its command line, or its name (the game's launcher shares the game's first 15 characters; review of #351). Before accepting a limit, ask which way it fails and whether that way is the one the gate exists to stop.
- Seen: 1× (2026-11-24)

### Merge only after reading the checks as all pass; re-run a cancelled check, never merge past it
- Cause: on 23 Nov 2026 the command that merged #334 printed the checks that were not "pass" and then ran `gh pr merge` whatever they were. One check showed "fail": its job, in the run started when the PR opened, had the conclusion "cancelled" (most likely cancelled by the runs the review comments started), and `gh pr checks` shows a cancelled job as "fail". The comment-started run had already passed the review gate (`REVIEW-ON-HEAD OK` for the head) before the merge at 16:46:49 UTC; the cancelled job, re-run after the merge, passed at 16:47:41 UTC.
- Fix: #334 (the job re-run after the merge: all pass), this entry
- Done right: merge only when every check's bucket is `pass`: `[ "$(gh pr checks <n> --json bucket -q 'length > 0 and all(.[]; .bucket == "pass")')" = true ] && gh pr merge ...`. A skipped check is not a pass. The one exception is a lead decision after round 2 (REVIEW.md, Rounds), which leaves `ai-sdlc/review-on-head` pending: then that check alone may be `pending` (`--json name,bucket`, `.bucket == "pass" or (.name == "ai-sdlc/review-on-head" and .bucket == "pending")`), and the PR body names the decision. `gh pr checks <n> && ...` is not enough: a cancelled job (bucket `cancel`) shows as "fail" but leaves the exit status 0 when the rest pass. Re-run a cancelled job (`gh run rerun <id> --failed`) and read the buckets again before the merge.
- Seen: 1× (2026-11-23)

### When a measured cause points at our own design, propose the fix; test the spec's stated reason
- Cause: on 23 Nov 2026 the stops with no new frame came as another app came in front of the game; a window over the row is the likely cause (the capture reads the display). The lead wrote "the stops are not format 3's: the row must be on the screen" and a side note advised the owner to move windows away. The fix was ours: capture the game's window. Spec 232 had ruled window capture out because "the owner plays full screen", but a full-screen game is a window too. The owner: "are we not agreed to get window not screen?", "think smartly next time".
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
- Again on 23 Nov 2026: the Rust test `a_capture_that_gives_no_frame` held 5.0 s, exactly its two waits' budget (the 3 s frame wait and `STOP_WAIT` 2 s before the kill), with nothing for the signal, the pipes and the reaping; on the loaded MacBook Pro it took 5.03 s and a CI run failed. The bound is now that budget and 1 s, from the constants, with the reason in the test.
- Done right: a check that compares two measures states its margin and the reason in the spec. After a change that moves memory or time, read the push's CI result before the review, not only the local run.
- Seen: 2× (2026-11-21, 2026-11-23)

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
- Again on 23 Nov 2026 (#332): a test ran `assist --history` with a missing file and waited for it to exit, with no limit. Under a mutation that dropped the flag, `assist` did not stop, and the test run hung until it was killed by hand. The test now kills the program after 10 s and fails.
- Done right: a wait on another process always has a limit and a fall-back. A cause goes into a document only after the smallest experiment that could contradict it has been run; until then the document says "not known" and lists what was seen.
- Seen: 2× (2026-11-13, 2026-11-23)

### Check an encoder against bytes written by hand, not against its own decoder
- Cause: the format-1 codec packed `session, seq, dwell` where the spec has `session, dwell, seq`. Every test packed and unpacked with the same code, so both sides were wrong the same way and 57 checks passed. The reviewer found it by reading the spec's table against the code.
- Fix: #34
- Done right: for each format, at least one frame whose bytes are written out by hand from the spec's table, and one committed vector (`tests/vectors/`) that a second implementation reads. A round trip proves only that the two halves agree with each other.
- Seen: 1× (2026-11-13)

### Probe a client capability in the game before building a feature on it
- Cause: 0.8.0 shipped a reload when AFK that calls `ReloadUI` from a timer. The harness mock allowed it; the client refuses a reload without a key press. The feature could never work and was removed one release later. A one-line probe in the game (`/hlink reloadtest`) settled it in a minute.
- Fix: #20 (0.8.1)
- Done right: when a feature stands on one client behaviour nobody has seen, ship the probe first (a slash command that tries it and reports), get the result, then build. "Fails safe" does not make an unproven feature worth a release.
- Seen: 1× (2026-11-12)
