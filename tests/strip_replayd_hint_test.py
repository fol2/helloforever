#!/usr/bin/env python3
"""The note about restarting replayd comes once a run (#113, review): a stream that fails three
times, answers, and fails three times again gives one note, not two.
Usage: python3 tests/strip_replayd_hint_test.py"""
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
import strip1 as s1           # noqa: E402

tmp = Path(tempfile.mkdtemp(prefix="hellolink-hint-"))
STATE = {"clock": {"clock": 1}, "health": {"healthMax": 1158}}


def display(seq):
    colours = s1.row_colours(4711, 4, (0.75, 1.0, None, None), s1.pack_frame(4711, seq, 10, s1.pack_fast(STATE)))
    (tmp / "cells.txt").write_text("".join("%d 0 2 2 %.6f %.6f %.6f\n" % (i * 2, r, g, b) for i, (r, g, b) in enumerate(colours)))
    hs.render(tmp / "cells.txt", tmp / "d.bmp", 1.0, 0, 0, 1280, 200)
    return hs.Bitmap((tmp / "d.bmp").read_bytes())


class Enough(Exception):
    pass


clock, streams = [0.0], []


def locate(_):
    return (1, 1280, s1.read_row(display(1))), None


def stream_frames(command, idle):
    streams.append(clock[0])
    n = len(streams)
    if n in (1, 2, 3, 5, 6, 7):
        raise hs.CaptureFailed("no frame in 15 s")
    if n == 4:                       # the stream answers once, between the two series
        clock[0] += 0.1
        yield display(2)
        raise hs.CaptureFailed("the display went away")
    raise Enough
    yield


real = hs.capture_tool, hs.locate, hs.stream_frames, time.monotonic, time.sleep
hs.capture_tool, hs.locate, hs.stream_frames = (lambda _: (Path("tool"), None)), locate, stream_frames
time.monotonic, time.sleep = (lambda: clock[0]), (lambda s: clock.__setitem__(0, clock[0] + s))
err = io.StringIO()
try:
    with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(err):
        hs.watch(SimpleNamespace(fps=60, json=True, addons=None, capture=None, remember=None))
except Enough:
    pass
finally:
    hs.capture_tool, hs.locate, hs.stream_frames, time.monotonic, time.sleep = real
shutil.rmtree(tmp, ignore_errors=True)
count = err.getvalue().count("killall replayd")
ok = len(streams) >= 7 and count == 1
print(("PASS " if ok else "FAIL ") + "three failures, an answer, three failures: one note, not two (%d notes, %d streams)" % (count, len(streams)))
print("== 1 checks, %d failed" % (not ok))
sys.exit(0 if ok else 1)
