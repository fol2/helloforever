# reader: the strip reader in Rust

The reader of HelloLink's live-state strip, format 1 (`docs/STRIP.md`), in Rust. It replaced
the Python reader (#195): the installed reader is this program since 20 Nov 2026
(`plan/README.md`), and step 3c deleted the Python tools and tests.

One crate, `hellolink`: a library and a binary.

- `src/strip1.rs`: the format and the row reader: frames, the fast block, objects, the
  Assembler, `read_row` (the finder, the width fit, depth 2 and 4, the last palette kept).
- `src/bitmap.rs`: the BMP reader, the test renderer and a capture stream's frames (`Bitmap`,
  `render` and `frames_from`).
- `src/rows.rs`: one JSON line an image, byte for byte as the Python reader printed it; JSON
  as Python's `json.dumps` writes it.
- `src/watch.rs`: `Quality` and `Watcher`: the reader that follows the row and says what is
  new, as events (JSON values). `feed_row` takes a row already read, so a record can note it
  first.
- `src/record.rs`: the `Recorder`, the file of `--record` (`docs/STRIP.md`, section 10).
- `src/pulls.rs`: `--pulls`, a line for each pull (`docs/PULLS.md`), also from `replay RECORD --pulls DIR`.
- `src/capture.rs`: the processes around the capture: `capture_tool`, `stop`, `ended`,
  `one_frame`, `locate` (`displays` and `look`), `Stream` (`stream_frames`) and
  `Screencapture` (`screencapture_frames`).
- `src/follow.rs`: `watch`. What it does outside itself goes through a `World` (the clock,
  sleeps, the capture tool, the look, the stream, the fall-back, the output), so that a test
  gives its own. A stream is a `Capture`: frames, and `close`, which says whether the capture
  failed.
- `src/api.rs`: the local HTTP API of `--serve`: `GET /state`, `GET /events` (server-sent
  events), on 127.0.0.1 only, on `std::net`.
- `src/slots.rs`: the slot writer, `write`: the slot file's three parts (the text, the
  strip's request, the assistant's cards), carried over in `.parts.json` under a `flock`.
- `src/assistant.rs`: the assistant program, `assist`: it follows the API's `/events`,
  answers object 13's `session` question with a card, and writes the slots' assist part at
  least once a minute.
- `src/history.rs`: `history`, and `assist --history`: HelloForever's saved data file (the Lua the
  client writes, the fight log's `d1:` and `j1:` blobs) and each enemy's usual fight time over
  the character's whole saved history (`docs/specs/331.md`).
- `src/install.rs`: `install-reader`: this program and the capture source, installed outside
  any checkout with a VERSION file that names the commit. An installed program builds the
  capture tool from the source beside it (`capture::capture_source`).
- `src/package.rs`: `package`: the release checks, the two Lua suites, the zip (deflated with
  `miniz_oxide`; CRC-32 and SHA-256 written here, checked against the FIPS 180 vectors and
  Python's `hashlib`).
- `src/bin/fake_capture.rs`: a stand-in for the capture tool, for the tests only (its head says
  what it does).
- `src/main.rs`: the commands.

```
hellolink rows [--step T] a.bmp b.bmp ...                # each image's row, as JSON lines
hellolink render cells.txt out.bmp [--scale S] [--dx X] [--dy Y] [--width W] [--height H]
hellolink render-rows --scale S [--step T] a.txt ...     # render each cells file, then rows
hellolink serve REQUESTS REPLIES                         # the addon test's server
hellolink watch [--json] [--fps N] [--addons DIR] [--serve PORT] [--capture TOOL]
                [--remember FILE] [--record FILE] [--pulls DIR]   # follow the row
hellolink write ADDONS [TEXT | -] [--strip-session N] [--assist FILE | -]
                                                         # the slot file, into every slot
hellolink assist --addons DIR [--reader URL] [--log FILE] [--history HELLOFOREVER.LUA]
                                                         # the assistant program
hellolink history HELLOFOREVER.LUA                       # each character's fights and usual times
hellolink install ADDONS [--slots N]                     # HelloLink and its slots
hellolink install-reader [--to DIR] [--checkout DIR]     # this program, outside any checkout
hellolink package [--check] [--no-tests] [--root DIR]    # check and zip a release
hellolink built-from                                     # the digest it was built from
```

To install the reader: `cargo build --release --locked`, then
`target/release/hellolink install-reader` (the default folder is
`~/Library/Application Support/HelloLink/reader`). The folder then holds this program
(`hellolink`), the capture tool's source (`strip_capture.swift`) and `VERSION`, which names
the commit. VERSION is true by construction:
`build.rs` writes into the program a digest of the files it is built from
(`src/built_from.rs`: the Cargo files, `build.rs` and every `.rs` under `src/` but `src/bin`,
the tests' own programs), and the install goes on only when the commit's files give the same
digest, and the copied program says the same (`hellolink built-from`); the capture source is
taken from the commit, not the working tree.

The lock beside the folder, the layout and the folder's identity guard an install. It
refuses, changing nothing but the lock file, when:

- the program was not built from the commit (build it first), or the commit lacks an input or
  the capture source;
- `--to` goes through a link that leads nowhere, or has a kept install's name
  (`<name>-previous-<n>`; an existing folder by the name the disk stores, so another case of it
  is the same name on macOS);
- the folder holds anything but a whole earlier install: the three files above, each a plain
  file, and nothing else (a folder of the Python reader's files is no install: move it away by
  hand);
- a reader or the assistant program runs from the folder, or another install into it runs.
  The lock is `.reader.lock` in the folder's parent, so it stays put while the folder moves.
  `watch` and `assist` run from an install hold it shared while they run, so any account's
  reader holds it; they find it from the program's real path (a link to it leads to the same
  lock) and, from a kept `reader-previous-<n>`, take the lock of `reader`. They do not start
  while an install holds it. The install holds it exclusive from start to end, or refuses, so
  two installs never run at once. It makes the file (empty) when it is not there, and the file
  stays, a refusal included;
- the folder moved aside at the end is not the one checked (its device and inode): one put in
  its place meanwhile is put back.

The earlier install is never deleted: it is kept beside the new one as
`reader-previous-<n>` (the line says where), whole, with anything that came into it
meanwhile; delete it by hand when the new one runs well. The program is then
`<folder>/hellolink watch ...` and `<folder>/hellolink assist ...`. There is no way back to
the Python reader; if the Rust reader fails, it is fixed. The owner, 19 Nov 2026: "we won't
return to python. we'll fix the rust instead". `--checkout` is for the tests.

The capture tool is built into `~/Library/Caches/HelloLink/strip_capture-<digest of its
source>`, from a copy of the bytes the digest is of, under a name of its own first: a reader takes only a tool built from its own source
(an install and a checkout share the folder; the Python reader's was `strip_capture`). Tools of
older sources stay there; delete them by hand.

`watch -h` prints its options. As argparse, an option without its value (the next word is
another option) is refused before anything is done.
`probe` is not ported (it needs the depth probe's own finder).

What the Rust program did differently from the Python one it replaced, on purpose or as the
language gives it (the record of the port; the Python is gone since step 3c):

- `/state` writes its top and each object in Python's order, but the events inside it
  (`state`) with their keys sorted: the Rust reader's events are sorted maps, Python's keep
  the order the reader built them in. The JSON is the same; only the order of keys differs.
  `/events` is the same byte for byte (Python sorts its keys there).
- An answer has no `Server` and `Date` headers; a method other than GET gets 501 with a line
  of plain text, not Python's HTML page.
- `.parts.json` is written as Python's `json.dumps` writes it (`", "`, `": "`, ASCII only),
  but with its keys sorted, where Python keeps the order it read them in; both tools read
  either. The slot files are the same byte for byte.
- A write waits for another writer's lock 10 s at most (Python: without a limit), and Ctrl-C
  ends the wait; then it fails and writes nothing. In `watch --addons` that ends `watch`, as a
  failed write ends the Python one.
- A `.parts.json` that cannot be read (not JSON, a number beyond 64 bits, not an object) is
  refused and nothing is written; Python reads the slots then as old ones, and drops the parts
  it cannot carry over. A missing one is an old slot in both.
- An assist set whose `session`, `seq` or `re` is written `-0` is refused (JSON's parser takes
  it for a float); Python takes it for 0.
- `assist`: a set that cannot be written ends the program with the reason (Python drops an
  OSError of the write and tries the stream again). A `--log` line has its keys sorted
  (Python: in the order of the set). The card's local time comes from `chrono` (std has no
  time zone; #195, step 3a).
- Step 3b, every command: an error is one line, `hellolink: <why>`, and exit 1. Python's
  argparse errors exit 2 with a usage line; its JSON and file errors have other words
  (`Expecting value: ...`); a slot that is a file, or a `.parts.json` that is not an object,
  gives a Python traceback. A number beyond 64 bits (`--strip-session`) is refused; Python
  takes it.
- `install-reader` installs this program, not the Python files. Python refuses a working tree
  that differs from the commit; this one installs from the commit itself, so a change not
  committed does not stop it. A `--to` resolved as Python's `resolve()`; an option where a
  value goes (`--to --checkout`, `--to -h`, `--to --7`) is refused, as argparse does (`-`,
  `-7` and `-.5` are values). `install` onto its own source
  (a `HelloLink` link to the checkout) is refused (Python: shutil's same-file error). `package` writes other zip bytes than Python's zlib (so its first SHA-256
  line differs); the entries, their times, modes, CRCs and bytes are the same.
- A request's whole head has the 10 s limit (Python: each read); the first `Host` counts, as in
  Python.

### Every wait and its limit

A wait on another process always has a limit (`LESSONS.md`; #38). The limits are Python's,
with more that Python does not have (marked):

| Wait | Limit |
|---|---|
| a capture's first frame (`one_frame`, and a stream before its first frame) | `ONE_FRAME_WAIT`, 15 s |
| the list of the displays (`tool list`) | 15 s, then killed |
| a capture process told to stop (SIGTERM) | `STOP_WAIT`, 2 s, then SIGKILL to its process group |
| a capture whose output ended, to leave by itself | `STOP_WAIT`, 2 s, then stopped: a failure |
| a stream's idle turn | 0.5 s |
| `kill` itself (it sends SIGTERM and the group's SIGKILL) | 2 s, then killed |
| the reap of a process after SIGKILL (Python: none) | 2 s |
| a process's pipes and reader threads, after it ended (Python: none for stderr) | 2 s; then its process group is killed, and 2 s more |
| `swiftc` building the capture tool (Python: none) | 300 s, then killed |
| one `screencapture` of the fall-back (Python: none) | 15 s, then killed, its files deleted unread, and said |
| a sleep, a wait for a frame, a list, an image, room in the output's queue | Ctrl-C ends it |
| the output's writer thread, at the end | 2 s, then left |

Every process the reader starts runs in a process group of its own (`Command::process_group`,
safe std). The group is named after a keeper, `sleep 60`, started first and held unreaped
(alive, then a zombie) until after the group's last signal: an id cannot be another's before
it is reaped, so no signal reaches a recycled group (std's `try_wait` reaps the capture
itself, which is why the group is not named after it). A child the capture leaves behind is
stopped with the group, so a pipe that child keeps open ends, and no reader thread is left
blocked. A blocking read cannot be cancelled in safe Rust: a child that left the group and
keeps a pipe open leaves its reader thread (it ends when that child does), and the capture is
then a failure that says so ("a child of it kept its output open from outside its process
group"). A pipe's drain stops at its deadline, also when a child writes without end, and keeps
its first 64 KiB.

The process group also keeps Ctrl-C from the terminal away from the captures: the reader
catches it (`signal-hook`, the crate's one dependency for it: catching a signal needs unsafe
code, which this crate forbids), stops its capture, deletes the fall-back's files and ends
with exit 0, as Python's KeyboardInterrupt does. Its output goes through a writer thread and a
queue of 256 lines, so a program that stops reading the output does not keep Ctrl-C waiting.
Ctrl-C while the capture tool is built ends `watch`; it does not start the fall-back.

When the reader leaves a stream (a new search, the first frame's limit, Ctrl-C), it closes it:
a capture that failed by itself meanwhile (its own exit code, not SIGTERM or SIGKILL) is a
failure of the stream, with its reason, and the stream is tried again after a pause. Python's
`stream.close()` drops that result (closing a generator runs its `finally` but not what
follows); the Rust reader reports it (review of #198). A capture is stopped before its pipe is
closed, so that it does not fail on a broken pipe first.

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
bytes. `tests/watch_parity.py` made them; step 3c deleted it, and the files stay as they are.

`hellolink/tests/floats.txt` holds 6000 floats as Python's `repr()` writes them (ties, the
largest and smallest exponents, Unix times, the fixtures' values, random ones with a fixed
seed); `tests/floats.rs` must write each the same. `tests/floats.py` made them; step 3c deleted it.

`hellolink/tests/stream/` holds scripts for the fake capture tool, with what
`hellolink_strip.py watch` wrote on each (stdout, stderr, the tool's runs, the record with its
clock times masked, the remembered place); `hellolink/tests/processes/stream_parity.rs` runs
`hellolink watch` on them and must write the same bytes. `tests/stream_parity.sh` made them;
step 3c deleted it, with `tests/parity.sh` (the two readers compared on many more cells files).
One line more on stderr: since 21 Nov 2026 `watch` writes first `started <local time with its offset>,
hellolink <build>` (the commit that `VERSION` beside the program names, else `built from
<digest>`), so a log kept across restarts (JevCompanion appends one) reads run by run. The
parity test checks that line's form and compares the rest.

The width fit sums complex numbers as Python 3.14 does (with Neumaier's compensation). Python
3.12 and 3.13 sum them plainly, so a fitted width can differ in its last bits there.

## Replay with rust-anything (step 3b)

The replay of step 3b ran the Python `tools/hellolink.py` against this program (295 cases,
every difference listed above); its cases (`reader/replay/`) went with the Python in step 3c.

## The Python checks in Rust

#195 step 3c deleted the Python tests. The lists and tables below say which Rust test holds
each of their checks.

Each check of the Python tests below is an assert whose message is the check's name, word for
word (with the values a Python name prints, a message says them too): in
`hellolink/tests/watch.rs` and `record.rs` (the Watcher, the record's lines), and in the test
program `hellolink/tests/processes/`: `capture.rs` (the capture processes, with real processes
and the real limits) and `follow.rs` (`watch` with a world the test gives). The tests that wait
are in that one program, so that cargo runs them at the same time; `tests/run_all.sh` gives it 32
test threads (most of its tests wait, using little processor), so it takes about 12 s, its
slowest test. `[profile.test]` builds the tests with `opt-level = 1`:
unoptimised, the fall-back checks read 500 noisy display images and took 47 s. The slot
writer's checks are in `slots.rs`, the API's in `api.rs`, both in that program.

`tests/strip1_test.py` (in `hellolink/tests/strip1.rs`, under 0.5 s). The other checks of that
file are in `vectors.rs` without messages: the spec's examples, the frame written by hand, the
objects that come back, the committed vectors and images, and the palette's cache (a unit test
in `strip1.rs`). A message with `%d` or `%.4g` says the depth, the square, the scale or the
pixels beyond, as the Python name does.

| Python check | Rust test |
|---|---|
| section 5: the fast block is 58 bytes | `the_fast_block` |
| every field of every group comes back | `the_fast_block` |
| an unknown group comes back as unknown, not as zeros | `the_fast_block` |
| a number too large for its field is the field's largest value | `the_fast_block` |
| bytes a later version adds at the end are skipped | `the_fast_block` |
| a fast block shorter than version 1's is refused | `the_fast_block` |
| section 3: a frame with no chunk is 73 bytes, 195 squares at depth 2 and 98 at depth 4 | `the_frame` |
| squares back to bytes drop the filling of the last square | `the_frame` |
| a frame with a chunk comes back: session, seq (wrapped), dwell, fast block, chunk | `the_frame` |
| a frame with no object comes back with no chunk | `the_frame` |
| frame_length asks for more until it knows | `the_frame` |
| a changed byte fails the frame check | `the_frame` |
| an unknown version is refused | `the_frame` |
| a frame cut short is refused | `the_frame` |
| a chunk of 0 bytes, 13 chunks or 256 bytes cannot be packed | `the_frame` |
| object id 0 with another object field set is refused | `the_frame` |
| a changed byte fails the object check | `objects` |
| an object of more than 12 chunks is sent as format 254 | `objects` |
| an object that is not UTF-8 is refused as a ValueError | `objects` (an `Err`) |
| chunks in order make the object | `joining_chunks` |
| the same chunk seen several times is ignored | `joining_chunks` |
| a gap drops the partial object | `joining_chunks` |
| chunks out of order make nothing | `joining_chunks` |
| chunks of two versions never mix | `joining_chunks` |
| a frame with no object in between drops the partial | `joining_chunks` |
| a chunk that comes later than 5 x dwell after the last one does not join | `joining_chunks` |
| a later frame's longer dwell does not stretch the limit set when the last chunk was accepted | `joining_chunks` |
| a version seen whole again is not reported twice, but its time is renewed | `joining_chunks` |
| a new version is reported | `joining_chunks` |
| a new session forgets what was held and starts again | `joining_chunks` (the assembler's session is private: the old partial is not finished by the new session's chunks, and the same version is new again) |
| depth %d, %d pixels a square: the frame, the session and the level squares come back | `rows_in_images` |
| the row is found away from the corner, and its box is reported | `rows_in_images` |
| at depth 4 the nearest two palette colours are reported: 85 apart on a clean image | `rows_in_images` |
| depth 4 reads through the blue-into-green leak, by the palette | `rows_in_images` |
| a full level reads 100 and an empty one 0 | `rows_in_images` |
| depth %d at a scale of %.4g: the longest frame comes back | `the_longest_frame_at_every_scale` |
| depth %d: every scale from 1.00 to 2.95 in steps of 0.13 reads the longest frame | `the_longest_frame_at_every_scale` |
| depth %d at 1.0015: a chunk of one repeated letter, whose squares differ less than two-level digits show | `hard_rows_at_1_0015` |
| depth %d at 1.0015 on a display that darkens the levels (the nearest colours 16 apart): still read | `hard_rows_at_1_0015` |
| depth %d at 1.0015, %d pixels beyond: a frame of long black stretches (only the clock known) and a repeated letter | `hard_rows_at_1_0015` |
| depth %d at %.4g: a short row with 2200 pixels of the game beyond its end is read | `hard_rows_at_1_0015` |
| depth %d with squares of 1.8 pixels: refused too, though a short frame could be guessed | `squares_under_2_pixels` |
| depth %d with squares of 1.5 pixels: refused with the reason, not misread | `squares_under_2_pixels` |
| when six bits cannot be read, the session and the levels still can, and the reason is given | `rows_that_are_not_read` |
| a row cut off by the image's edge is not read, and nothing breaks | `rows_that_are_not_read` |
| a frame whose session is not the row's is refused | `rows_that_are_not_read` |
| an image without a row gives nothing | `rows_that_are_not_read` |
| a palette whose colours came back too close asks for depth 2 at once | `rows_that_are_not_read` |
| frames that pass never ask | `the_fall_back_thresholds` |
| more than 2 failed frames in 100, over the last 200, asks | `the_fall_back_thresholds` |
| 1 failed frame in 100 does not | `the_fall_back_thresholds` |
| a reader that never read a depth-4 frame asks after 200 frames, not before | `the_fall_back_thresholds` |
| a row at depth 2 never asks | `the_fall_back_thresholds` |

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
| the request is written to every slot as the strip field of the spec | `slots.rs`: `the_request_in_the_slots` |
| a later write of a text keeps the request: the addon may not have looked yet | `slots.rs`: `the_request_in_the_slots` |
| a request for another session replaces it | `slots.rs`: `the_request_in_the_slots` |
| with no request there is no strip field | `slots.rs`: `the_request_in_the_slots` |
| a quiet write prints nothing (the reader's own output stays clean JSON) | `slots::write` prints nothing; only `hellolink write` says what it wrote (`slots.rs`: `the_assist_part`) |
| one_frame takes the first frame and stops the process, though it would run on | `one_frame_takes_the_first_frame` |
| stream_frames gives the frames, and None when none came for a while | `stream_frames_gives_frames_and_idle_turns` |
| a capture process that fails is an error with its reason, not an empty stream | `failures_of_the_capture_process` |
| a capture tool that is not there is reported, for the fall-back to take over | `failures_of_the_capture_process` |
| one_frame says why a capture failed, instead of 'no frame' | `failures_of_the_capture_process` |
| one_frame gives None for a capture that ended cleanly with nothing | `failures_of_the_capture_process` |
| output that is not a frame from a process that runs on: stopped at once and reported, not waited for | `output_that_is_not_a_frame_from_a_process_that_runs_on` |
| a command that cannot be started is a failed capture too | `failures_of_the_capture_process` |
| output that is not frames is a failed capture, not a silent end | `failures_of_the_capture_process` |
| leaving a stream early stops its process and its reader thread, though the queue was full | `leaving_a_stream_early` |
| the slot writer does not take words in a text for a request | `slots.rs`: `the_request_in_the_slots` |
| so a text that looks like a request leaves none behind | `slots.rs`: `the_request_in_the_slots` |
| sixteen writers at once, one of them a request: the request is still there after all of them | `slots.rs`: `the_request_in_the_slots` |
| a capture that gives no frame is a failure after 3 s, not waited for | `a_capture_that_gives_no_frame` |
| ... and it was asked to stop, not killed | `a_capture_that_gives_no_frame` |
| a capture that gives no frame and does not listen is killed two seconds later | `a_capture_that_does_not_listen` |
| a capture that fails by itself after it was told to stop is still a failure, with its reason | `a_capture_that_fails_after_it_was_told_to_stop` |
| a capture whose output ends before it leaves is waited for: no frame, no failure, no signal | `a_capture_whose_output_ends_before_it_leaves` |
| a capture that gave its frame is asked to stop, not killed | `a_capture_that_gave_its_frame` |
| a stream gives its frame, after an idle turn | `a_stream_whose_reader_leaves_early` |
| a stream whose reader leaves early is asked to stop, not killed | `a_stream_whose_reader_leaves_early` |
| a stream whose output ends before it leaves ends cleanly | `a_capture_whose_output_ends_before_it_leaves` |
| a capture whose output ends but which stays and does not listen is a failure, not a clean end | `a_capture_whose_output_ends_but_which_stays` |
| ... and the same for a stream | `a_stream_whose_output_ends_but_which_stays` |

`tests/strip_api_test.py` (in `api.rs`, `follow.rs` and `cli.rs`):

| Python check | Rust test |
|---|---|
| its 30 checks of the server: `/state`, `/events`, the snapshot, the objects, the conditions, a new session, a foreign Host, 404, POST, no CORS header, a client that does not read, close, a client that sends nothing | `api.rs`: `the_checks_of_the_python_api_test` (the first, "listens on 127.0.0.1 only", is `Api::start` binding 127.0.0.1; and another port in Host is refused too) |
| `watch --serve 8787` starts the API on that port | `cli.rs`: `watch_serves_the_api_and_asks_through_the_slots` |
| ... tells it every event it prints; the first is the `waiting` said at the start (#80) | `follow.rs`: `every_event_printed_is_told` |
| ... and closes it when the reader ends | `watch_serves_the_api_and_asks_through_the_slots` (the port is free after Ctrl-C) |
| a start-up message that cannot be written still closes the API | the API is closed when it is dropped, whatever ends `watch` |

`api.rs`: `the_same_answers_as_the_python_server` gives the Rust API the events that
`tools/strip_api.py` answered before step 3c deleted it; its answers are kept in
`hellolink/tests/api/`: `/events` the same bytes, `/state` the same bytes but for the age (the
events given with sorted keys, as the Rust reader makes them), 404 and 403 the same.

`tests/hellolink_assist_test.py`, sections 2 and 3 (in `slots.rs`): `the_assist_part`, each
check of the writer word for word (`install` is step 3; the slots are made as it makes them).
Section 1, the vector, and section 4, the encoder: `the_slot_file_as_written_out_by_hand`
(bytes written out by hand, `tests/vectors/assist_inbox.lua`, and `tests/vectors/hard.lua`,
which `tests/hellolink_assist_test.lua` reads back in Lua byte for byte).
`the_same_slot_files_as_the_python_tool` gives `hellolink write` the eight writes (a text, a
set of cards, a hard text, a request, odd cards, stdin, an empty set, a new request) that
`tools/hellolink.py write` made before step 3c; its slot files are kept in
`hellolink/tests/slots/`: the same bytes, the clock's numbers taken out. (The check of the two
tools in turn on one folder went with the Python tool.)

`tests/install_reader_test.py` (in `tests/install.rs`, a test program of its own): `the_reader_installs_outside_any_checkout`
(the files and VERSION; a second install keeps the first beside it, whole),
`the_default_checkout_is_the_one_built_from`,
`an_install_from_another_checkout_takes_the_commits_files` (the commit's capture source, not
the working tree's, as a new file), `the_reader_install_refuses_and_changes_nothing` (a
program built from another commit, a commit without its lock file, its build script or the
capture source, a copied program built from something else, a file that comes into the
folder during the install, a folder put in place of the install, a lock file that cannot be
opened, a kept install's name and another case of it, a reader that holds the lock, `--to
--checkout`, `--to -h` and `--to --7`, `missing/../notes`, a link that leads nowhere, and
folders that are not a whole install, a Python install among them; and what is no reader: an
upgrade by the installed program itself, one from a shell in the folder),
`an_installed_reader_does_not_start_while_an_install_holds_the_lock`,
`the_capture_tool_is_built_once_for_each_source` (a stand-in compiler). Step 3c took out the
checks of the Python install and of the process scan (`ps`, `lsof`): the lock replaced the
scan. The slots: `the_slot_install_is_the_python_install` (the
files, bytes and modes `tools/hellolink.py install` made over an earlier install, written into
the test before step 3c deleted it),
`the_slot_counts_the_install_refuses`, `a_slot_install_onto_its_own_source_changes_nothing`. The release: `the_release_zip_is_the_python_one`,
`check_only_writes_no_zip`, `the_release_checks_fail_as_the_python_ones` (the same messages
for six broken roots), `the_tests_run_before_the_zip_as_in_python`,
`sha256_against_fips_180_vectors`. What `tools/package.py` said is kept in
`hellolink/tests/package/`, the version as `{V}`; the zip is read by Info-ZIP (`unzip -t`,
`unzip -p`, `zipinfo`) and, for the UTF-8 flag, by a scan of its central directory.

`tests/hellolink_strip_test.py` (in `hellolink/tests/bitmap.rs`): the bitmap's six refusals and
the screenshot fall-back's clean-up (`a_bitmap_refuses_what_is_not_one`,
`a_screenshot_is_handed_on_and_deleted`). Its six depth-probe checks were not ported: the
probe was the spike's measurement of how many colours a square carries, and Rust has no
`probe`; `tests/hellolink_strip_test.lua` still checks that `/hlink probe depth` draws its rows.

`tests/ai_sdlc_review_status_test.py`: `tests/ai_sdlc_review_status_test.sh`, its 11 cases.

`tests/assistant_test.py` (in `assistant.rs`): sections 1 to 7 and the review's checks in
`the_checks_of_the_python_test`, message for message; sections 8 and 9 (the whole program
against a stand-in reader, and the reader gone) in `the_whole_program`.
`the_same_sets_as_the_python_program` gives the Rust Assistant the events and clock that
`tools/assistant.py`'s Assistant had before step 3c (five runs: the test's, odd names, a fight
with no times, a snapshot's objects, a reload) and asks for its set four times a step: the sets
kept in `hellolink/tests/assistant/`, the clock time of "the strip since" masked.

`tests/strip_record_test.py`:

| Python check | Rust test |
|---|---|
| the reader has a Recorder | the build: `hellolink::record::Recorder` |
| the Watcher's events are as without a record | `the_recorder_on_the_watcher_capture_by_capture` |
| a header and one line a capture | `the_recorder_on_the_watcher_capture_by_capture` |
| line %d is whole and right | `the_recorder_on_the_watcher_capture_by_capture` |
| a second run appends to the file with a header of its own | `the_recorder_on_the_watcher_capture_by_capture` |
| watch --record FILE writes a header, every capture of the search, then each capture of the stream | `watch_with_a_record` |
| watch without --record writes no file | `watch_with_a_record` |
| the slow fall-back records the image of a display without the row, then the one with it, once each | `watch_with_a_record` |

`tests/strip_slow_start_test.py`, `strip_capture_late_test.py` (in `capture.rs`):

| Python check | Rust test |
|---|---|
| a first frame after 5 s is taken, not a failure | `a_first_frame_after_5_s` |
| the limit is at least 12 s: the slowest first frame seen under load was 10.1 s | `a_first_frame_after_5_s` (checked when it is built) |
| a capture that gives nothing still fails, at the limit | `a_capture_that_gives_nothing_fails_at_the_limit` |
| a frame that comes after the 3 s limit is not taken: the capture failed | `a_frame_after_the_limit_is_not_taken` |

`tests/strip_stream_back_test.py`:

| Python check | Rust test |
|---|---|
| the stream answers again and is started once | `follow.rs`: `the_stream_answers_again` |
| the ten images of the stream give ten states | `the_stream_answers_again` |
| no screencapture: every state is the stream's, in order | `the_stream_answers_again` |
| before it, `waiting` at the start and once with the stream's failure; then only `state` | `the_stream_answers_again` |
| the list of the displays has a limit of some seconds | `capture.rs`: `a_list_of_the_displays_that_does_not_come` (a real tool that does not answer; the tests' 3 s limit) and `a_list_of_the_displays_after_3_s_is_still_taken` (the search for the row waits the real 15 s) |
| a list that does not come is a failure of the stream | `a_list_of_the_displays_that_does_not_come` |

The review of #198 added checks of its own, each first seen failing on the code before it
(the PR has the messages): in `capture.rs`, `a_child_of_the_capture_that_keeps_stderr_open`,
`a_child_of_the_list_that_keeps_stdout_open`, `a_child_of_the_stream_that_keeps_stdout_open`;
in `cli.rs` (`hellolink watch` as a program), `ctrl_c_stops_the_capture_and_ends_cleanly`,
`a_capture_that_failed_while_the_stream_was_left_is_a_failure`,
`an_option_without_its_value_is_refused`, `watch_help`; in `follow.rs`,
`a_screencapture_that_does_not_end_or_start` and
`a_turn_of_the_fall_back_that_failed_is_said_and_counted_as_a_miss`.

In `follow.rs`:

| Python test: check | Rust test |
|---|---|
| `strip_waiting_test.py`: its 3 checks | `waiting_while_no_display_shows_the_row` |
| `strip_waiting_fallback_test.py`: its 3 checks | `waiting_on_the_slow_fall_back` |
| `strip_stream_again_test.py`: its 7 checks | `a_failed_stream_is_tried_again` |
| `strip_slow_stream_test.py`: its 7 checks | `a_slow_first_frame_of_a_stream` |
| `strip_replayd_hint_test.py`: three failures, an answer, three failures: one note, not two | `the_note_about_replayd_comes_once` |
| `strip_start_test.py`: its 21 checks (13 of them one a bad file) | `the_start_and_the_remembered_place` |
| `strip_fallback_test.py`: its 4 checks | `the_slow_fall_back_follows_the_display_that_shows_the_row` |
| `strip_fallback_missing_test.py`: no file for display 1, the row on display 2: display 2 is the one captured from then on | `the_slow_fall_back_keeps_a_displays_number` |

Where a Python test replaced `time.sleep` to move its clock, the Rust test's sleep moves it;
where the Python fall-back's stand-in had no pause, the Rust test's sleep is none. The Rust
`watch` sleeps 0.2 s between two turns of the fall-back, as Python's `screencapture_frames`
does inside itself; `strip_stream_again_test.py`'s fall-back run therefore has 0.5 s a turn
instead of 0.3 s (over 100 turns in 150 s either way).
