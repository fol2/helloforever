#!/bin/sh
# Writes the parity fixtures of `watch`, reader/hellolink/tests/stream/: what the Python reader
# (tools/hellolink_strip.py watch) does with the capture tool of each NAME.script. The fake
# capture tool (reader/hellolink/src/bin/fake_capture.rs, whose head says what a script line
# is) gives the same frames to any reader; hellolink/tests/processes/stream_parity.rs runs the
# Rust reader on it and must write the same bytes.
#
#     sh reader/tests/stream_parity.sh            # from the repository's top; python3, cargo
#     sh reader/tests/stream_parity.sh rust       # the same run of the Rust reader, to compare
#
# For each NAME it writes NAME.out (stdout), NAME.err (stderr), NAME.calls (the arguments of
# each run of the capture tool), NAME.record (the file of --record, with "t" and "started"
# masked: they are clock times) and NAME.place (the file of --remember). A script's head may
# hold "# args: ..." (RECORD and PLACE are the two files) and "# place: ..." (the file of
# --remember before the start). A run ends when the reader says "fake: done": the script's
# end; it is then stopped. The wait for it has a limit of 60 s: a run that does not end in it
# fails the tool. Every file is written to a new folder first, and the fixtures are replaced
# only when every script ran to its end (python); with `rust`, each file is compared as bytes
# with the fixture, and any difference fails the tool. Exit 0 only when all went well.
cd "$(dirname "$0")/.." || exit 1
MODE=${1:-python}
case $MODE in python | rust) ;; *) echo "usage: sh reader/tests/stream_parity.sh [rust]" >&2; exit 2 ;; esac
cargo build -q --bin fake_capture --bin hellolink || exit 1
FAKE=$PWD/target/debug/fake_capture
DIR=$PWD/hellolink/tests/stream
OUT=$(mktemp -d "${TMPDIR:-/tmp}/stream-parity.XXXXXX") || exit 1
trap 'rm -rf "$OUT"' EXIT
failed=0
for script in "$DIR"/*.script; do
    name=$(basename "$script" .script)
    st=$(mktemp -d "${TMPDIR:-/tmp}/stream-parity.XXXXXX") || exit 1
    args=$(sed -n 's/^# args: //p' "$script" | sed "s|RECORD|$st/record|; s|PLACE|$st/place|")
    place=$(sed -n 's/^# place: //p' "$script")
    [ -n "$place" ] && printf '%s' "$place" > "$st/place"
    if [ "$MODE" = rust ]; then set -- "$PWD/target/debug/hellolink"; else set -- python3 ../tools/hellolink_strip.py; fi
    # shellcheck disable=SC2086 # the args are words
    HELLOLINK_FAKE_SCRIPT=$script HELLOLINK_FAKE_STATE=$st "$@" watch --capture "$FAKE" $args > "$st/out" 2> "$st/err" &
    pid=$!
    i=0
    until grep -q 'fake: done' "$st/out" || [ $i -ge 600 ]; do sleep 0.1; i=$((i + 1)); done
    kill "$pid" 2>/dev/null
    wait "$pid" 2>/dev/null
    if [ $i -ge 600 ]; then
        echo "stream_parity: $name did not end in 60 s" >&2
        failed=1
        rm -rf "$st"
        continue
    fi
    cp "$st/out" "$OUT/$name.out"
    cp "$st/err" "$OUT/$name.err"
    cp "$st/calls" "$OUT/$name.calls"
    if [ -f "$st/record" ]; then
        sed 's/"t":[-0-9.e]*/"t":T/; s/"started":[-0-9.e+]*/"started":S/' "$st/record" > "$OUT/$name.record"
    fi
    [ -f "$st/place" ] && cp "$st/place" "$OUT/$name.place"
    rm -rf "$st"
done
[ "$failed" = 0 ] || { echo "stream_parity: a run did not end; nothing was written" >&2; exit 1; }
if [ "$MODE" = rust ]; then
    for f in "$OUT"/*; do
        cmp -s "$f" "$DIR/$(basename "$f")" || { echo "stream_parity: $(basename "$f") differs" >&2; failed=1; }
    done
    for f in "$DIR"/*; do
        case $f in *.script) continue ;; esac
        [ -e "$OUT/$(basename "$f")" ] || { echo "stream_parity: $(basename "$f") was not written" >&2; failed=1; }
    done
    [ "$failed" = 0 ] && echo "stream_parity: the Rust reader wrote every fixture, byte for byte"
    exit "$failed"
fi
for f in "$DIR"/*; do
    case $f in *.script) ;; *) rm -f "$f" ;; esac
done
cp "$OUT"/* "$DIR"/ && echo "stream_parity: the fixtures were written"
