#!/bin/sh
# Runs the Rust build for `rust-anything app replay`. The Python tools wrote their errors
# without a name; the Rust program starts each with "hellolink: ". The name is taken off here,
# in the harness, never in the program. stderr is passed on after the program ends (replay
# compares each stream on its own). HELLOLINK names the binary (default: the debug build).
bin=${HELLOLINK:-$(cd "$(dirname "$0")/.." && pwd)/target/debug/hellolink}
err=$(mktemp "${TMPDIR:-/tmp}/hellolink-err.XXXXXX") || exit 125
"$bin" "$@" 2>"$err"
code=$?
sed 's/^hellolink: //' "$err" >&2
rm -f "$err"
exit "$code"
