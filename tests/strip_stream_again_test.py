#!/usr/bin/env python3
"""A reader that fell back to `screencapture` because the capture stream failed tries the
stream again, once a minute (#56). On 13 Nov 2026 the stream gave no frame once, 19 minutes
into a run, and the reader stayed on the slow fall-back for the 3 h 20 min that followed.
A reader with no capture tool never tries a stream.
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
    try:
        with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            hs.watch(SimpleNamespace(fps=60, json=True, addons=None, capture=None))
    except Enough:
        pass
    finally:
        hs.capture_tool, hs.locate, hs.screencapture_frames, time.monotonic, time.sleep = real
    return looks, turns


once, once_turns = run(Path("tool"), lambda n: n > 1, 200)       # the stream fails once
never, never_turns = run(Path("tool"), lambda n: False, 200)     # the stream fails every time
none, none_turns = run(None, lambda n: True, 150)                # no capture tool at all
failed = 0
for name, ok in (
    ("the stream failed once: the reader looks at the stream again (looks at %s)" % [round(t) for t in once[:3]], len(once) > 1),
    ("the second look comes 60 to 70 s after the first", len(once) > 1 and 60 <= once[1] - once[0] <= 70),
    ("until then the reader is on screencapture (%d turns)" % len(once_turns), len(once_turns) > 100),
    ("once the stream answers, no more screencapture", len(once) > 1 and all(t <= once[1] for t in once_turns)),
    ("the stream fails every time: one look a minute, 4 in 200 s (got %d)" % len(never), len(never) == 4),
    ("between the looks the reader is on screencapture (%d turns)" % len(never_turns), len(never_turns) > 500),
    ("no capture tool: no look at a stream (got %d)" % len(none), len(none) == 0 and len(none_turns) > 100),
):
    print(("PASS " if ok else "FAIL ") + name)
    failed += not ok
print("== 7 checks, %d failed" % failed)
sys.exit(1 if failed else 0)
