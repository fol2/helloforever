#!/usr/bin/env python3
"""A capture stream that failed is tried again, after a pause that grows to 30 s, and the
reader never falls back to `screencapture` while it has a capture tool (#103; owner, 15 Nov
2026: "i always wanted streaming not capturing"). Before, it took the fall-back for a minute
at a time (#56). A reader with no capture tool never tries a stream.
Usage: python3 tests/strip_stream_again_test.py"""
import contextlib
import io
import shutil
import sys
import tempfile
import time
from pathlib import Path
from types import SimpleNamespace

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "tools"))
import hellolink_strip as hs  # noqa: E402

tmp = Path(tempfile.mkdtemp(prefix="hellolink-again-"))
(tmp / "cells.txt").write_text("")
hs.render(tmp / "cells.txt", tmp / "blank.bmp", 1.0, 0, 0, 1280, 200)
blank = hs.Bitmap((tmp / "blank.bmp").read_bytes())
shutil.rmtree(tmp, ignore_errors=True)


class Enough(Exception):
    pass


notes = []                       # each run's stderr, in order


def run(tool, answers, seconds):
    """`watch` for `seconds` of a clock that only the stand-ins move. `answers(n)` is what the
    n-th look at the stream does: True, it answers (no row); False, it fails. Returns the
    times of the looks at the stream and of the `screencapture` turns, from the start."""
    clock, looks, turns = [0.0], [], []

    def sleep(s):
        clock[0] += s
        if clock[0] > seconds:
            raise Enough

    def locate(_):
        looks.append(clock[0])
        if not answers(len(looks)):
            raise hs.CaptureFailed("no frame in 3 s")
        return None, "no row on any display"

    def frames(pause=0.2):
        while clock[0] <= seconds:
            turns.append(clock[0])
            yield blank
            clock[0] += 0.3

    real = hs.capture_tool, hs.locate, hs.screencapture_frames, time.monotonic, time.sleep
    hs.capture_tool, hs.locate, hs.screencapture_frames = (lambda _: (tool, tool and None or "no tool")), locate, frames
    time.monotonic, time.sleep = (lambda: clock[0]), sleep
    err = io.StringIO()
    notes.append(err)
    try:
        with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(err):
            hs.watch(SimpleNamespace(fps=60, json=True, addons=None, capture=None))
    except Enough:
        pass
    finally:
        hs.capture_tool, hs.locate, hs.screencapture_frames, time.monotonic, time.sleep = real
    return looks, turns


once, once_turns = run(Path("tool"), lambda n: n > 1, 200)       # the stream fails once
never, never_turns = run(Path("tool"), lambda n: False, 200)     # the stream fails every time
none, none_turns = run(None, lambda n: True, 150)                # no capture tool at all
gaps = [round(b - a) for a, b in zip(never, never[1:])]
hint = "killall replayd"
once_notes, never_notes = notes[0].getvalue(), notes[1].getvalue()
failed = 0
for name, ok in (
    ("the stream failed once: it is tried again after 2 s (looks at %s)" % [round(t) for t in once[:3]],
     len(once) > 1 and 1.5 <= once[1] - once[0] <= 3),
    ("no screencapture while there is a capture tool (%d turns, %d turns)" % (len(once_turns), len(never_turns)),
     not once_turns and not never_turns),
    ("the stream fails every time: the pauses grow 2, 4, 8, 16, then 30 s each (%s)" % gaps,
     gaps[:5] == [2, 4, 8, 16, 30] and all(g == 30 for g in gaps[5:])),
    ("so it is tried again at most each 30 s, never left: %d looks in 200 s" % len(never), len(never) >= 9),
    ("no capture tool: no look at a stream, and screencapture runs (got %d looks)" % len(none), len(none) == 0 and len(none_turns) > 100),
    ("a stream that keeps failing gets one note: restarting replayd helped once (#113; %d notes)" % never_notes.count(hint),
     never_notes.count(hint) == 1),
    ("a stream that failed once gets no such note", hint not in once_notes),
):
    print(("PASS " if ok else "FAIL ") + name)
    failed += not ok
print("== 7 checks, %d failed" % failed)
sys.exit(1 if failed else 0)
