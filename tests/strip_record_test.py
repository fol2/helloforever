#!/usr/bin/env python3
"""The reader's record of a play session (#178): `watch --record FILE` writes one JSON line a
capture, with the frame's bytes when they change, the reason and the bytes of a failed read,
and the depth, levels and palette when they move. Every line is compared whole.
Usage: python3 tests/strip_record_test.py"""
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

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
import hellolink_strip as hs  # noqa: E402
import strip1 as s1         # noqa: E402

fails = checks = 0
tmp = Path(tempfile.mkdtemp(prefix="strip-record-test-"))


def check(name, cond, detail=""):
    global fails, checks
    checks += 1
    fails += not cond
    print(("PASS " if cond else "FAIL ") + name + ("" if cond else " " + str(detail)))


STATE = {"clock": {"clock": 1}, "health": {"healthMax": 1158}}
WIDE = 2560


def shot(frame, levels=(0.75, 1.0, None, None), depth=4, bend=None, width=WIDE):
    """A capture of the row, `width` x 4, as tests/strip_watch_test.py makes one."""
    cells = s1.row_colours(4711, depth, levels, frame)
    (tmp / "cells.txt").write_text("".join("%d 1 2 2 %.6f %.6f %.6f\n" % (2 + i * 2, r, g, b) for i, (r, g, b) in enumerate(cells)))
    hs.render(tmp / "cells.txt", tmp / "shot.bmp", 1.0, 0, 0, WIDE, 4)
    bmp = hs.Bitmap((tmp / "shot.bmp").read_bytes())
    raw = bytearray()
    for y in range(bmp.height):
        for x in range(width):
            r, g, b = bmp.rgb(x, y)
            if bend:
                r, g, b = bend(r, g, b)
            raw += bytes((b, g, r, 255))
    return hs.Bitmap.from_bgra(width, 4, bytes(raw))


def frame(seq):
    return s1.pack_frame(4711, seq, 10, s1.pack_fast(STATE))


def lines(path):
    return [json.loads(line) for line in path.read_text().splitlines()]


PALETTE = [[85 * (i // 16), 85 * (i // 4 % 4), 85 * (i % 4)] for i in range(64)]
DARKER = [[max(0, c - 6) for c in rgb] for rgb in PALETTE]
one, two = frame(1), frame(2)
bad = bytearray(two)
bad[8] ^= 0x01                           # a byte of the fast block read wrong: the check fails

# --- the Recorder on the Watcher, capture by capture ---
path = tmp / "play.jsonl"
watcher = s1.Watcher()
record = getattr(hs, "Recorder", None)
check("the reader has a Recorder", record is not None)
if record is None:
    print("== %d checks, %d failed" % (checks, fails))
    sys.exit(1)
rec = record(path, started=1794516378.25)
watcher.on_row = rec.note
captures = [
    shot(one),
    shot(one),
    shot(one, levels=(0.5, 1.0, None, None)),
    shot(two),
    shot(two, bend=lambda r, g, b: (max(0, r - 6), max(0, g - 6), max(0, b - 6))),
    shot(bytes(bad)),
    shot(bytes(bad), depth=2, levels=(0.25, 1.0, None, None)),
    shot(two, width=300),                # 149 squares: 58 of the frame, 43 bytes
    shot(two, levels=(0.5, 1.0, None, None), width=100),   # the palette cut short
    hs.Bitmap.from_bgra(WIDE, 4, bytes(WIDE * 4 * 4)),
]
events = []
for i, image in enumerate(captures):
    events += watcher.feed(image, 100.0 + i * 0.016)
rec.close()
check("the Watcher's events are as without a record", [e["kind"] for e in events][:3] == ["state", "levels", "state"])
got = lines(path)
want = [
    {"record": 1, "started": 1794516378.25},
    {"t": 0.0, "frame": one.hex(), "depth": 4, "levels": [76, 100, None, None], "palette": PALETTE},
    {"t": 0.016},
    {"t": 0.032, "levels": [50, 100, None, None]},
    {"t": 0.048, "frame": two.hex(), "levels": [76, 100, None, None]},
    {"t": 0.064, "palette": DARKER},
    {"t": 0.08, "why": "frame check failed", "bad": bytes(bad).hex(), "palette": PALETTE},
    {"t": 0.096, "why": "frame check failed", "bad": s1.squares_to_bytes(s1.bytes_to_squares(bytes(bad), 3), 3, len(bad)).hex(),
     "depth": 2, "levels": [25, 100, None, None]},
    {"t": 0.112, "why": "the row runs off the image", "bad": two[:43].hex(), "depth": 4, "levels": [76, 100, None, None]},
    {"t": 0.128, "why": "the row runs off the image", "levels": [50, 100, None, None]},
    {"t": 0.144, "why": "no row"},
]
check("a header and one line a capture", len(got) == len(want), len(got))
for i, (g, w) in enumerate(zip(got, want)):
    check("line %d is whole and right" % i, g == w, "\n got %r\nwant %r" % (g, w))

# A record continues the file: two runs, two headers.
rec = record(path, started=1794516400.0)
w2 = s1.Watcher()
w2.on_row = rec.note
w2.feed(shot(one), 7.0)
rec.close()
check("a second run appends to the file with a header of its own",
      [line.get("record") for line in lines(path)].count(1) == 2)


# --- through the command line: every capture of the search, then each of the stream ---
class Enough(Exception):
    pass


BLANK = hs.Bitmap.from_bgra(WIDE, 4, bytes(WIDE * 4 * 4))


def watch(argv):
    """`hellolink_strip.py <argv>` with the real locate; the capture tool lists one display,
    2560 x 4, and its frames are given here: two looks find nothing, then the row."""
    clock = [5.0]
    looks = iter([BLANK, BLANK, shot(frame(1)), shot(frame(1))])

    def one_frame(command):
        clock[0] += 0.1
        return next(looks)

    def stream_frames(command, idle):
        for seq in (2, 3):
            clock[0] += 0.1
            yield shot(frame(seq))
        raise Enough

    real = (hs.capture_tool, hs.one_frame, hs.stream_frames, hs.subprocess.run, time.monotonic, time.sleep, sys.argv)
    hs.capture_tool, hs.one_frame, hs.stream_frames = (lambda _: (Path("tool"), None)), one_frame, stream_frames
    hs.subprocess.run = lambda *a, **k: SimpleNamespace(returncode=0, stdout="0 %d 4\n" % WIDE, stderr="")
    time.monotonic, time.sleep = (lambda: clock[0]), (lambda s: None)
    sys.argv = ["hellolink_strip.py"] + argv
    try:
        with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            hs.main()
    except Enough:
        pass
    finally:
        hs.capture_tool, hs.one_frame, hs.stream_frames, hs.subprocess.run, time.monotonic, time.sleep, sys.argv = real


played = tmp / "watch.jsonl"
watch(["watch", "--json", "--record", str(played)])
got = lines(played) if played.exists() else []
want = [{"t": 0.0, "why": "no row"}, {"t": 0.1, "why": "no row"},
        {"t": 0.2, "frame": frame(1).hex(), "depth": 4, "levels": [76, 100, None, None], "palette": PALETTE},
        {"t": 0.3, "frame": frame(2).hex()}, {"t": 0.4, "frame": frame(3).hex()}]
check("watch --record FILE writes a header, every capture of the search, then each capture of the stream",
      len(got) == 6 and set(got[0]) == {"record", "started"} and got[1:] == want, got)
before = set(tmp.iterdir())
watch(["watch", "--json"])
check("watch without --record writes no file", set(tmp.iterdir()) == before)

shutil.rmtree(tmp, ignore_errors=True)
print("== %d checks, %d failed" % (checks, fails))
sys.exit(1 if fails else 0)
