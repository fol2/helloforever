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

## Where it stands (16 Nov 2026, from the repository)

| Part | State |
|---|---|
| HelloForever | 0.18.2. Lossless fight capture, the snapshot and timeline, the XP panel and fight window, the fight baseline; the assistant's bar and window with the `fight`, `target`, `gold`, `ammo` and `bags` cards, `/hello ask`, and the cards the companion sends; a settings window for every setting (`/hello settings`). Saved data writes no number where the client gave none (bags, XP, level, skills). |
| HelloLink | 0.5.0 in `main` (0.5.1 waits in #161). The live-state strip, format 1 with seventeen objects (the last four: gear, bag slots, bank, trainer), its own settings window (`/hlink settings`), and the 200 slots that carry text and the companion's cards into the game. |
| The reader | `tools/hellolink_strip.py` with its capture program and local API (`docs/STRIP.md`), installed outside any checkout (`tools/install_reader.py`). macOS only. |
| The assistant | Steps 1 to 3 of `docs/specs/115.md` are built: the bar, the window, the cards of the first part and of gold and supplies, and the companion (`tools/assistant.py`), which answers `session`. The `gear` card waits for its probe; `quests` is set aside (the owner, 16 Nov 2026: "please skip quest for now") and its design is still to be found (`docs/specs/115.md`, section 5); AI (step 4) is specified, not built. |
| HelloAim | A proposal, revision 4. No code. |
| Releases | Tags `v0.1.0` to `v0.5.0`. Nothing is tagged or published since. |
| The loop's checks | CI and the AI-SDLC checks run on every pull request. No branch protection (owner decision, 15 Nov 2026): the loop holds the merge gate. On 16 Nov 2026 GitHub blocked the AI-SDLC checks (`pull_request_target`) in a scheduled brownout until 18:00 UTC; GitHub blocks `pull_request_target` by default from 2 Dec 2026 (its changelog of 2 Nov 2026), after which they run only if the owner allows it in the repository's Actions settings (`plan/README.md`). The nightly audit, the evals and the weekly metrics are not set up. |

Which build the game has installed cannot be seen from the repository.

**Proved against the mock client only, not yet seen in the game:** the fight baseline
(`plan/05-assistant-link.md`, sections 6 to 8); most of `plan/01-in-game-verification.md`
(`/hello selftest` has never been recorded; the pull stats, the quest states, the fight
context, the pet); steps 1, 2 and 4 of `plan/04-matty-hunter-contract.md`. Seen in the game on
16 Nov 2026: the strip's objects 14 to 17, the gold, ammo and bags cards, both settings windows
(`plan/05`, sections 13 to 20, with the parts still open).

## Now

| # | Work | Serves | Waits for | Done when |
|---|---|---|---|---|
| 1 | The capture seen in the game: `/hello selftest` recorded, and each box of `plan/01-in-game-verification.md` ticked or noted | 1 | the game. The identity (`/hello debug`) can be done on the level 1 bank character; the selftest needs fights, loot and a quest handed in before it, so it and the fight keys, the quests and the pet are the owner's play | `plan/01`'s own "Done when" |
| 2 | The fight baseline seen in the game | 3 | the owner's fights (the agent does no combat) | the boxes of `plan/05`, sections 6, 7 and 8 are ticked with what was seen |
| 3 | The assistant, step 0: the probes (`docs/specs/115.md`, section 13) | 3 | the game: the bank character for most rows; the owner's play for the rows that need a fight or a hostile creature | each row of that section has a result in `plan/05`, but the two rows (the font, the window's widgets) that are line 4's game check |
| 4 | The assistant, step 1: the bar, its window with every setting, and the cards of the first part, fights, in English and Cantonese (HelloForever 0.12.0) | 3 | nothing to build the bar, the window and `fight`; `target` is built (0.14.0, #136); the game check waits for a close of the game (a new file) and, for the two cards, the owner's fights (line 2) | `docs/specs/115.md`, section 11, step 1 |

Line 1 is the oldest open work (11 Nov 2026) and serves priority 1. It comes before more of
priority 3 whenever the game is free for it.

## Next

| # | Work | Serves | Waits for | Done when |
|---|---|---|---|---|
| 6 | The cards of the other parts, in the owner's order: gear, gold, supplies, quests (`docs/specs/115.md`, section 5); then more languages, a table each | 3 | line 4; `gear` waits for its probe, `gold` and `quests` for their design | each part of `docs/specs/115.md`, section 5, has its cards in a release |
| 8 | The assistant, step 3: the companion and its first answer (`session`) | 3 | the game checks of the card's time on the bar, on the bank character and in play (in the owner's play the answer was written a second after the question and was on the bar when object 13 was read 33 s later, 15 Nov 2026, `plan/05`, section 12) | `docs/specs/115.md`, section 11, step 3 |
| 9 | A release others can install: tag and publish the version that line 1 verified (`plan/03-release.md`); the rollback rehearsed once (`docs/code-standards.md` says it never was) | 1, 2 | line 1 | `plan/03`'s own "Done when", and a note of the rehearsal |
| 10 | What Matty Hunter exposes, seen in the game (`plan/04-matty-hunter-contract.md`); the result of the trial of Matty Hunter alone written into `HelloAim/PLAN.md`; then its open decision 0 | 4 | the owner's play on the hunter | `plan/04`'s own "Done when", and decision 0 answered |
| 12 | The strip's four ongoing game checks (#60) | 3 | a play session that happens to show one | #60's boxes, each with a note |
| 13 | The other open boxes of `plan/05-assistant-link.md`: the guide's arrow and the route's legs, the target in combat and what a creature casts, a dungeon, indoors, flying and a cave, the reader's stream in play, and what is left of sections 1 and 3 | 3 | a play session that shows one; the probe lines in that file are the owner's to type | each box is ticked or has a note of what was seen |

## Later

| # | Work | Serves | Waits for |
|---|---|---|---|
| 15 | The assistant, step 4: AI (`docs/specs/115.md`, section 8) | 3 | an Expenditure decision by the owner. Step 3 runs in his play (15 Nov 2026), so the price of a question can now be measured on real briefs |
| 16 | History in the companion: a reader of the saved data file in this repository (the pipeline's is private) | 3, 2 | an intent of its own |
| 17 | A baseline for fights with several enemies (`docs/specs/93.md`, section 6) | 3 | a spec of its own |
| 18 | More on the strip: auras, cooldowns, action bars, the group (`docs/specs/29.md`, section 9). The gear, the bags, the bank and the trainer came when the local program asked (#138, #141) | 3 | a reader that asks for it |
| 19 | Sharing the assistant: a release with HelloLink and the slots' installer, a guide for a new player, a reader for Windows | the goal | the owner's word that it is good (`docs/north-star.md`: "如果佢真係好好"); the counts of `docs/specs/115.md`, section 9, as evidence |
| 20 | HelloAim code: only what the trial shows is missing | 4 | line 10 |
| 21 | The nightly lessons audit, the agent-setup evals, the weekly metrics | all | a self-hosted runner with the agent CLI and a token (`docs/code-standards.md`) |

## What waits for the owner

- Play: fights for lines 1 and 2; a hostile creature targeted and a changed piece of gear
  for line 3; the hunter with Matty Hunter for line 10; a play session
  with the bar for line 4.
- A decision: the expenditure for AI (line 15), and whether the assistant is good enough to
  share (line 19).

## Not on the roadmap

The non-goals of `docs/north-star.md`: automation of a key press or a cast, another
addon's code, a general chat bot in the game, an AI call without an approved expenditure.
