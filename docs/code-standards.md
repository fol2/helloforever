# Code standards

Commands, repo-specific hard rules and repo-specific acceptance criteria. Changed by PR. The shared rules and acceptance criteria live in the AI-SDLC skill (`SKILL.md` §4 and §5) and are not copied here. A rule that must always hold names the hook or check that enforces it.

## Commands

Each check is one command that exits non-zero on failure. `sh tests/run_all.sh` runs every one of them at once, with the lint and the release checks, and prints each one's result and time: CI runs it (`.github/workflows/ci.yml`, on Lua 5.1), and it is the command to run before each push (#193). A new test is added there.

- Unit tests: `lua5.1 tests/id_freshness.lua`. Healthy: `== 36 checks, 0 failed`, exit 0.
- Mock-client harness: `lua5.1 tests/fights_harness_v4.lua ./HelloForever <out_SV.lua> <out_truth.json>`. Healthy: exit 0. Needs Lua 5.1 exactly.
- The same with the extra reset sections: `lua5.1 tests/fights_harness_more.lua ./HelloForever <out_SV.lua> <out_truth.json>`. Healthy: exit 0.
- The same with the assistant's sections (`docs/specs/115.md`): `lua5.1 tests/assist_harness.lua ./HelloForever <out_SV.lua> <out_truth.json>`. Healthy: `== 484 checks, 0 failed`, exit 0.
- Adoption test: `sh .github/ai_sdlc_adoption.sh`. Healthy: `AI-SDLC ADOPTION OK`, exit 0. Each failure names the missing control. Needs `jq`.
- HelloLink spike: `reader/target/release/hellolink install <dir> --slots 3 && lua5.1 tests/hellolink_test.lua <dir>` (`<dir>` is a new, empty folder). Healthy: `== 8 checks, 0 failed`, exit 0.
- HelloLink's API probe: `lua5.1 tests/hellolink_probe_test.lua`. Healthy: `== 57 checks, 0 failed`, exit 0.
- The Rust reader (`reader/hellolink`, #195): the strip reader, its local API, the slot writer, the assistant program (step 3), the installers and the release packer, one program, `reader/target/release/hellolink`. Build it with `cargo build --release --locked` in `reader/`. Its format check, lint and tests: `sh tests/run_all.sh rust`. Healthy: exit 0. The Python tests were deleted in #195 step 3c; `reader/README.md` ("The Python checks in Rust") names the Rust test that holds each of their checks.
- The assistant's way in: `lua5.1 tests/hellolink_assist_test.lua` (`== 35 checks, 0 failed`, what HelloLink takes). The writer's side (the slot TOC and the slot file's parts) is in the Rust tests.
- HelloLink commands (`/hlink send`, `/hlink probe depth`) and its settings window: `lua5.1 tests/hellolink_strip_test.lua <dir>` (`<dir>` is an existing scratch folder). Healthy: `== 49 checks, 0 failed`, exit 0.
- Live-state strip, the addon's row: `lua5.1 tests/strip1_addon_test.lua <dir>` (`<dir>` is an existing scratch folder). Healthy: `== 511 checks, 0 failed`, exit 0.
- Live-state strip, its cost: `lua5.1 tests/strip_perf_test.lua`. Healthy: `== 16 checks, 0 failed`, exit 0 (the picture of thirty seconds of play, square by square, and under 20 KB of memory asked for in a second; the same play with the 0.8.0 sources full, each read, under 30 KB a second; the lines above the checks give the memory, the time and the slowest frame, and the times are not held).
- Live-state strip, the reader that follows the row: `reader/target/release/hellolink watch` (`reader/README.md`); its tests are in the Rust tests. The capture stream itself (`tools/strip_capture.swift`) builds on this Mac with `swiftc -O -swift-version 5 tools/strip_capture.swift -o <file>` and is not built in CI; `hellolink watch` builds it into `~/Library/Caches/HelloLink/` when needed.
- Install the reader outside any git checkout (`docs/STRIP.md`, section 10): `reader/target/release/hellolink install-reader`. Healthy: `<commit> installed in ~/Library/Application Support/HelloLink/reader; start the reader from there ...`, exit 0. Stop the reader first. Test: `reader/hellolink/tests/install.rs`, in the Rust tests.
- Lint: `luacheck HelloForever HelloLink tests`. Healthy: `0 warnings / 0 errors`.
- Release checks: `reader/target/release/hellolink package --check --no-tests`. Healthy: `HelloForever <version>: TOC, VERSION_FALLBACK, SOURCE_REVISION and CHANGELOG agree`.
- Build: `reader/target/release/hellolink package`. Healthy: `dist/HelloForever-<version>.zip` and SHA-256 sums.
- Deploy: run the tests first (`hellolink package` runs them with `lua5.1`, which this Mac does not have: use the two `luajit` commands under "This machine", or rely on CI for a merged commit), then `reader/target/release/hellolink package --no-tests`, then replace `Interface/AddOns/HelloForever` with the unzipped build. Done this way four times on 2026-11-12 (0.6.0, 0.7.0 twice, 0.7.1). Replacing the folder is only for when the game is closed: check with `pgrep -f 'World of Warcraft.app/Contents/MacOS/World of Warcraft'` and wait if it runs (owner decision, 2026-11-12). Copy `SavedVariables/HelloForever.lua` to `dist/sv-backup-before-<version>/` first. Healthy: the installed files' SHA-256 equal the build's. A public release is a tag and a GitHub release (`plan/03-release.md`).
- Rollback: build the previous version (`mkdir <dir> && git archive <tag or sha> | tar -x -C <dir>`, then `reader/target/release/hellolink package --no-tests --root <dir>`; untried) and install it the same way; restore the SavedVariables backup if the format changed. **Never rehearsed.**
- Health check: `/hello selftest` in the game (`plan/01-in-game-verification.md`). Only a person with the client can run it.

## Enforcement in this repo

- AI-SDLC checks: `.github/workflows/ai-sdlc-checks.yml`, on GitHub-hosted runners. Not required by branch protection, by the owner's decision (`docs/owner-decisions.md`, 15 Nov 2026). The loop holds the merge gate itself: `sh .ai-sdlc/review_on_head.sh <PR> <sha>` must exit 0, then `gh pr merge --match-head-commit <sha>`.
- The checks implementation is a copy (`.github/workflows/ai-sdlc-checks-impl.yml`), because the skill's reusable workflow cannot be called from this account. Refresh `.ai-sdlc/` with the skill's `scripts/adopt.sh` and the copy by hand when the skill changes. The copy differs from the skill in two places, named in its header: the runner, and a head that no review names yet is `pending`, not a failure (#84), so a push does not turn the PR red before its review. Test: `sh tests/ai_sdlc_review_status_test.sh` (`== 11 checks, 0 failed`).
- Tests, lint and release checks: `.github/workflows/ci.yml`, on every pull request.
- Hooks: `.claude/hooks/guard-edits.sh`, `.claude/hooks/spend-gate.sh`. No spend patterns: nothing in this repo spends money.
- Secret scan beyond the sample patterns: GitGuardian (the account's GitHub app).
- Not set up: the nightly lessons audit (it needs a self-hosted runner with the agent CLI and a token), agent-setup evals, weekly metrics, CODEOWNERS.

## Repo-specific hard rules

1. No code, rule table or spell table from Matty7500Hunter enters this repository; its licence is All Rights Reserved. Read its live global at runtime only (`HelloAim/PLAN.md`). Enforced by: review only.
2. HelloForever never writes to another addon: `rawget` only, no method calls, no callbacks (`docs/SCHEMA.md`). Enforced by: review only.
3. No addon automates a key press or a cast (`HelloAim/PLAN.md`, Terms of Use). Enforced by: review only.
4. No SavedVariables dump or real fight data is committed. Enforced by: `.gitignore`; review.
5. The TOC version, `VERSION_FALLBACK`, `SOURCE_REVISION` and the changelog change together. Enforced by: `hellolink package --check` (the Rust packer, `reader/hellolink`) in CI.
6. A change to the saved-data format updates `docs/SCHEMA.md` in the same PR; the offline pipeline (`fol2/wow-data`) reads it. Enforced by: review only.
7. A new test is trusted only after it was seen failing: on the code without the fix, or on a mutation that takes the guard out. When a fault raises nothing (a secret value, a call not made), the test records that the guard was asked or the order of the calls, and checks that. A check whose condition holds whatever the code does (a nil equal to a nil, a type check that refuses the mock anyway) is no check. The PR names the red run. Enforced by: review (the reviewer runs mutations). From `LESSONS.md`, seen on 13, 14, 15 and 16 Nov 2026 (#59, #65, #147, #149, #153).
8. A gated command (a merge, a commit, a push) runs only after its gate passed: in a shell call of its own, issued after the gate's result was read and seen to pass; or after `&&` behind a command whose exit code is that result. Never after `;`, and never after a loop or a wait that ends whatever the result. Enforced by: review only. From `LESSONS.md`, seen on 13, 19 and 21 Nov 2026 (#54, #205, #249).

## Repo-specific acceptance criteria

1. A PR that changes addon behaviour says what was checked in the mock client and what still needs the game, and adds the in-game check to `plan/`.

## This machine

- The development Mac's `lua` is 5.5, not 5.1: it runs `tests/id_freshness.lua` but not the harness. Use `luajit` for the harness (below).
- The game loads `Interface/AddOns/HelloForever` from a real folder, unzipped from the release zip (`hellolink package`; 0.6.0 on 2026-11-12). Editing this repository does not change what the game loads: build the zip and replace the folder.
- `luajit` and `luacheck` are installed (Homebrew). The tests here: `luajit tests/id_freshness.lua` and `luajit tests/fights_harness_more.lua ./HelloForever <out_SV.lua> <out_truth.json>` (the harness with the extra sections).
- Two ways to install, by what the release changes (owner decisions, 2026-11-12):
  - Only the content of `.lua` files that are already installed: copy each file over its installed copy (write a temporary file beside it, then rename), also while the game runs. Then the owner types `/reload`. Used for HelloLink on 2026-11-12.
  - Anything else (a changed `.toc`, a new or removed file, a new addon): wait until the game is closed, then replace the folder as under Deploy. A HelloForever release changes the `.toc` version. When that version line is its only change outside the `.lua` files that are already installed (no file added, removed or renamed, no change to the files the `.toc` lists or their order): copy its changed `.lua` files as above at once, all of them before the `/reload`, and replace the folder at the next close; in between the addon reports the old version and the new source revision (owner decision, 2026-11-12). Done so for 0.8.1. Any other HelloForever release waits whole for the close.
  - Never replace or remove an installed addon folder while the game is running.
