# reader: the strip reader in Rust

The reader of HelloLink's live-state strip, format 1 (`docs/STRIP.md`), in Rust. It is step 1
of #195: the Python reader stays, and nothing uses this one yet.

One crate, `hellolink`: a library and a binary.

- `src/strip1.rs`: the format and the row reader, as `tools/strip1.py`: frames, the fast
  block, objects, the Assembler, `read_row` (the finder, the width fit, depth 2 and 4).
- `src/bitmap.rs`: the BMP reader and the test renderer, as `Bitmap` and `render` in
  `tools/hellolink_strip.py`.
- `src/rows.rs`: one JSON line an image, byte for byte as `hellolink_strip.py rows` prints it.
- `src/main.rs`: the commands.

```
hellolink rows [--step T] a.bmp b.bmp ...                # as hellolink_strip.py rows
hellolink render cells.txt out.bmp [--scale S] [--dx X] [--dy Y] [--width W] [--height H]
hellolink render-rows --scale S [--step T] a.txt ...     # as tests/render_rows.py
hellolink serve REQUESTS REPLIES                         # as tests/render_rows.py --serve
```

## Build and test

```
cargo build --release --manifest-path reader/Cargo.toml
cargo test --manifest-path reader/Cargo.toml
cargo fmt --check --manifest-path reader/Cargo.toml
cargo clippy --manifest-path reader/Cargo.toml --all-targets -- -D warnings
```

The tests read the committed vectors in `tests/vectors/`, a frame written by hand from the
spec, and `hellolink/tests/fixtures/`: cells files of the addon test with the lines the
Python reader printed for them. They need no Python.

`tests/parity.sh` compares the two readers on many more cells files, at any scale: run the
Lua addon test with a dump directory, then the script, both from the repository's top (see
its head).

The width fit sums complex numbers as Python 3.14 does (with Neumaier's compensation). Python
3.12 and 3.13 sum them plainly, so a fitted width can differ in its last bits there.
