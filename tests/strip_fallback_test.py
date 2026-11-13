#!/usr/bin/env python3
"""The slow fall-back (`screencapture`) follows the row on the display that shows it (#46): the
images of the other displays are not fed to the reader as misses, and after the first find
only that display is captured. `screencapture` itself is replaced by a stand-in that writes
the images. Usage: python3 tests/strip_fallback_test.py"""
import shutil
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "tools"))
import hellolink_strip as hs  # noqa: E402
import strip1 as s1           # noqa: E402

tmp = Path(tempfile.mkdtemp(prefix="hellolink-fallback-"))
STATE = {"clock": {"clock": 1}, "health": {"healthMax": 1158}}
checks = fails = 0


def check(name, cond):
    global checks, fails
    checks += 1
    fails += not cond
    print(("PASS " if cond else "FAIL ") + name)


def display(out, seq=None):
    """A display's image as `screencapture` writes it, 1280 x 200 with noise all over; with
    `seq`, the row is on it."""
    cells = tmp / "cells.txt"
    cells.write_text("")
    if seq is not None:
        colours = s1.row_colours(4711, 4, (0.75, 1.0, None, None), s1.pack_frame(4711, seq, 10, s1.pack_fast(STATE)))
        cells.write_text("".join("%d 0 2 2 %.6f %.6f %.6f\n" % (i * 2, r, g, b) for i, (r, g, b) in enumerate(colours)))
    hs.render(cells, Path(out), 1.0, 0, 0, 1280, 200)


def run(shown, turns, gone_after=None):
    """`turns` images from the fall-back with three displays, the row on display `shown`
    (counted from 1) and gone after `gone_after` captures. Returns the reader's events and
    the display each capture asked for (None: all of them)."""
    asked, events, real = [], [], hs.subprocess.run

    def stand_in(command, **_):
        assert command[0] == "screencapture", command
        one = int(command[command.index("-D") + 1]) if "-D" in command else None
        asked.append(one)
        paths = [p for p in command if p.endswith(".bmp")]
        there = gone_after is None or len(asked) <= gone_after
        for number, path in zip([one] if one else [1, 2, 3], paths):
            display(path, len(asked) if number == shown and there else None)

    hs.subprocess.run = stand_in
    try:
        watcher, frames = s1.Watcher(), hs.screencapture_frames(pause=0)
        for turn in range(turns):
            frame = next(frames)
            events += watcher.feed(frame, turn * 0.3) if frame is not None else watcher.idle(turn * 0.3)
        frames.close()
    finally:
        hs.subprocess.run = real
    return events, asked


events, asked = run(shown=2, turns=6)
kinds = [e["kind"] for e in events]
check("the row on the second of three displays: six images give six states, and no 'no row' for the other displays (got %s)" % kinds,
      kinds == ["state"] * 6)
check("after the first find only the display that shows the row is captured (asked for %s)" % asked,
      asked[0] is None and len(asked) > 1 and set(asked[1:]) == {2})

events, asked = run(shown=3, turns=6, gone_after=3)
check("when the row leaves that display, every display is captured again (asked for %s)" % asked, None in asked[4:])
check("... and the reader is told that the row is gone", "relocate" in [e["kind"] for e in events])

shutil.rmtree(tmp, ignore_errors=True)
print("== %d checks, %d failed" % (checks, fails))
sys.exit(1 if fails else 0)
