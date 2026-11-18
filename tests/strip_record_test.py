#!/usr/bin/env python3
"""The reader's record of a play session (#178): `watch --record FILE` writes one JSON line a
capture, with the frame's bytes when they change, the reason and bytes of a failed read, and
the palette when it moves. Usage: python3 tests/strip_record_test.py"""
import json
import shutil
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "tools"))
sys.path.insert(0, str(Path(__file__).resolve().parent))
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


def shot(frame, levels=(0.75, 1.0, None, None), session=4711, bend=None):
    """A capture of the row, 2560 x 4, as tests/strip_watch_test.py makes one."""
    cells = s1.row_colours(session, 4, levels, frame)
    (tmp / "cells.txt").write_text("".join("%d 1 2 2 %.6f %.6f %.6f\n" % (2 + i * 2, r, g, b) for i, (r, g, b) in enumerate(cells)))
    hs.render(tmp / "cells.txt", tmp / "shot.bmp", 1.0, 0, 0, 2560, 4)
    bmp = hs.Bitmap((tmp / "shot.bmp").read_bytes())
    raw = bytearray()
    for y in range(bmp.height):
        for x in range(bmp.width):
            r, g, b = bmp.rgb(x, y)
            if bend:
                r, g, b = bend(r, g, b)
            raw += bytes((b, g, r, 255))
    return hs.Bitmap.from_bgra(2560, 4, bytes(raw))


one = s1.pack_frame(4711, 1, 10, s1.pack_fast(STATE))
two = s1.pack_frame(4711, 2, 10, s1.pack_fast(STATE))
bad = bytearray(two)
bad[8] ^= 0x01                         # a byte of the fast block read wrong: the check fails
darker = lambda r, g, b: (max(0, r - 6), max(0, g - 6), max(0, b - 6))   # noqa: E731

path = tmp / "play.jsonl"
watcher = s1.Watcher()
record = getattr(hs, "Recorder", None)
check("the reader has a Recorder", record is not None)
if record is None:
    print("== %d checks, %d failed" % (checks, fails))
    sys.exit(1)
rec = record(path, started=1794516378.25)
feed = rec.wrap(watcher)
events = feed(shot(one), 0.0)
feed(shot(one), 0.016)
feed(shot(one, levels=(0.5, 1.0, None, None)), 0.033)
feed(shot(two), 0.05)
feed(shot(two, bend=darker), 0.066)
feed(shot(bytes(bad)), 0.083)
feed(hs.Bitmap.from_bgra(2560, 4, bytes(2560 * 4 * 4)), 0.1)
rec.close()
check("the wrapped feed still gives the Watcher's events", [e["kind"] for e in events] == ["state"])

lines = [json.loads(line) for line in path.read_text().splitlines()]
check("a header and one line a capture", len(lines) == 8, len(lines))
head = lines[0]
check("the header names the record's format and when it started",
      head == {"record": 1, "started": 1794516378.25}, head)
body = lines[1:]
check("every capture has its time from the start, in seconds to the millisecond",
      [b["t"] for b in body] == [0.0, 0.016, 0.033, 0.05, 0.066, 0.083, 0.1], [b["t"] for b in body])
first = body[0]
check("the first good capture gives the frame's bytes, the depth, the levels and the palette",
      first.get("frame") == one.hex() and first.get("depth") == 4 and first.get("levels") == [76, 100, None, None]
      and isinstance(first.get("palette"), list) and len(first["palette"]) == 64 and first["palette"][63] == [255, 255, 255],
      first)
check("the same capture again is the time alone", body[1] == {"t": 0.016}, body[1])
check("level squares that moved give the levels alone", body[2] == {"t": 0.033, "levels": [50, 100, None, None]}, body[2])
check("a new frame gives its bytes and the levels that moved back, without the palette or the depth that did not move",
      body[3] == {"t": 0.05, "frame": two.hex(), "levels": [76, 100, None, None]}, body[3])
check("a palette that moved is written again, the frame not", "palette" in body[4] and "frame" not in body[4]
      and body[4]["palette"][63] == [249, 249, 249], body[4])
check("a frame that fails its check gives the reason and the bytes as read",
      body[5].get("why") == "frame check failed" and body[5].get("bad") == bytes(bad).hex() and "frame" not in body[5], body[5])
check("an image with no row gives the reason alone", body[6] == {"t": 0.1, "why": "no row"}, body[6])

# A record continues the file: two runs, two headers.
rec = record(path, started=1794516400.0)
rec.wrap(s1.Watcher())(shot(one), 0.0)
rec.close()
check("a second run appends to the file with a header of its own",
      [json.loads(line).get("record") for line in path.read_text().splitlines()].count(1) == 2)

shutil.rmtree(tmp, ignore_errors=True)
print("== %d checks, %d failed" % (checks, fails))
sys.exit(1 if fails else 0)
