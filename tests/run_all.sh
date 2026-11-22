#!/bin/sh
# Every CI step at once, the same in CI and on this machine: run it before each push (#193).
# The Rust reader is built first (the addon test reads its frames with it); then every other
# step runs at the same time, its checks and tests among them. Each step's output, time and result is printed when
# all have ended; exit 1 if any failed.
# Usage: sh tests/run_all.sh [group]   (lua5.1, luacheck, cargo, gzip, unzip and zipinfo on PATH)
# With a group (rust, addon, harness, rest) only that group's steps run: CI runs the groups on
# machines of their own at once, because one machine's four processors were the limit.
# `rust` checks the Rust reader (format, lint, its tests); `addon` builds it, for the steps that
# run it (the addon's row read back, the probe's floor rows, the HelloLink spike, the release checks).
cd "$(dirname "$0")/.." || exit 1
GROUP=${1:-}
T=$(mktemp -d "${TMPDIR:-/tmp}/helloforever-ci.XXXXXX") || { echo "run_all: no temporary folder" >&2; exit 1; }
[ -n "$T" ] && [ -d "$T" ] || { echo "run_all: no temporary folder" >&2; exit 1; }
trap 'rm -rf "$T"' EXIT
trap 'exit 130' INT TERM
mkdir -p "$T/addons" "$T/strip" "$T/row" || exit 1
n=0
step() {   # step <group> <name> <command>: runs in the background; writes <n>.done with its exit code and seconds
    [ -z "$GROUP" ] || [ "$GROUP" = "$1" ] || return 0
    shift
    n=$((n + 1))
    printf '%s\n' "$1" > "$T/$n.name"
    ( start=$(date +%s); sh -c "$2" > "$T/$n.log" 2>&1; echo "$? $(( $(date +%s) - start ))" > "$T/$n.done" ) &
}
step addon "The Rust reader: build" "cd reader && cargo build --release --locked -q"
wait    # the addon test below needs the binary
if [ "$n" = 1 ]; then
    [ "$(cut -d' ' -f1 "$T/1.done" 2>/dev/null)" = 0 ] || { cat "$T/1.log"; echo "run_all: the Rust reader did not build" >&2; exit 1; }
fi
# The lint (in a target folder of its own, so that it does not wait for the tests' build) runs
# while the tests run. 32 test threads: most of the processes program's tests wait on real
# limits and use little processor, so one thread a core made it the sum of their waits divided
# by four on CI; with 32 it is its slowest test (about 12 s).
step rust "The Rust reader: format, lint, tests (group addon builds the release)" \
    "cd reader && cargo fmt --check && { CARGO_TARGET_DIR=target/clippy cargo clippy --locked --all-targets -q -- -D warnings & lint=\$!; RUST_TEST_THREADS=32 cargo test --locked -q --no-fail-fast; tests=\$?; wait \$lint && [ \$tests = 0 ]; }"
step harness "Unit tests (fight ids, envelope, freshness, quest states)" "lua5.1 tests/id_freshness.lua"
step harness "Mock-client harness" "lua5.1 tests/fights_harness_v4.lua ./HelloForever '$T/sv1.lua' '$T/truth1.json'"
step harness "Mock-client harness, with the extra reset sections" "lua5.1 tests/fights_harness_more.lua ./HelloForever '$T/sv2.lua' '$T/truth2.json'"
step harness "Mock-client harness, with the assistant's sections" "lua5.1 tests/assist_harness.lua ./HelloForever '$T/sv3.lua' '$T/truth3.json'"
step rest "AI-SDLC adoption (controls present and wired)" "sh .github/ai_sdlc_adoption.sh"
step rest "AI-SDLC review status (pending before a review)" "sh tests/ai_sdlc_review_status_test.sh"
step addon "HelloLink spike (a tool's text reaches the addon through a slot)" "reader/target/release/hellolink install '$T/addons' --slots 3 >/dev/null && lua5.1 tests/hellolink_test.lua '$T/addons'"
step rest "HelloLink's API probe (/hlink probe api)" "lua5.1 tests/hellolink_probe_test.lua"
step rest "HelloLink's API probe: errors (secret, long)" "lua5.1 tests/hellolink_probe_errors_test.lua"
step addon "HelloLink commands (/hlink send, /hlink probe depth, its floor rows read by the Rust reader)" "lua5.1 tests/hellolink_strip_test.lua '$T/strip'"
step addon "Live-state strip, format 1 (the addon's row, read by the Rust reader)" "lua5.1 tests/strip1_addon_test.lua '$T/row'"
step addon "Live-state strip, its picture over a run and its memory a second" "lua5.1 tests/strip_perf_test.lua"
step rest "The assistant's way in (what HelloLink takes from the slot file's assist part)" "lua5.1 tests/hellolink_assist_test.lua"
step rest "Lint" "luacheck HelloForever HelloLink tests"
step addon "Release checks (versions agree, changelog entry, TOC files exist)" "reader/target/release/hellolink package --check --no-tests"
wait
failed=0
i=1
while [ "$i" -le "$n" ]; do
    # a step that left no result failed, whatever the step before it did
    code=missing secs=?
    [ -s "$T/$i.done" ] && read -r code secs < "$T/$i.done"
    if [ "$code" = 0 ]; then mark=ok; else mark="FAILED (exit $code)"; failed=$((failed + 1)); fi
    printf '\n=== %s: %s (%s s)\n' "$(cat "$T/$i.name")" "$mark" "$secs"
    if [ "$code" = 0 ]; then tail -n 3 "$T/$i.log"; else cat "$T/$i.log"; fi
    i=$((i + 1))
done
printf '\n== %d steps%s, %d failed\n' "$n" "${GROUP:+ of group $GROUP}" "$failed"
[ "$failed" = 0 ]
