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
check("two captures with no row ask for a new search, and 30 say the row is lost; each once",
      [e["kind"] for e in events] == ["relocate", "lost"] and w.hint is None)
check("after that the row is found again by searching", [e["kind"] for e in w.feed(shot(2), 2.0)] == ["state"])
other = w.feed(shot(1, session=4712), 2.1)
check("another session is a new state, even with a seq seen before", [e["kind"] for e in other] == ["state"] and other[0]["session"] == 4712)


# --- what time makes old ---
w = s1.Watcher()
w.feed(shot(1), 0.0)
check("the same seq read again for 3 s gives nothing", [e for i in range(30) for e in w.feed(shot(1), 0.1 * i)] == [])
old = w.feed(shot(1), 3.2) + w.feed(shot(1), 3.4) + w.idle(4.0)
check("after 3 s without a new seq the state is called stale, once, and a new search is asked for",
      [e["kind"] for e in old] == ["stale", "relocate"])
check("a new seq is fresh again, and can go stale again", [e["kind"] for e in w.feed(shot(2), 5.0)] == ["state"]
      and [e["kind"] for e in w.idle(8.5)] == ["stale", "relocate"])
w = s1.Watcher()
w.feed(shot(1), 0.0)
check("with no capture at all (the row moved away, the old place stands still), time alone says stale, once, "
      "and asks for a search every 3 s", [e["kind"] for e in w.idle(1.0) + w.idle(3.5) + w.idle(4.0) + w.idle(9.0)] == ["stale", "relocate", "relocate"])
w = s1.Watcher()
single = (3, 9, 0, 1, s1.pack_object("{}", False))
w.feed(shot(1, chunk=single), 0.0)
late = w.idle(21.0) + w.idle(22.0) + w.idle(30.0)
check("an object not seen whole for three largest rounds (21.6 s at a dwell of 0.1 s) is called stale, once",
      [e for e in late if e["kind"] == "stale-object"] == [{"kind": "stale-object", "id": 3}])

again = w.feed(shot(2, chunk=single), 40.0)
check("seen whole again in the same version, it is called fresh, and can go stale again",
      [e["kind"] for e in again if "object" in e["kind"]] == ["fresh-object"]
      and [e["kind"] for e in w.idle(70.0) if "object" in e["kind"]] == ["stale-object"])

# --- one Watcher for the whole run: a new search does not forget the session ---
w = s1.Watcher()
mismatch = hs.Bitmap.from_bgra(2560, 4, capture(4711, 4, (0.75, 1.0, None, None), s1.pack_frame(4999, 1, 10, s1.pack_fast(STATE))))
events = []
for i in range(205):   # the palette is fine, but no frame is ever right: 200 of them must add up
    events += w.feed(mismatch, i * 0.02)
kinds = [e["kind"] for e in events]
check("frames that keep failing ask for the fall-back after 200, though the row was searched for again on the way",
      kinds.count("ask") == 1 and kinds.count("relocate") == 1 and kinds.index("relocate") < kinds.index("ask"))

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
after = (addons / "HelloLink_S003" / "Inbox.lua").read_text()
check("a later write of a text keeps the request: the addon may not have looked yet",
      "strip = { session = 4711, depth = 2 }" in after and 'text = "hello"' in after)
hellolink.write(addons, "", 4712)
check("a request for another session replaces it", "session = 4712" in (addons / "HelloLink_S001" / "Inbox.lua").read_text()
      and "4711" not in (addons / "HelloLink_S001" / "Inbox.lua").read_text())
fresh = tmp / "Fresh"
hellolink.install(fresh, 2)
hellolink.write(fresh, "hello")
check("with no request there is no strip field", "strip" not in (fresh / "HelloLink_S001" / "Inbox.lua").read_text())
import contextlib  # noqa: E402
quiet = io.StringIO()
with contextlib.redirect_stdout(quiet):
    hellolink.write(fresh, "x", quiet=True)
check("a quiet write prints nothing (the reader's own output stays clean JSON)", quiet.getvalue() == "")

# --- the processes around the capture ---
import time  # noqa: E402
(tmp / "frame.bin").write_bytes(framed(one))
feeder = ("import sys,time;d=open(sys.argv[1],'rb').read();sys.stdout.buffer.write(d);sys.stdout.buffer.flush();"
          "time.sleep(float(sys.argv[2]));sys.stdout.buffer.write(d);sys.stdout.buffer.flush();time.sleep(float(sys.argv[3]))")
start = time.monotonic()
got = hs.one_frame([sys.executable, "-c", feeder, str(tmp / "frame.bin"), "30", "30"])
check("one_frame takes the first frame and stops the process, though it would run on", got is not None and time.monotonic() - start < 5)
seen = list(hs.stream_frames([sys.executable, "-c", feeder, str(tmp / "frame.bin"), "0.7", "0"], 0.3))
check("stream_frames gives the frames, and None when none came for a while",
      [f is not None for f in seen][0] is True and None in seen and sum(f is not None for f in seen) == 2)
check("a capture process that fails is an error with its reason, not an empty stream",
      raises(lambda: list(hs.stream_frames([sys.executable, "-c", "import sys;sys.stderr.write('no display');sys.exit(3)"], 0.3)), OSError))
check("a capture tool that is not there is reported, for the fall-back to take over", hs.capture_tool(str(tmp / "nope"))[0] is None)
failing = [sys.executable, "-c", "import sys;sys.stderr.write('no display');sys.exit(3)"]
check("one_frame says why a capture failed, instead of 'no frame'", raises(lambda: hs.one_frame(failing), hs.CaptureFailed))
check("one_frame gives None for a capture that ended cleanly with nothing", hs.one_frame([sys.executable, "-c", "pass"]) is None)
check("a command that cannot be started is a failed capture too",
      raises(lambda: hs.one_frame([str(tmp / "nope")]), hs.CaptureFailed) and raises(lambda: list(hs.stream_frames([str(tmp / "nope")], 0.1)), hs.CaptureFailed))
check("output that is not frames is a failed capture, not a silent end",
      raises(lambda: list(hs.stream_frames([sys.executable, "-c", "import sys;sys.stdout.write('JUNKJUNKJUNKJUNKJUNK')"], 0.3)), hs.CaptureFailed))
import threading  # noqa: E402
flood = ("import sys;d=open(sys.argv[1],'rb').read()\n"
         "while True: sys.stdout.buffer.write(d); sys.stdout.buffer.flush()")
before = threading.active_count()
stream = hs.stream_frames([sys.executable, "-c", flood, str(tmp / "frame.bin")], 0.3)
first = next(stream)
time.sleep(0.5)            # the queue fills behind the one frame taken
stream.close()
time.sleep(0.3)
check("leaving a stream early stops its process and its reader thread, though the queue was full",
      first is not None and threading.active_count() == before)
check("the slot writer does not take words in a text for a request",
      hellolink.STRIP_ASK.search(hellolink.inbox(1, '", strip = { session = 1, depth = 2 } }')) is None
      and hellolink.STRIP_ASK.search(hellolink.inbox(1, "x", 77)).group(1) == b"77")
hellolink.write(fresh, 'he said ", strip = { session = 1, depth = 2 } }')
hellolink.write(fresh, "next")
check("so a text that looks like a request leaves none behind", "strip" not in (fresh / "HelloLink_S001" / "Inbox.lua").read_text())
import subprocess  # noqa: E402
tool = str(Path(__file__).resolve().parent.parent / "tools" / "hellolink.py")
racers = [subprocess.Popen([sys.executable, tool, "write", str(addons), "text %d" % i] + (["--strip-session", "5000"] if i == 7 else []),
                           stdout=subprocess.DEVNULL) for i in range(16)]
for r in racers:
    r.wait()
hellolink.write(addons, "last")
check("sixteen writers at once, one of them a request: the request is still there after all of them",
      all("session = 5000" in (addons / ("HelloLink_S%03d" % i) / "Inbox.lua").read_text() for i in (1, 2, 3)))

shutil.rmtree(tmp, ignore_errors=True)
print("== %d checks, %d failed" % (checks, fails))
sys.exit(1 if fails else 0)
