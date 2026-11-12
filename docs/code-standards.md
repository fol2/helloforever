# Code standards

Commands, repo-specific hard rules and repo-specific acceptance criteria. Changed by PR. The shared rules and acceptance criteria live in the AI-SDLC skill (`SKILL.md` §4 and §5) and are not copied here. A rule that must always hold names the hook or check that enforces it.

## Commands

Each check is one command that exits non-zero on failure. All five run in CI (`.github/workflows/ci.yml`) on Lua 5.1.

- Unit tests: `lua5.1 tests/id_freshness.lua`. Healthy: `== 30 checks, 0 failed`, exit 0.
- Mock-client harness: `lua5.1 tests/fights_harness_v4.lua ./HelloForever <out_SV.lua> <out_truth.json>`. Healthy: exit 0. Needs Lua 5.1 exactly.
- Adoption test: `sh .github/ai_sdlc_adoption.sh`. Healthy: `AI-SDLC ADOPTION OK`, exit 0. Each failure names the missing control. Needs `jq`.
- Lint: `luacheck HelloForever tests`. Healthy: `0 warnings / 0 errors`.
- Release checks: `python3 tools/package.py --check --no-tests`. Healthy: `TOC, VERSION_FALLBACK, SOURCE_REVISION and CHANGELOG agree`.
- Build: `python3 tools/package.py`. Healthy: `dist/HelloForever-<version>.zip` and SHA-256 sums.
- Deploy: none from a PR. A release is a tag and a GitHub release (`plan/03-release.md`); the owner installs the zip into the game.
- Rollback: install the previous release's zip. Never rehearsed.
- Health check: `/hello selftest` in the game (`plan/01-in-game-verification.md`). Only a person with the client can run it.

## Enforcement in this repo

- AI-SDLC checks: `.github/workflows/ai-sdlc-checks.yml`, on GitHub-hosted runners. Not yet required by branch protection (to do after the first green run). Until then the loop holds the merge gate itself: `sh .ai-sdlc/review_on_head.sh <PR> <sha>` must exit 0, then `gh pr merge --match-head-commit <sha>`.
- The checks implementation is a copy (`.github/workflows/ai-sdlc-checks-impl.yml`), because the skill's reusable workflow cannot be called from this account. Refresh `.ai-sdlc/` with the skill's `scripts/adopt.sh` and the copy by hand when the skill changes.
- Tests, lint and release checks: `.github/workflows/ci.yml`, on every pull request.
- Hooks: `.claude/hooks/guard-edits.sh`, `.claude/hooks/spend-gate.sh`. No spend patterns: nothing in this repo spends money.
- Secret scan beyond the sample patterns: GitGuardian (the account's GitHub app).
- Not set up: the nightly lessons audit (it needs a self-hosted runner with the agent CLI and a token), agent-setup evals, weekly metrics, CODEOWNERS.

## Repo-specific hard rules

1. No code, rule table or spell table from Matty7500Hunter enters this repository; its licence is All Rights Reserved. Read its live global at runtime only (`HelloAim/PLAN.md`). Enforced by: review only.
2. HelloForever never writes to another addon: `rawget` only, no method calls, no callbacks (`docs/SCHEMA.md`). Enforced by: review only.
3. No addon automates a key press or a cast (`HelloAim/PLAN.md`, Terms of Use). Enforced by: review only.
4. No SavedVariables dump or real fight data is committed. Enforced by: `.gitignore`; review.
5. The TOC version, `VERSION_FALLBACK`, `SOURCE_REVISION` and the changelog change together. Enforced by: `tools/package.py --check` in CI.
6. A change to the saved-data format updates `docs/SCHEMA.md` in the same PR; the offline pipeline (`fol2/wow-data`) reads it. Enforced by: review only.

## Repo-specific acceptance criteria

1. A PR that changes addon behaviour says what was checked in the mock client and what still needs the game, and adds the in-game check to `plan/`.

## This machine

- The development Mac has Lua 5.5, not 5.1: `tests/id_freshness.lua` runs, the harness does not. CI is the harness run.
- The game loads `Interface/AddOns/HelloForever` through a symbolic link to an older working copy outside this repository (0.5.0 on 2026-11-12). Editing this repository does not change what the game loads.
- Do not change the installed addon while the game is running.
