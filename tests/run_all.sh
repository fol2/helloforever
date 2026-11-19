#!/bin/sh
# Every CI step at once, the same in CI and on this machine: run it before each push (#193).
# The Rust reader is built first (the addon test reads its frames with it); then every other
# step runs at the same time, its checks and tests among them. Each step's output, time and result is printed when
# all have ended; exit 1 if any failed.
# Usage: sh tests/run_all.sh [group]   (lua5.1, luacheck, python3 and cargo on PATH)
# With a group (rust, addon, watch, strip, harness, rest) only that group's steps run: CI runs
# the six groups on six machines at once, because one machine's four processors were the limit.
# `rust` checks the Rust reader (format, lint, its tests); `addon` only builds it, for the
# addon test that reads its frames with it.
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
# while the tests run: most of their time is the real 15 s limits.
step rust "The Rust reader: format, lint, tests (group addon builds the release)" \
    "cd reader && cargo fmt --check && { CARGO_TARGET_DIR=target/clippy cargo clippy --locked --all-targets -q -- -D warnings & lint=\$!; cargo test --locked -q; tests=\$?; wait \$lint && [ \$tests = 0 ]; }"
step harness "Unit tests (fight ids, envelope, freshness, quest states)" "lua5.1 tests/id_freshness.lua"
step harness "Mock-client harness" "lua5.1 tests/fights_harness_v4.lua ./HelloForever '$T/sv1.lua' '$T/truth1.json'"
step harness "Mock-client harness, with the extra reset sections" "lua5.1 tests/fights_harness_more.lua ./HelloForever '$T/sv2.lua' '$T/truth2.json'"
step harness "Mock-client harness, with the assistant's sections" "lua5.1 tests/assist_harness.lua ./HelloForever '$T/sv3.lua' '$T/truth3.json'"
step rest "AI-SDLC adoption (controls present and wired)" "sh .github/ai_sdlc_adoption.sh"
step rest "AI-SDLC review status (pending before a review)" "python3 tests/ai_sdlc_review_status_test.py"
step rest "HelloLink spike (a tool's text reaches the addon through a slot)" "python3 tools/hellolink.py install '$T/addons' --slots 3 && lua5.1 tests/hellolink_test.lua '$T/addons'"
step rest "HelloLink's API probe (/hlink probe api)" "lua5.1 tests/hellolink_probe_test.lua"
step rest "HelloLink commands (/hlink send, /hlink probe depth)" "lua5.1 tests/hellolink_strip_test.lua '$T/strip'"
step rest "The reader tool's bitmap, depth probe and screenshots" "python3 tests/hellolink_strip_test.py"
step rest "Live-state strip, format 1 (the Python codec against the spec)" "python3 tests/strip1_test.py"
step addon "Live-state strip, format 1 (the addon's row, read by the Rust reader)" "lua5.1 tests/strip1_addon_test.lua '$T/row'"
step addon "Live-state strip, its picture over a run and its memory a second" "lua5.1 tests/strip_perf_test.lua"
step watch "Live-state strip, the reader that follows the row" "python3 tests/strip_watch_test.py"
step strip "Live-state strip, the capture's time limit holds for a late frame" "python3 tests/strip_capture_late_test.py"
for t in fallback fallback_missing waiting waiting_fallback stream_again slow_start slow_stream replayd_hint stream_back api start record; do
    step strip "Live-state strip, $t" "python3 tests/strip_${t}_test.py"
done
step rest "The reader installs outside any git checkout" "python3 tests/install_reader_test.py"
step rest "The assistant's way in (the slot file's assist part; what HelloLink takes)" "python3 tests/hellolink_assist_test.py && lua5.1 tests/hellolink_assist_test.lua"
step rest "The assistant program (step 3)" "python3 tests/assistant_test.py"
step rest "Lint" "luacheck HelloForever HelloLink tests"
step rest "Release checks (versions agree, changelog entry, TOC files exist)" "python3 tools/package.py --check --no-tests"
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
