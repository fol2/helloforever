# North star

Why this repo exists. Drafted by the orchestrator from what is on record; the owner edits at will. See the AI-SDLC skill, `modules/north-star.md`.

## Goal

"Open-source **WoW Forever** addons by James To." (`README.md`)

Direction, owner, 12 Nov 2026: a personal assistant for his own play first ("一開始梗係幫到自己先"),
shared with others if it proves good ("如果佢真係好好、我自己都覺得好好用嘅，咁我唔介意分開畀人"). Not only
playing better: "全方位嘅私人助理". It may connect to AI ("我亦都唔介意佢可以 connect 到 AI 喺個 game
入邊"), as an assistant with its own UI, not a chat bot ("我唔係諗住喺入面開個 chat bot").

## Who pays, for what

Nobody. The addons are free and MIT-licensed, and the owner has stated no revenue for this repo. Intents carry "Revenue impact: none" until he says otherwise.

## Priorities, in order

1. HelloForever captures every fight without loss and without hurting play.
2. What it saves stays readable by the offline pipeline (`docs/SCHEMA.md`).
3. The assistant: what the game saved comes back to the player as advice, in the game.
   First the two channels (`plan/05-assistant-link.md`), then a baseline for a fight, then
   the assistant bar, then AI. The lead's order, 12 Nov 2026; the owner said "你係 project
   lead，你可以決定".
4. HelloAim: only what the trial of Matty7500Hunter alone shows is missing (`HelloAim/PLAN.md`).

Paraphrased from `README.md` and `HelloAim/PLAN.md`; not the owner's own words.

## Non-goals

- Automation: every cast is a player key press. Kept by the owner on 12 Nov 2026 when the shared live-state strip was agreed (`docs/owner-decisions.md`).
- Copying another addon's code.
- A general chat bot in the game. Others have built that; the assistant's value is that it
  knows this character's history.
- AI calls without an approved expenditure (`docs/owner-decisions.md`).

## History

- `2026-11-12`: both channels work in the game without a reload (`plan/05`). The live-state strip gets a public format that other projects may read; this repo stays an adviser.
- `2026-11-12`: the owner's direction for an assistant added, quoted; priority 3 is new.
- `2026-11-12`: first draft at AI-SDLC adoption. Only the Goal line is quoted.
