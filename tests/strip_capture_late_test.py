#!/usr/bin/env python3
"""The capture's time limit holds once it has passed: a frame that comes after it, while the
process is being stopped, is not taken (#38). A file of its own, beside strip_watch_test.py.
Usage: python3 tests/strip_capture_late_test.py"""
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "tools"))
import hellolink_strip as hs  # noqa: E402

LATE = """
import signal, sys, time
signal.signal(signal.SIGTERM, signal.SIG_IGN)
time.sleep(3.4)
sys.stdout.buffer.write(b"HLC1" + (2).to_bytes(4, "little") + (1).to_bytes(4, "little") + bytes(8))
sys.stdout.buffer.flush()
time.sleep(30)
"""

began = time.time()
try:
    got = hs.one_frame([sys.executable, "-c", LATE])
except hs.CaptureFailed as e:
    got = e
ok = isinstance(got, hs.CaptureFailed) and "no frame" in str(got) and time.time() - began < 7
print(("PASS " if ok else "FAIL ") + "a frame that comes after the 3 s limit is not taken: the capture failed")
print("== 1 checks, %d failed" % (not ok))
sys.exit(0 if ok else 1)
