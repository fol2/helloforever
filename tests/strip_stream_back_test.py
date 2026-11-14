#!/usr/bin/env python3
"""After the capture stream failed and answers again, the reader follows the stream: the
states go on, in order, with no other event at the switch (#56, a review finding). And the
look at the stream has a limit: a list of the displays that does not come is a failure of
the stream, not a wait. A file of its own, beside strip_stream_again_test.py.
Usage: python3 tests/strip_stream_back_test.py"""
import contextlib
import io
import json
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from types import SimpleNamespace

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "tools"))
import hellolink_strip as hs  # noqa: E402
import strip1 as s1           # noqa: E402

tmp = Path(tempfile.mkdtemp(prefix="hellolink-back-"))
STATE = {"clock": {"clock": 1}, "health": {"healthMax": 1158}}


def display(seq):
    """A display's image, 1280 x 200 with noise all over, with the row on it."""
    colours = s1.row_colours(4711, 4, (0.75, 1.0, None, None), s1.pack_frame(4711, seq, 10, s1.pack_fast(STATE)))
    (tmp / "cells.txt").write_text("".join("%d 0 2 2 %.6f %.6f %.6f\n" % (i * 2, r, g, b) for i, (r, g, b) in enumerate(colours)))
    hs.render(tmp / "cells.txt", tmp / "d.bmp", 1.0, 0, 0, 1280, 200)
    return hs.Bitmap((tmp / "d.bmp").read_bytes())


class Enough(Exception):
    pass


clock, seq, looks, streams, source = [0.0], [0], [], [], []


def image(by):
    seq[0] += 1
    source.append(by)
    return display(seq[0])


def locate(_):
    looks.append(clock[0])
    if len(looks) == 1:
        raise hs.CaptureFailed("no frame in 3 s")
    return (0, 1280, s1.read_row(image("look"))), None


def screencapture_frames(pause=0.2):
    while True:
        yield image("screencapture")
        clock[0] += 2.0


def stream_frames(command, idle):
    streams.append(command)
    for _ in range(10):
        clock[0] += 0.1
        yield image("stream")
    raise Enough


real = hs.capture_tool, hs.locate, hs.screencapture_frames, hs.stream_frames, time.monotonic
hs.capture_tool, hs.locate, hs.screencapture_frames, hs.stream_frames = (lambda _: (Path("tool"), None)), locate, screencapture_frames, stream_frames
time.monotonic = lambda: clock[0]
out = io.StringIO()
try:
    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(io.StringIO()):
        hs.watch(SimpleNamespace(fps=60, json=True, addons=None, capture=None))
except Enough:
    pass
finally:
    hs.capture_tool, hs.locate, hs.screencapture_frames, hs.stream_frames, time.monotonic = real
events = [json.loads(line) for line in out.getvalue().splitlines()]
kinds = sorted(set(e["kind"] for e in events))
seqs = [e["seq"] for e in events if e["kind"] == "state"]
by_stream = [n for n, by in enumerate(source, 1) if by == "stream"]

# the look at the stream: a list of the displays that does not come
asked = []


def silent(command, **options):
    asked.append(options.get("timeout"))
    if options.get("timeout"):
        raise subprocess.TimeoutExpired(command, options["timeout"])
    return SimpleNamespace(returncode=0, stdout="", stderr="")     # the old code: no limit was asked for


real_run, hs.subprocess.run = hs.subprocess.run, silent
try:
    hs.locate(Path("tool"))
    limit = "no CaptureFailed"
except hs.CaptureFailed as e:
    limit = str(e)
finally:
    hs.subprocess.run = real_run
shutil.rmtree(tmp, ignore_errors=True)

failed = 0
for name, ok in (
    ("the stream answers again and is started once (%d)" % len(streams), len(streams) == 1 and "stream" in streams[0]),
    ("the ten images of the stream give ten states (seq %s)" % by_stream, len(by_stream) == 10 and all(n in seqs for n in by_stream)),
    ("the states of the fall-back came before them, and every state is in order", len(seqs) > 20 and seqs == sorted(set(seqs))),
    ("the switch gives no other event: `state`, after the one `waiting` of the start (got %s)" % kinds,
     kinds == ["state", "waiting"] and [e["kind"] for e in events].count("waiting") == 1 and events[0]["kind"] == "waiting"),
    ("the list of the displays has a limit of some seconds (asked: %s)" % asked, bool(asked) and asked[0] and 0 < asked[0] <= 10),
    ("a list that does not come is a failure of the stream (%s)" % limit, "list" in limit),
):
    print(("PASS " if ok else "FAIL ") + name)
    failed += not ok
print("== 6 checks, %d failed" % failed)
sys.exit(1 if failed else 0)
