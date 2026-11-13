#!/usr/bin/env python3
"""The same as strip_waiting_test.py on the slow fall-back (`screencapture`), which has its
own loop (#52, a review finding): while no display shows the row, `waiting` once a minute and
no `relocate`. A file of its own, beside strip_waiting_test.py.
Usage: python3 tests/strip_waiting_fallback_test.py"""
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

tmp = Path(tempfile.mkdtemp(prefix="hellolink-waiting-"))
(tmp / "cells.txt").write_text("")
hs.render(tmp / "cells.txt", tmp / "blank.bmp", 1.0, 0, 0, 1280, 200)
blank = hs.Bitmap((tmp / "blank.bmp").read_bytes())
shutil.rmtree(tmp, ignore_errors=True)
clock = [1000.0]


def frames(pause=0.2):
    """A display with no row, three images a second, for 150 s; every tenth turn no image."""
    turn = 0
    while clock[0] <= 1150:
        turn += 1
        yield None if turn % 10 == 0 else blank
        clock[0] += 0.3


real = hs.capture_tool, hs.screencapture_frames, time.monotonic
hs.capture_tool, hs.screencapture_frames, time.monotonic = (lambda _: (None, "no tool")), frames, (lambda: clock[0])
out = io.StringIO()
try:
    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(io.StringIO()):
        hs.watch(SimpleNamespace(fps=60, json=True, addons=None, capture=None))
finally:
    hs.capture_tool, hs.screencapture_frames, time.monotonic = real
events = [json.loads(line) for line in out.getvalue().splitlines()]
kinds = [e["kind"] for e in events]
failed = 0
for name, ok in (
    ("the fall-back, no row on the display: no `relocate` line (got %d)" % kinds.count("relocate"), "relocate" not in kinds),
    ("the fall-back: `waiting` once a minute, 3 lines in 150 s (got %d)" % kinds.count("waiting"), kinds.count("waiting") == 3),
    ("the fall-back: every `waiting` line says why", all(e.get("why") == "no row on any display" for e in events if e["kind"] == "waiting")),
):
    print(("PASS " if ok else "FAIL ") + name)
    failed += not ok
print("== 3 checks, %d failed" % failed)
sys.exit(1 if failed else 0)
