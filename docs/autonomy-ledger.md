# Autonomy ledger

How far each task type runs without the owner. The orchestrator reads this before every step and stops at the level's limit. The weekly audit proposes movements from evidence; the owner may set any level at any time. See the AI-SDLC skill, `modules/autonomy.md`.

Levels: 0 Propose · 1 Draft (open the PR) · 2 Merge · 3 Release (deploy, verify, roll back) · 4 Initiate (start work from the north star or a monitor).

Enforcement status: `not yet green` (the checks first run on the pull request after the adoption PR). Levels 3 and 4 need green.

| Task type | Level | Clean streak | Last change | Evidence |
|---|---|---|---|---|
| docs | 2 | 0 | 2026-11-12 | owner setting |
| config | 2 | 0 | 2026-11-12 | owner setting |
| bug-fix | 2 | 0 | 2026-11-12 | owner setting |
| refactor | 2 | 0 | 2026-11-12 | owner setting |
| feature | 2 | 0 | 2026-11-12 | owner setting |
| schema-migration | 2 | 0 | 2026-11-12 | owner setting |
| infra-pipeline | 2 | 0 | 2026-11-12 | owner setting |
| dependency | 2 | 0 | 2026-11-12 | owner setting |
| release | 2 | 0 | 2026-11-12 | owner setting |
| payments-wiring | 2 | 0 | 2026-11-12 | owner setting |
| marketing-publish | 2 | 0 | 2026-11-12 | owner setting |
| skill-change | 2 | 0 | 2026-11-12 | owner setting |
| expenditure | 0 | n/a | fixed | the owner approves every spend |

## Owner settings

Entries the owner made by hand, newest first. The audit never undoes one.

- `2026-11-12`: all types except expenditure set to level 2. Why: "don't ask me about merge. please apply ai-sdlc".

## Movement log

One line per movement, newest first, written by the weekly audit with its evidence.

- (none yet)
