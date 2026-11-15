# Roadmap

The work of this repository in order. It follows the priorities of `docs/north-star.md` and
changes none of them; when the two disagree, the north star is right. The lead keeps it;
the owner changes it at will. No dates: the order is what counts.

- A line is added when its intent (issue) is opened, and deleted by the pull request that
  finishes it. `CHANGELOG.md` and `plan/` keep the record of what was done.
- Inside a section the lines are in the order of work. A line that waits does not hold
  back the lines after it.
- "Serves" is the priority in `docs/north-star.md`: 1 capture without loss, 2 saved data
  the pipeline can read, 3 the assistant, 4 HelloAim.

## Where it stands (15 Nov 2026, from the repository)

| Part | State |
|---|---|
| HelloForever | 0.11.0. Lossless fight capture, the snapshot and timeline, the XP panel and fight window, the fight baseline (kept, shown as a chat line, handed to the strip). |
| HelloLink | 0.1.0. The live-state strip, format 1 with twelve objects, and the 200 slots that carry text into the game. |
| The reader | `tools/hellolink_strip.py` with its capture program and local API (`docs/STRIP.md`). macOS only. |
| The assistant | The two channels work in the game; the baseline is built. The bar, the companion and AI are specified (`docs/specs/115.md`), not built. |
| HelloAim | A proposal, revision 4. No code. |
| Releases | Tags `v0.1.0` to `v0.5.0`. Nothing is tagged or published since. |
| The loop's checks | CI and the AI-SDLC checks run on every pull request. Branch protection does not require them. The nightly audit, the evals and the weekly metrics are not set up. |

Which build the game has installed cannot be seen from the repository.

**Proved against the mock client only, not yet seen in the game:** the fight baseline
(`plan/05-assistant-link.md`, sections 6 to 8); most of `plan/01-in-game-verification.md`
(`/hello selftest` has never been recorded; the pull stats, the quest states, the fight
context, the pet); steps 1, 2 and 4 of `plan/04-matty-hunter-contract.md`.

## Now

| # | Work | Serves | Waits for | Done when |
|---|---|---|---|---|
| 1 | The capture seen in the game: `/hello selftest` recorded, and each box of `plan/01-in-game-verification.md` ticked or noted | 1 | the game. The selftest, the identity and the fight keys can be done on the level 1 bank character; fights, quests and the pet need the owner's play | `plan/01`'s own "Done when" |
| 2 | The fight baseline seen in the game | 3 | the owner's fights (the agent does no combat) | the boxes of `plan/05`, sections 6, 7 and 8 are ticked with what was seen |
| 3 | The assistant, step 0: the probes (`docs/specs/115.md`, section 13) | 3 | the game, on the bank character | each row of that section has a result in `plan/05` |
| 4 | The assistant, step 1: the bar and the addon's cards (HelloForever 0.12.0) | 3 | nothing; its game check waits for a close of the game (a new file) and, for three cards, the owner's play | `docs/specs/115.md`, section 11, step 1 |
| 5 | `README.md` says what 0.11.0 does (its status and headings say 0.8.1); `plan/README.md` names the tasks as they are now | all | nothing | the README's version lines equal the TOC's |

Line 1 is the oldest open work (11 Nov 2026) and serves priority 1. It comes before more of
priority 3 whenever the game is free for it.

## Next

| # | Work | Serves | Waits for | Done when |
|---|---|---|---|---|
| 6 | The assistant, step 2: the way in (the `assist` part of a slot, the looks, strip object 13) | 3 | line 3 (what a look costs, the doorbell); the local program's word on object 13 | `docs/specs/115.md`, section 11, step 2 |
| 7 | The assistant, step 3: the companion and its first answer (`session`) | 3 | line 6 | `docs/specs/115.md`, section 11, step 3 |
| 8 | A release others can install: tag and publish the version that line 1 verified (`plan/03-release.md`); the rollback rehearsed once (`docs/code-standards.md` says it never was) | 1, 2 | line 1 | `plan/03`'s own "Done when", and a note of the rehearsal |
| 9 | What Matty Hunter exposes, seen in the game (`plan/04-matty-hunter-contract.md`); the result of the trial of Matty Hunter alone written into `HelloAim/PLAN.md`; then its open decision 0 | 4 | the owner's play on the hunter | `plan/04`'s own "Done when", and decision 0 answered |
| 10 | Branch protection requires CI and the AI-SDLC checks (`docs/code-standards.md`, "Enforcement in this repo") | all | the rights to change the repository's settings | a pull request with a failing check cannot be merged |
| 11 | The strip's four ongoing game checks (#60) | 3 | a play session that happens to show one | #60's boxes, each with a note |

## Later

| # | Work | Serves | Waits for |
|---|---|---|---|
| 12 | The assistant, step 4: AI (`docs/specs/115.md`, section 8) | 3 | an Expenditure decision by the owner; line 7 run in his play, so that a question's price is measured |
| 13 | More cards: `talent`, `sell`, `repair`, `enchant`, `quests`, `pace` (`docs/specs/115.md`, section 5) | 3 | a probe each; the owner's word on which parts of play come first |
| 14 | History in the companion: a reader of the saved data file in this repository (the pipeline's is private) | 3, 2 | an intent of its own |
| 15 | A baseline for fights with several enemies (`docs/specs/93.md`, section 6) | 3 | a spec of its own |
| 16 | More on the strip: auras, cooldowns, action bars, the group, the rest of the gear (`docs/specs/29.md`, section 9) | 3 | a reader that asks for it |
| 17 | Sharing the assistant: a release with HelloLink and the slots' installer, a guide for a new player, a reader for Windows | the goal | the owner's word that it is good (`docs/north-star.md`: "如果佢真係好好"); the counts of `docs/specs/115.md`, section 9, as evidence |
| 18 | HelloAim code: only what the trial shows is missing | 4 | line 9 |
| 19 | The nightly lessons audit, the agent-setup evals, the weekly metrics | all | a self-hosted runner with the agent CLI and a token (`docs/code-standards.md`) |

## What waits for the owner

- Play: fights for lines 1 and 2; the hunter with Matty Hunter for line 9; a play session
  with the bar for line 4.
- Answers: the three questions of `docs/specs/115.md`, section 12. The build follows the
  defaults there until he answers.
- A decision: the expenditure for AI (line 12), and whether the assistant is good enough to
  share (line 17).

## Not on the roadmap

The non-goals of `docs/north-star.md`: automation of a key press or a cast, another
addon's code, a general chat bot in the game, an AI call without an approved expenditure.
