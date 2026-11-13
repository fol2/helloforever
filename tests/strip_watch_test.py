#!/usr/bin/env python3
"""The reader that follows the row: the capture stream's framing, the Watcher, and the request
to fall back. The capture itself (tools/strip_capture.swift) needs a screen and is not run here.
Usage: python3 tests/strip_watch_test.py"""
import io
import shutil
import struct
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "tools"))
import hellolink            # noqa: E402
import hellolink_strip as hs  # noqa: E402
import strip1 as s1         # noqa: E402

fails = checks = 0
tmp = Path(tempfile.mkdtemp(prefix="strip-watch-test-"))


def check(name, cond):
    global fails, checks
    checks += 1
    fails += not cond
    print(("PASS " if cond else "FAIL ") + name)


def raises(fn, kind=ValueError):
    try:
        fn()
    except kind:
        return True
    return False


STATE = {"clock": {"clock": 1}, "health": {"healthMax": 1158}}


def capture(session, depth, levels, frame, bend=None):
    """A capture frame of the row's place, as the stream gives it: 2560 x 4, the row from x = 2."""
    cells = s1.row_colours(session, depth, levels, frame)
    lines = ["%d 1 2 2 %.6f %.6f %.6f" % (2 + i * 2, r, g, b) for i, (r, g, b) in enumerate(cells)]
    (tmp / "cells.txt").write_text("\n".join(lines) + "\n")
    hs.render(tmp / "cells.txt", tmp / "shot.bmp", 1.0, 0, 0, 2560, 4)
    bmp = hs.Bitmap((tmp / "shot.bmp").read_bytes())
    raw = bytearray()
    for y in range(bmp.height):
        for x in range(bmp.width):
            r, g, b = bmp.rgb(x, y)
            if bend:
                r, g, b = bend(r, g, b)
            raw += bytes((b, g, r, 255))
    return bytes(raw)


def framed(raw, width=2560, height=4):
    return b"HLC1" + struct.pack("<II", width, height) + raw


# --- the stream's framing ---
one = capture(4711, 4, (0.75, 1.0, None, None), s1.pack_frame(4711, 1, 10, s1.pack_fast(STATE)))
frames = list(hs.frames_from(io.BytesIO(framed(one) + framed(one))))
check("two frames on the pipe are two bitmaps of the size the header gives", len(frames) == 2 and (frames[0].width, frames[0].height) == (2560, 4))
check("a frame cut short by the end of the pipe is dropped", len(list(hs.frames_from(io.BytesIO(framed(one) + framed(one)[:500])))) == 1)
check("bytes that are not a frame are refused", raises(lambda: list(hs.frames_from(io.BytesIO(b"JUNKJUNKJUNKJUNK")))))
check("a frame that claims an absurd size is refused", raises(lambda: list(hs.frames_from(io.BytesIO(b"HLC1" + struct.pack("<II", 10 ** 9, 4))))))
row = s1.read_row(frames[0])
check("a raw frame reads like an image: the session, the levels, the frame", row["session"] == 4711 and row["levels"] == [76, 100, None, None]
      and row["frame"]["fast"]["health"] == {"healthMax": 1158})
check("a raw frame with too few bytes is refused", raises(lambda: hs.Bitmap.from_bgra(2560, 4, one[:-1])))


# --- the Watcher ---
def shot(seq, levels=(0.75, 1.0, None, None), chunk=None, session=4711, depth=4, bend=None, state=STATE):
    frame = s1.pack_frame(session, seq, 10, s1.pack_fast(state), chunk)
    return hs.Bitmap.from_bgra(2560, 4, capture(session, depth, levels, frame, bend))


w = s1.Watcher()
first = w.feed(shot(1), 0.0)
check("the first capture gives the state: session, seq, depth, levels by name, the fast block",
      [e["kind"] for e in first] == ["state"] and first[0]["session"] == 4711 and first[0]["seq"] == 1 and first[0]["depth"] == 4
      and first[0]["levels"] == {"health": 76, "power": 100, "targetHealth": None, "petHealth": None}
      and first[0]["fast"]["health"] == {"healthMax": 1158})
check("the same capture again gives nothing", w.feed(shot(1), 0.02) == [])
moved = w.feed(shot(1, levels=(0.5, 1.0, None, None)), 0.04)
check("level squares that changed with no new seq give a levels event", [e["kind"] for e in moved] == ["levels"] and moved[0]["levels"]["health"] == 50)
check("a new seq gives a state event", [e["kind"] for e in w.feed(shot(2), 0.06)] == ["state"])
check("the place of the row is remembered after a good read", w.hint is not None)
text = '{"map": 1437, "zone": "Wetlands", "sub": ""}'
parts = s1.chunks_of(s1.pack_object(text, False), 20)
events = []
for i, part in enumerate(parts):
    for _ in range(3):  # each chunk is seen three times
        events += w.feed(shot(3 + i, chunk=(3, 500, i, len(parts), part)), 0.1 + i * 0.1)
objects = [e for e in events if e["kind"] == "object"]
check("an object in several chunks, each seen three times, comes out once and whole", objects == [{"kind": "object", "id": 3, "format": 0, "text": text}])

w = s1.Watcher()
w.feed(shot(1), 0.0)
blank = hs.Bitmap.from_bgra(2560, 4, bytes(2560 * 4 * 4))
events = []
for i in range(40):
    events += w.feed(blank, 0.1 + i * 0.02)
check("30 captures with no row say the row is lost, once, and the place is forgotten",
      [e["kind"] for e in events] == ["lost"] and w.hint is None)
check("after that the row is found again by searching", [e["kind"] for e in w.feed(shot(2), 2.0)] == ["state"])
other = w.feed(shot(1, session=4712), 2.1)
check("another session is a new state, even with a seq seen before", [e["kind"] for e in other] == ["state"] and other[0]["session"] == 4712)


# --- asking for the fall-back ---
def crush(r, g, b):
    return (255 if r > 127 else 0, 255 if g > 127 else 0, 255 if b > 127 else 0)


w = s1.Watcher()
events = []
for i in range(5):
    events += w.feed(shot(1 + i, bend=crush), i * 0.02)
asks = [e for e in events if e["kind"] == "ask"]
check("a palette that cannot be told apart asks for depth 2, once, with the session from the two-level squares",
      asks == [{"kind": "ask", "session": 4711}])
events = []
for i in range(5):
    events += w.feed(shot(1 + i, bend=crush, session=4712), 1 + i * 0.02)
check("a new session that is as bad asks again", [e for e in events if e["kind"] == "ask"] == [{"kind": "ask", "session": 4712}])
w = s1.Watcher()
events = []
for i in range(250):
    events += w.feed(shot(1 + i % 3), i * 0.02)
check("250 good captures at depth 4 never ask", not [e for e in events if e["kind"] == "ask"])

# --- the request in the slots ---
addons = tmp / "AddOns"
hellolink.install(addons, 3)
hellolink.write(addons, "", 4711)
slot = (addons / "HelloLink_S002" / "Inbox.lua").read_text()
check("the request is written to every slot as the strip field of the spec", "strip = { session = 4711, depth = 2 }" in slot and slot.startswith("HelloLink_Inbox = { seq = "))
hellolink.write(addons, "hello")
check("a write without a request has no strip field", "strip" not in (addons / "HelloLink_S001" / "Inbox.lua").read_text())

shutil.rmtree(tmp, ignore_errors=True)
print("== %d checks, %d failed" % (checks, fails))
sys.exit(1 if fails else 0)
