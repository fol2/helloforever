#!/usr/bin/env python3
"""A stream whose first frame is slow is waited for (#103, review): before its first frame, a
stream's silence is not "nothing new for 3 s", so the reader does not close it and look again;
it waits up to ONE_FRAME_WAIT, then takes the stream for failed and tries again later.
Usage: python3 tests/strip_slow_stream_test.py"""
import contextlib
import io
import json
import shutil
import sys
import tempfile
import time
from pathlib import Path
from types import SimpleNamespace

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "tools"))
import hellolink_strip as hs  # noqa: E402
import strip1 as s1           # noqa: E402

tmp = Path(tempfile.mkdtemp(prefix="hellolink-slowstream-"))
STATE = {"clock": {"clock": 1}, "health": {"healthMax": 1158}}


def display(seq):
    colours = s1.row_colours(4711, 4, (0.75, 1.0, None, None), s1.pack_frame(4711, seq, 10, s1.pack_fast(STATE)))
    (tmp / "cells.txt").write_text("".join("%d 0 2 2 %.6f %.6f %.6f\n" % (i * 2, r, g, b) for i, (r, g, b) in enumerate(colours)))
    hs.render(tmp / "cells.txt", tmp / "d.bmp", 1.0, 0, 0, 1280, 200)
    return hs.Bitmap((tmp / "d.bmp").read_bytes())


class Enough(Exception):
    pass


def run(silent_for, before=0, jump=False):
    """A stream that is silent for `silent_for` seconds, then gives frames. With `before`, a
    first stream gives that many frames and then fails, so the second one starts with a state
    already known. With `jump`, the silence is one step: the first frame itself comes late."""
    clock, seq, looks, streams = [0.0], [0], [], []

    def locate(_):
        looks.append(clock[0])
        if len(looks) > 3:
            raise Enough
        seq[0] += 1
        return (1, 1280, s1.read_row(display(seq[0]))), None

    def stream_frames(command, idle):
        streams.append(clock[0])
        if len(streams) == 1 and before:
            for _ in range(before):
                seq[0] += 1
                clock[0] += 0.1
                yield display(seq[0])
            raise hs.CaptureFailed("the display went away")
        if jump:
            clock[0] += silent_for
        while clock[0] - streams[-1] < silent_for:
            clock[0] += idle
            yield None
        for _ in range(5):
            seq[0] += 1
            clock[0] += 0.1
            yield display(seq[0])
        raise Enough

    real = hs.capture_tool, hs.locate, hs.stream_frames, time.monotonic, time.sleep
    hs.capture_tool, hs.locate, hs.stream_frames = (lambda _: (Path("tool"), None)), locate, stream_frames
    time.monotonic, time.sleep = (lambda: clock[0]), (lambda s: clock.__setitem__(0, clock[0] + s))
    out = io.StringIO()
    try:
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(io.StringIO()):
            hs.watch(SimpleNamespace(fps=60, json=True, addons=None, capture=None, remember=None))
    except Enough:
        pass
    finally:
        hs.capture_tool, hs.locate, hs.stream_frames, time.monotonic, time.sleep = real
    events = [json.loads(line) for line in out.getvalue().splitlines()]
    return looks, streams, events


fails = checks = 0


def check(name, ok):
    global fails, checks
    checks += 1
    fails += not ok
    print(("PASS " if ok else "FAIL ") + name)


looks, streams, events = run(8)
states = [e for e in events if e["kind"] == "state"]
check("a stream silent for 8 s is kept: one look, one stream (%d looks, %d streams)" % (len(looks), len(streams)),
      len(looks) == 1 and len(streams) == 1)
check("... and its frames give states (%d)" % len(states), len(states) >= 5)
looks, streams, events = run(60)
check("a stream silent for longer than the limit is given up after it, and tried again (streams at %s)"
      % [round(t) for t in streams[:3]],
      len(streams) >= 2 and hs.ONE_FRAME_WAIT <= streams[1] - streams[0] <= hs.ONE_FRAME_WAIT + 5)
check("... with `waiting` and the reason", any(e["kind"] == "waiting" and "does not answer" in (e.get("why") or "") for e in events))
looks, streams, events = run(8, before=3)
kinds = [e["kind"] for e in events]
check("while a new stream is silent, the state known before goes stale (%s)" % sorted(set(kinds)),
      "stale" in kinds and kinds.index("stale") > kinds.index("state"))
check("... and the new stream is still kept, not cut at 3 s (%d streams)" % len(streams), len(streams) == 2)
looks, streams, events = run(hs.ONE_FRAME_WAIT + 1, jump=True)
check("a first frame that comes after the limit is not taken: no state from it, the stream is tried again (%d streams)"
      % len(streams), not [e for e in events if e["kind"] == "state"] and len(streams) >= 2)
shutil.rmtree(tmp, ignore_errors=True)
print("== %d checks, %d failed" % (checks, fails))
sys.exit(1 if fails else 0)
