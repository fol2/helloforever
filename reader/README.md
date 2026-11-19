# reader: the strip reader in Rust

The reader of HelloLink's live-state strip, format 1 (`docs/STRIP.md`), in Rust. It is steps 1
and 2a of #195: the Python reader stays, and only the tests use this one yet.

One crate, `hellolink`: a library and a binary.

- `src/strip1.rs`: the format and the row reader, as `tools/strip1.py`: frames, the fast
  block, objects, the Assembler, `read_row` (the finder, the width fit, depth 2 and 4, the
  last palette kept).
- `src/bitmap.rs`: the BMP reader, the test renderer and a capture stream's frames, as
  `Bitmap`, `render` and `frames_from` in `tools/hellolink_strip.py`.
- `src/rows.rs`: one JSON line an image, byte for byte as `hellolink_strip.py rows` prints it;
  JSON as Python's `json.dumps` writes it.
- `src/watch.rs`: `Quality` and `Watcher` of `tools/strip1.py`: the reader that follows the
  row and says what is new, as events (JSON values). `feed_row` takes a row already read, so a
  record can note it first (the Python Watcher's `on_row`).
- `src/record.rs`: the `Recorder` of `tools/hellolink_strip.py`, the file of `--record`
  (`docs/STRIP.md`, section 10).
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

`hellolink/tests/watch/` holds sequences of captures and idle turns, with the events and the
record the Python Watcher and Recorder made of them; `hellolink/tests/watch_parity.rs` must make the same
bytes. `tests/watch_parity.py` writes them again (from the repository's top, Python 3.14); its
head says what a step is.

`tests/parity.sh` compares the two readers on many more cells files, at any scale: run the
Lua addon test with a dump directory, then the script, both from the repository's top (see
its head).

The width fit sums complex numbers as Python 3.14 does (with Neumaier's compensation). Python
3.12 and 3.13 sum them plainly, so a fitted width can differ in its last bits there.

## The Python checks in Rust

Each check of the Python tests below that is about the stream's framing, the Watcher, the
fall-back or the record's lines is an assert in `hellolink/tests/watch.rs` or
`hellolink/tests/record.rs` whose message is the check's name, word for word. The others need
the capture processes, the slot writer or the `watch` command: step 2b.

`tests/strip_watch_test.py`:

| Python check | Rust test |
|---|---|
| two frames on the pipe are two bitmaps of the size the header gives | `the_streams_framing` |
| a frame cut short by the end of the pipe is dropped | `the_streams_framing` |
| bytes that are not a frame are refused | `the_streams_framing` |
| a frame that claims an absurd size is refused | `the_streams_framing` |
| a raw frame reads like an image: the session, the levels, the frame | `the_streams_framing` |
| a raw frame with too few bytes is refused | `the_streams_framing` |
| the first capture gives the state: session, seq, depth, levels by name, the fast block | `the_watcher` |
| the same capture again gives nothing | `the_watcher` |
| level squares that changed with no new seq give a levels event | `the_watcher` |
| a new seq gives a state event | `the_watcher` |
| the place of the row is remembered after a good read | `the_watcher` |
| an object in several chunks, each seen three times, comes out once and whole | `the_watcher` |
| two captures with no row ask for a new search, and 30 say the row is lost; each once | `the_watcher` |
| after that the row is found again by searching | `the_watcher` |
| another session is a new state, even with a seq seen before | `the_watcher` |
| the same seq read again for 3 s gives nothing | `what_time_makes_old` |
| after 3 s without a new seq the state is called stale, once; frames still decode there, so no new search | `what_time_makes_old` |
| a new seq is fresh again, and can go stale again | `what_time_makes_old` |
| with no capture at all (the row moved away, the old place stands still), time alone says stale, once, and asks for a search every 3 s | `what_time_makes_old` |
| after three rounds of six objects (21.6 s) an object is not yet stale: there are eight (#62) | `what_time_makes_old` |
| after three rounds of eight objects (28.8 s) it is not yet stale either: there are nine (#64) | `what_time_makes_old` |
| after three rounds of nine objects (32.4 s) it is not yet stale either: there are ten (#68) | `what_time_makes_old` |
| after three rounds of ten objects (36 s) it is not yet stale either: there are eleven (#74) | `what_time_makes_old` |
| after three rounds of eleven objects (39.6 s) it is not yet stale either: there are twelve (#109) | `what_time_makes_old` |
| after three rounds of twelve objects (43.2 s) it is not yet stale either: there are thirteen (#127) | `what_time_makes_old` |
| after three rounds of thirteen, fourteen and fifteen objects (46.8, 50.4, 54 s) it is not yet stale: there are sixteen (#138) | `what_time_makes_old` |
| after three rounds of sixteen and seventeen objects (57.6, 61.2 s) it is not yet stale: there are eighteen (#180) | `what_time_makes_old` |
| after three rounds of eighteen to twenty-two objects (64.8 to 79.2 s) it is not yet stale: there are twenty-three (0.8.0) | `what_time_makes_old` |
| an object not seen whole for three largest rounds (82.8 s at a dwell of 0.1 s) is called stale, once | `what_time_makes_old` |
| seen whole again in the same version, it is called fresh, and can go stale again | `what_time_makes_old` |
| at a dwell of 0.2 s the time doubles: not stale after 165.4 s ... | `what_time_makes_old` |
| ... and stale after 165.6 s (3 x 23 x 12 x 0.2 s) | `what_time_makes_old` |
| a chunk that fails the object check, seen twice, does not make the old object fresh | `what_time_makes_old` |
| with no frame ever decoded and no capture coming, a search is still asked for every 3 s, and nothing is called stale | `what_time_makes_old` |
| frames that keep failing ask for the fall-back after 200, though the row was searched for again on the way | `one_watcher_for_the_whole_run` |
| a palette that cannot be told apart asks for depth 2, once, with the session from the two-level squares | `asking_for_the_fall_back` |
| a new session that is as bad asks again | `asking_for_the_fall_back` |
| 250 good captures at depth 4 never ask | `asking_for_the_fall_back` |
| the request is written to every slot as the strip field of the spec | step 2b: the slot writer |
| a later write of a text keeps the request: the addon may not have looked yet | step 2b: the slot writer |
| a request for another session replaces it | step 2b: the slot writer |
| with no request there is no strip field | step 2b: the slot writer |
| a quiet write prints nothing (the reader's own output stays clean JSON) | step 2b: the slot writer |
| one_frame takes the first frame and stops the process, though it would run on | step 2b: the capture processes |
| stream_frames gives the frames, and None when none came for a while | step 2b: the capture processes |
| a capture process that fails is an error with its reason, not an empty stream | step 2b: the capture processes |
| a capture tool that is not there is reported, for the fall-back to take over | step 2b: the capture processes |
| one_frame says why a capture failed, instead of 'no frame' | step 2b: the capture processes |
| one_frame gives None for a capture that ended cleanly with nothing | step 2b: the capture processes |
| output that is not a frame from a process that runs on: stopped at once and reported, not waited for | step 2b: the capture processes |
| a command that cannot be started is a failed capture too | step 2b: the capture processes |
| output that is not frames is a failed capture, not a silent end | step 2b: the capture processes |
| leaving a stream early stops its process and its reader thread, though the queue was full | step 2b: the capture processes |
| the slot writer does not take words in a text for a request | step 2b: the slot writer |
| so a text that looks like a request leaves none behind | step 2b: the slot writer |
| sixteen writers at once, one of them a request: the request is still there after all of them | step 2b: the slot writer |
| a capture that gives no frame is a failure after 3 s, not waited for | step 2b: the capture processes |
| ... and it was asked to stop, not killed | step 2b: the capture processes |
| a capture that gives no frame and does not listen is killed two seconds later | step 2b: the capture processes |
| a capture that fails by itself after it was told to stop is still a failure, with its reason | step 2b: the capture processes |
| a capture whose output ends before it leaves is waited for: no frame, no failure, no signal | step 2b: the capture processes |
| a capture that gave its frame is asked to stop, not killed | step 2b: the capture processes |
| a stream gives its frame, after an idle turn | step 2b: the capture processes |
| a stream whose reader leaves early is asked to stop, not killed | step 2b: the capture processes |
| a stream whose output ends before it leaves ends cleanly | step 2b: the capture processes |
| a capture whose output ends but which stays and does not listen is a failure, not a clean end | step 2b: the capture processes |
| ... and the same for a stream | step 2b: the capture processes |

`tests/strip_record_test.py`:

| Python check | Rust test |
|---|---|
| the reader has a Recorder | the build: `hellolink::record::Recorder` |
| the Watcher's events are as without a record | `the_recorder_on_the_watcher_capture_by_capture` |
| a header and one line a capture | `the_recorder_on_the_watcher_capture_by_capture` |
| line %d is whole and right | `the_recorder_on_the_watcher_capture_by_capture` |
| a second run appends to the file with a header of its own | `the_recorder_on_the_watcher_capture_by_capture` |
| watch --record FILE writes a header, every capture of the search, then each capture of the stream | step 2b: the `watch` command |
| watch without --record writes no file | step 2b: the `watch` command |
| the slow fall-back records the image of a display without the row, then the one with it, once each | step 2b: the `watch` command |
