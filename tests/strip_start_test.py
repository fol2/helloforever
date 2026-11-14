#!/usr/bin/env python3
"""The reader's start (#80): it says `waiting` at once, and with `--remember <file>` it tries
the place where the row was at the last run before it looks at every display.
Usage: python3 tests/strip_start_test.py"""
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

tmp = Path(tempfile.mkdtemp(prefix="hellolink-start-"))
STATE = {"clock": {"clock": 1}, "health": {"healthMax": 1158}}


def display(seq, row=True):
    """A display's image, 1280 x 200 with noise all over, with the row on it or without."""
    colours = s1.row_colours(4711, 4, (0.75, 1.0, None, None), s1.pack_frame(4711, seq, 10, s1.pack_fast(STATE)))
    cells = "".join("%d 0 2 2 %.6f %.6f %.6f\n" % (i * 2, r, g, b) for i, (r, g, b) in enumerate(colours)) if row else ""
    (tmp / "cells.txt").write_text(cells)
    hs.render(tmp / "cells.txt", tmp / "d.bmp", 1.0, 0, 0, 1280, 200)
    return hs.Bitmap((tmp / "d.bmp").read_bytes())


class Enough(Exception):
    pass


def run(remember, stream_of, locate_gives=True):
    """One run of the reader with a fake capture. `stream_of(n, command)` gives the frames of
    the n-th stream (or raises). Returns the events, the looks, the stream commands and the
    order in which things happened."""
    clock, seq, order, looks, streams = [0.0], [0], [], [], []

    def frame(row=True):
        seq[0] += 1
        clock[0] += 0.1
        return display(seq[0], row)

    def locate(_):
        looks.append(clock[0])
        order.append("look")
        if len(looks) > 3:
            raise Enough
        return ((1, 1280, s1.read_row(frame())), None) if locate_gives else (None, "no row on any display")

    def stream_frames(command, idle):
        streams.append([str(c) for c in command])
        order.append("stream")
        yield from stream_of(len(streams), frame)
        raise Enough

    def screencapture_frames(pause=0.2):
        order.append("fall-back")
        raise Enough
        yield

    def capture_tool(_):
        order.append("tool")
        return Path("tool"), None

    class Out(io.StringIO):
        """The reader's output; the first `waiting` goes into `order` at the moment it is written."""
        def write(self, text):
            if '"waiting"' in text and "wait" not in order:
                order.append("wait")
            return super().write(text)

    real = hs.capture_tool, hs.locate, hs.screencapture_frames, hs.stream_frames, time.monotonic, time.sleep
    hs.capture_tool, hs.locate, hs.screencapture_frames, hs.stream_frames = capture_tool, locate, screencapture_frames, stream_frames
    time.monotonic, time.sleep = (lambda: clock[0]), (lambda s: clock.__setitem__(0, clock[0] + s))
    out = Out()
    try:
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(io.StringIO()):
            hs.watch(SimpleNamespace(fps=60, json=True, addons=None, capture=None, remember=remember))
    except Enough:
        pass
    finally:
        hs.capture_tool, hs.locate, hs.screencapture_frames, hs.stream_frames, time.monotonic, time.sleep = real
    return [json.loads(line) for line in out.getvalue().splitlines()], looks, streams, order


def ten(n, frame):
    for _ in range(10):
        yield frame()


def no_row(n, frame):
    if n == 1:
        for _ in range(60):
            yield frame(row=False)
    else:
        yield from ten(n, frame)


def fails(n, frame):
    if n == 1:
        raise hs.CaptureFailed("no frame in 3 s")
    yield from ten(n, frame)


checks = []
place = tmp / "place.json"

# 1. no remembered place: `waiting` first, then a look, and the place is written
events, looks, streams, order = run(str(place), ten)
checks.append(("the first event is `waiting`, with a reason, before any display is looked at (%s)" % events[:1],
               bool(events) and events[0] == {"kind": "waiting", "why": "looking for the row"} and len(looks) == 1))
checks.append(("it is written before the capture tool is asked for and before any look (%s)" % order[:4], order[:3] == ["wait", "tool", "look"]))
checks.append(("the states follow it", [e["kind"] for e in events[1:]].count("state") >= 10))
written = json.loads(place.read_text()) if place.exists() else None
checks.append(("the place that was found is written: five whole numbers (%s)" % written,
               isinstance(written, dict) and sorted(written) == ["display", "left", "lines", "top", "width"]
               and all(isinstance(v, int) for v in written.values()) and written["display"] == 1))
checks.append(("the stream was started on that rectangle",
               len(streams) == 1 and written is not None
               and streams[0][1:7] == ["stream", "1", str(written["left"]), str(written["top"]), str(written["width"]), str(written["lines"])]))

# 2. with the remembered place: the stream starts there and no display is looked at
events, looks, streams, order = run(str(place), ten)
checks.append(("with a remembered place no display is looked at (%d looks) and the stream starts on it" % len(looks),
               looks == [] and len(streams) == 1 and written is not None and streams[0][2:7] == [str(written[k]) for k in ("display", "left", "top", "width", "lines")]))
checks.append(("and the states come", [e["kind"] for e in events].count("state") >= 10 and events[0]["kind"] == "waiting"))

# 3. the remembered place shows no row: the reader looks again
events, looks, streams, order = run(str(place), no_row)
checks.append(("a remembered place that shows no row is followed by a look at the displays (%s)" % order[:5],
               len(looks) >= 1 and len(streams) >= 2 and "fall-back" not in order))

# 4. the remembered place's stream fails: a look, not the fall-back
events, looks, streams, order = run(str(place), fails)
checks.append(("a remembered place whose stream fails is followed by a look, not by the fall-back (%s)" % order[:5],
               len(looks) == 1 and "fall-back" not in order and len(streams) == 2))

# 5. a file that is no place is ignored
for bad in ("", "{", "[1, 2, 3, 4, 5]", '{"display": 1}', '{"display": -1, "left": 0, "top": 0, "width": 100, "lines": 4}',
            '{"display": 1, "left": 0, "top": 0, "width": 0, "lines": 4}', '{"display": 1.5, "left": 0, "top": 0, "width": 100, "lines": 4}',
            '{"display": 1, "left": 0, "top": 0, "width": 99999999, "lines": 4}', '{"display": 1, "left": 0, "top": 0, "width": 100, "lines": 4, "extra": 6}', "null", '"text"', "5",
            '{"display": true, "left": 0, "top": 0, "width": 100, "lines": 4}'):
    place.write_text(bad)
    events, looks, streams, order = run(str(place), ten)
    checks.append(("a file that is no place is ignored, and the reader looks (%r)" % bad[-28:], len(looks) == 1 and len(streams) == 1))

# 6. without --remember nothing is read or written
place.unlink()
events, looks, streams, order = run(None, ten)
checks.append(("without --remember the reader looks, and writes no file", len(looks) == 1 and not place.exists()))

shutil.rmtree(tmp, ignore_errors=True)
failed = 0
for name, ok in checks:
    print(("PASS " if ok else "FAIL ") + name)
    failed += not ok
print("== %d checks, %d failed" % (len(checks), failed))
sys.exit(1 if failed else 0)
