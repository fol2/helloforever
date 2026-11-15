#!/usr/bin/env python3
"""A capture whose first frame is slow is not a failure (#103). Measured 15 Nov 2026 under load:
the first frame came after 4.47, 10.14 and 8.55 s, and the reader gave up after 3 s. A fake
capture program gives its first frame after a set time; a silent one gives none.
Usage: python3 tests/strip_slow_start_test.py"""
import shutil
import struct
import sys
import tempfile
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "tools"))
import hellolink_strip as hs  # noqa: E402

tmp = Path(tempfile.mkdtemp(prefix="hellolink-slow-"))
fake = tmp / "capture.py"
fake.write_text("""import struct, sys, time
time.sleep(float(sys.argv[1]))
if sys.argv[1] != "99":
    sys.stdout.buffer.write(b"HLC1" + struct.pack("<II", 2, 1) + bytes(8))
    sys.stdout.buffer.flush()
""")
fails = checks = 0


def check(name, ok):
    global fails, checks
    checks += 1
    fails += not ok
    print(("PASS " if ok else "FAIL ") + name)


def first(delay):
    t = time.monotonic()
    try:
        frame = hs.one_frame([sys.executable, str(fake), str(delay)])
        return frame, None, time.monotonic() - t
    except hs.CaptureFailed as e:
        return None, str(e), time.monotonic() - t


frame, error, took = first(5)
check("a first frame after 5 s is taken, not a failure (%s, %.1f s)" % (error, took), frame is not None and error is None)
check("the limit is at least 12 s: the slowest first frame seen under load was 10.1 s", hs.ONE_FRAME_WAIT >= 12)
frame, error, took = first(99)
check("a capture that gives nothing still fails, at the limit (%s, %.1f s)" % (error, took),
      frame is None and error is not None and "no frame" in error and took < hs.ONE_FRAME_WAIT + 3)
shutil.rmtree(tmp, ignore_errors=True)
print("== %d checks, %d failed" % (checks, fails))
sys.exit(1 if fails else 0)
