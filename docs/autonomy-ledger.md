# Autonomy ledger

How far each task type runs without the owner. The orchestrator reads this before every step and stops at the level's limit. The weekly audit proposes movements from evidence; the owner may set any level at any time. See the AI-SDLC skill, `modules/autonomy.md`.

Levels: 0 Propose · 1 Draft (open the PR) · 2 Merge · 3 Release (deploy, verify, roll back) · 4 Initiate (start work from the north star or a monitor).

Enforcement status: `green since 2026-11-12, #11` (the AI-SDLC checks ran and gated that pull request and every one since). Levels 3 and 4 need green.

| Task type | Level | Clean streak | Last change | Evidence |
|---|---|---|---|---|
| docs | 4 | 0 | 2026-11-12 | owner setting |
| config | 4 | 0 | 2026-11-12 | owner setting |
| bug-fix | 4 | 0 | 2026-11-12 | owner setting |
| refactor | 4 | 0 | 2026-11-12 | owner setting |
| feature | 4 | 0 | 2026-11-12 | owner setting |
| schema-migration | 4 | 0 | 2026-11-12 | owner setting |
| infra-pipeline | 4 | 0 | 2026-11-12 | owner setting |
| dependency | 4 | 0 | 2026-11-12 | owner setting |
| release | 4 | 0 | 2026-11-12 | owner setting |
| payments-wiring | 4 | 0 | 2026-11-12 | owner setting |
| marketing-publish | 4 | 0 | 2026-11-12 | owner setting |
| skill-change | 4 | 0 | 2026-11-12 | owner setting |
| expenditure | 0 | n/a | fixed | the owner approves every spend |

## Owner settings

Entries the owner made by hand, newest first. The audit never undoes one.

- `2026-11-12`: all types except expenditure set to level 4. Why: "You can do whatever you want. You are code owner". Level 4 (start work with no owner message) is the owner's setting; the north star's priorities say what to start.
- `2026-11-12`: all types except expenditure set to level 2. Why: "don't ask me about merge. please apply ai-sdlc".

## Movement log

One line per movement, newest first, written by the weekly audit with its evidence.

- (none yet)
