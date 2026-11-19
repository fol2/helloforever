#!/bin/sh
# Parity of the Rust reader with the Python one, on the cells files of a directory.
# Make them with: lua5.1 tests/strip1_addon_test.lua <empty dir>  (writes row_NNN.txt)
#
#     reader/tests/parity.sh <cells dir> [batch size] [every n-th batch]
#
# Run from the repository's top. For each batch of consecutive cells files: the JSON lines of
# `python3 tests/render_rows.py` and of `hellolink render-rows` must be equal, and each BMP
# the Python drew must equal the one `hellolink render` draws. Prints the counts; exits 1 on
# a difference. Needs a release build: cargo build --release --manifest-path reader/Cargo.toml
set -eu
dir=$1; size=${2:-50}; every=${3:-1}
scale=1.312500000000    # the addon test's: 1 / (768 / 1440 / 0.7)
bin=reader/target/release/hellolink
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
ls "$dir"/row_*.txt | sort -V | split -l "$size" - "$tmp/batch."
batches=0 files=0 lines=0 differ=0 bmps=0 bmpdiffer=0 n=0
for b in "$tmp"/batch.*; do
    n=$((n + 1)); [ $(( (n - 1) % every )) -eq 0 ] || continue
    batches=$((batches + 1))
    # shellcheck disable=SC2046
    python3 tests/render_rows.py --scale $scale --step 0.1 $(cat "$b") > "$tmp/py"
    # shellcheck disable=SC2046
    "$bin" render-rows --scale $scale --step 0.1 $(cat "$b") > "$tmp/rs"
    files=$((files + $(wc -l < "$b"))); lines=$((lines + $(wc -l < "$tmp/py")))
    if ! cmp -s "$tmp/py" "$tmp/rs"; then
        differ=$((differ + $(diff "$tmp/py" "$tmp/rs" | grep -c '^<' || true)))
        echo "differs: $b ($(head -1 "$b"))"; diff "$tmp/py" "$tmp/rs" | head -4
    fi
    while read -r cells; do
        "$bin" render "$cells" "$tmp/rs.bmp" --scale $scale --width 2560 --height 12
        bmps=$((bmps + 1))
        cmp -s "${cells%.txt}.bmp" "$tmp/rs.bmp" || { bmpdiffer=$((bmpdiffer + 1)); echo "BMP differs: $cells"; }
    done < "$b"
done
echo "$batches batches, $files cells files, $lines lines: $differ lines differ; $bmps BMPs: $bmpdiffer differ"
[ "$differ" -eq 0 ] && [ "$bmpdiffer" -eq 0 ]
