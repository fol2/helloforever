#!/usr/bin/env python3
"""The slow fall-back keeps a display's number when `screencapture` writes no file for an
earlier display (#46, a review finding). A file of its own, beside strip_fallback_test.py.
Usage: python3 tests/strip_fallback_missing_test.py"""
import shutil
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "tools"))
import hellolink_strip as hs  # noqa: E402
import strip1 as s1           # noqa: E402

tmp = Path(tempfile.mkdtemp(prefix="hellolink-fallback-"))
asked, real = [], hs.subprocess.run


def stand_in(command, **_):
    """Two displays; no file comes for the first, the row is on the second."""
    one = int(command[command.index("-D") + 1]) if "-D" in command else None
    asked.append(one)
    paths = [p for p in command if p.endswith(".bmp")]
    for number, path in zip([one] if one else [1, 2], paths):
        if number != 2:
            continue
        frame = s1.pack_frame(4711, len(asked), 10, s1.pack_fast({"clock": {"clock": 1}}))
        colours = s1.row_colours(4711, 4, (0.75, 1.0, None, None), frame)
        (tmp / "cells.txt").write_text("".join("%d 0 2 2 %.6f %.6f %.6f\n" % (i * 2, r, g, b) for i, (r, g, b) in enumerate(colours)))
        hs.render(tmp / "cells.txt", Path(path), 1.0, 0, 0, 1280, 200)


hs.subprocess.run = stand_in
try:
    watcher, frames, kinds = s1.Watcher(), hs.screencapture_frames(pause=0), []
    for turn in range(6):
        frame = next(frames)
        kinds += [e["kind"] for e in (watcher.feed(frame, turn * 0.3) if frame is not None else watcher.idle(turn * 0.3))]
    frames.close()
finally:
    hs.subprocess.run = real
    shutil.rmtree(tmp, ignore_errors=True)
ok = kinds == ["state"] * 6 and asked == [None, 2, 2, 2, 2, 2]
print(("PASS " if ok else "FAIL ") + "no file for display 1, the row on display 2: display 2 is the one captured from then on "
      "(asked for %s, got %s)" % (asked, kinds))
print("== 1 checks, %d failed" % (not ok))
sys.exit(0 if ok else 1)
