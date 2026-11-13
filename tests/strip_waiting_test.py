#!/usr/bin/env python3
"""While no display shows the row, `watch` says `waiting`, again once a minute, and never
`relocate` (#52). On 13 Nov 2026 the row was on no display for 35 minutes: the log held one
`waiting` line and 229 `relocate: nothing new for 3 s` lines, the line a row that stands
still gives, and it was read as a row that stood still.
Usage: python3 tests/strip_waiting_test.py"""
import contextlib
import io
import json
import sys
import time
from pathlib import Path
from types import SimpleNamespace

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "tools"))
import hellolink_strip as hs  # noqa: E402

clock = [1000.0]


class Enough(Exception):
    pass


def sleep(seconds):
    clock[0] += seconds
    if clock[0] > 1150:          # 150 s with no row
        raise Enough


real = hs.capture_tool, hs.locate, time.monotonic, time.sleep
hs.capture_tool, hs.locate = (lambda _: (Path("tool"), None)), (lambda _: (None, "no row on any display"))
time.monotonic, time.sleep = (lambda: clock[0]), sleep
out = io.StringIO()
try:
    with contextlib.redirect_stdout(out):
        hs.watch(SimpleNamespace(fps=60, json=True, addons=None, capture=None))
except Enough:
    pass
finally:
    hs.capture_tool, hs.locate, time.monotonic, time.sleep = real
events = [json.loads(line) for line in out.getvalue().splitlines()]
kinds = [e["kind"] for e in events]
failed = 0
for name, ok in (
    ("no row on any display: no `relocate` line (got %d)" % kinds.count("relocate"), "relocate" not in kinds),
    ("`waiting` is said again once a minute: 3 lines in 150 s (got %d)" % kinds.count("waiting"), kinds.count("waiting") == 3),
    ("every `waiting` line says why", all(e.get("why") == "no row on any display" for e in events if e["kind"] == "waiting")),
):
    print(("PASS " if ok else "FAIL ") + name)
    failed += not ok
print("== 3 checks, %d failed" % failed)
sys.exit(1 if failed else 0)
