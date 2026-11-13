# Code standards

Commands, repo-specific hard rules and repo-specific acceptance criteria. Changed by PR. The shared rules and acceptance criteria live in the AI-SDLC skill (`SKILL.md` §4 and §5) and are not copied here. A rule that must always hold names the hook or check that enforces it.

## Commands

Each check is one command that exits non-zero on failure. All five run in CI (`.github/workflows/ci.yml`) on Lua 5.1.

- Unit tests: `lua5.1 tests/id_freshness.lua`. Healthy: `== 30 checks, 0 failed`, exit 0.
- Mock-client harness: `lua5.1 tests/fights_harness_v4.lua ./HelloForever <out_SV.lua> <out_truth.json>`. Healthy: exit 0. Needs Lua 5.1 exactly.
- The same with the extra reset sections: `lua5.1 tests/fights_harness_more.lua ./HelloForever <out_SV.lua> <out_truth.json>`. Healthy: exit 0.
- Adoption test: `sh .github/ai_sdlc_adoption.sh`. Healthy: `AI-SDLC ADOPTION OK`, exit 0. Each failure names the missing control. Needs `jq`.
- HelloLink spike: `python3 tools/hellolink.py install <dir> --slots 3 && lua5.1 tests/hellolink_test.lua <dir>` (`<dir>` is a new, empty folder). Healthy: `== 8 checks, 0 failed`, exit 0.
- HelloLink strip: `lua5.1 tests/hellolink_strip_test.lua <dir>` (`<dir>` is an existing scratch folder). Healthy: `== 27 checks, 0 failed`, exit 0.
- HelloLink strip reader, bad images: `python3 tests/hellolink_strip_test.py`. Healthy: `== 29 checks, 0 failed`, exit 0.
- Live-state strip, format 1: `python3 tests/strip1_test.py`. Healthy: `== 83 checks, 0 failed`, exit 0.
- Lint: `luacheck HelloForever HelloLink tests`. Healthy: `0 warnings / 0 errors`.
- Release checks: `python3 tools/package.py --check --no-tests`. Healthy: `TOC, VERSION_FALLBACK, SOURCE_REVISION and CHANGELOG agree`.
- Build: `python3 tools/package.py`. Healthy: `dist/HelloForever-<version>.zip` and SHA-256 sums.
- Deploy: run the tests first (`tools/package.py` runs them with `lua5.1`, which this Mac does not have: use the two `luajit` commands under "This machine", or rely on CI for a merged commit), then `python3 tools/package.py --no-tests`, then replace `Interface/AddOns/HelloForever` with the unzipped build. Done this way four times on 2026-11-12 (0.6.0, 0.7.0 twice, 0.7.1). Replacing the folder is only for when the game is closed: check with `pgrep -f 'World of Warcraft.app/Contents/MacOS/World of Warcraft'` and wait if it runs (owner decision, 2026-11-12). Copy `SavedVariables/HelloForever.lua` to `dist/sv-backup-before-<version>/` first. Healthy: the installed files' SHA-256 equal the build's. A public release is a tag and a GitHub release (`plan/03-release.md`).
- Rollback: build the previous version (`git checkout <tag or sha>`, `python3 tools/package.py --no-tests`) and install it the same way; restore the SavedVariables backup if the format changed. **Never rehearsed.**
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

- The development Mac's `lua` is 5.5, not 5.1: it runs `tests/id_freshness.lua` but not the harness. Use `luajit` for the harness (below).
- The game loads `Interface/AddOns/HelloForever` from a real folder, unzipped from `tools/package.py` (0.6.0 on 2026-11-12). Editing this repository does not change what the game loads: build the zip and replace the folder.
- `luajit` and `luacheck` are installed (Homebrew). The tests here: `luajit tests/id_freshness.lua` and `luajit tests/fights_harness_more.lua ./HelloForever <out_SV.lua> <out_truth.json>` (the harness with the extra sections).
- Two ways to install, by what the release changes (owner decisions, 2026-11-12):
  - Only the content of `.lua` files that are already installed: copy each file over its installed copy (write a temporary file beside it, then rename), also while the game runs. Then the owner types `/reload`. Used for HelloLink on 2026-11-12.
  - Anything else (a changed `.toc`, a new or removed file, a new addon): wait until the game is closed, then replace the folder as under Deploy. A HelloForever release changes the `.toc` version. When that version line is its only change outside the `.lua` files that are already installed (no file added, removed or renamed, no change to the files the `.toc` lists or their order): copy its changed `.lua` files as above at once, all of them before the `/reload`, and replace the folder at the next close; in between the addon reports the old version and the new source revision (owner decision, 2026-11-12). Done so for 0.8.1. Any other HelloForever release waits whole for the close.
  - Never replace or remove an installed addon folder while the game is running.
