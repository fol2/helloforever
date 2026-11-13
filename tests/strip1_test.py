#!/usr/bin/env python3
"""The live-state strip, format 1: tools/strip1.py against docs/specs/29.md.
Usage: python3 tests/strip1_test.py"""
import shutil
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "tools"))
import hellolink_strip as hs  # noqa: E402  (the bitmap and the renderer)
import strip1 as s1           # noqa: E402

fails = checks = 0
tmp = Path(tempfile.mkdtemp(prefix="strip1-test-"))


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


STATE = {
    "clock": {"clock": 54321}, "health": {"healthMax": 1158}, "power": {"powerMax": 1335, "powerType": 0},
    "level": {"level": 29, "xp": 2004, "xpMax": 64000}, "state": {"flags": 128 + 4 + 2 + 1 + 256},
    "cast": {"spell": 19434, "tenths": 17}, "target": {"level": 23, "flags": 128 + 1, "nameHash": 0xF0C8},
    "pet": {"healthMax": 1355}, "position": {"map": 1437, "x": 32768, "y": 16384, "facing": 64},
    "purse": {"money": 7800, "bagFree": 12}, "hand": {"item": 2504, "enchant": 599},
    "loot": {"counter": 255, "item": 2318, "quantity": 2}, "uiError": {"error": 50, "counter": 3},
    "threat": {"player": 58, "pet": 100},
}

# --- the vectors of the spec ---
check("section 7: the check of 'abcde' is F0 C8", s1.check(b"abcde") == bytes((0xF0, 0xC8)))
check("section 3: 01 00 2A is the colours 0, 16, 0, 42 at depth 4", s1.bytes_to_squares(bytes((1, 0, 0x2A)), 6) == [0, 16, 0, 42])
check("and the digits 0, 0, 2, 0, 0, 0, 5, 2 at depth 2", s1.bytes_to_squares(bytes((1, 0, 0x2A)), 3) == [0, 0, 2, 0, 0, 0, 5, 2])
check("section 5: the fast block is 58 bytes", s1.FAST_LEN == 58 and len(s1.pack_fast(STATE)) == 58)
plain = s1.pack_frame(4711, 9, 10, s1.pack_fast(STATE))
check("section 3: a frame with no chunk is 73 bytes, 195 squares at depth 2 and 98 at depth 4",
      len(plain) == 73 and len(s1.bytes_to_squares(plain, 3)) == 195 and len(s1.bytes_to_squares(plain, 6)) == 98)
check("squares back to bytes drop the filling of the last square",
      s1.squares_to_bytes(s1.bytes_to_squares(plain, 3), 3, 73) == plain and s1.squares_to_bytes(s1.bytes_to_squares(plain, 6), 6, 73) == plain)

# A frame written out by hand from the table of section 4, not by the code under test:
# version 1, session 0x1267, dwell 10, seq 9, fastLen 0, no object, then its check.
BY_HAND = bytes((1, 0x12, 0x67, 10, 0, 9, 0, 0, 0, 0, 0, 0, 0))
s_1 = sum(BY_HAND) % 255
s_2 = sum((len(BY_HAND) - i) * b for i, b in enumerate(BY_HAND)) % 255
check("section 4: the frame's fields are in the order version, session, dwell, seq, fastLen",
      s1.pack_frame(0x1267, 9, 10, b"") == BY_HAND + bytes((s_1, s_2)))
with_fast = BY_HAND[:6] + bytes((58,)) + s1.pack_fast(STATE) + bytes(6)
read = s1.unpack_frame(with_fast + s1.check(with_fast))
check("and a frame written by hand is read that way", (read["session"], read["dwell"], read["seq"]) == (0x1267, 10, 9))

# --- the fast block ---
back = s1.unpack_fast(s1.pack_fast(STATE))
check("every field of every group comes back", back == STATE)
some = dict(STATE, target=None, pet=None, threat=None)
back = s1.unpack_fast(s1.pack_fast(some))
check("an unknown group comes back as unknown, not as zeros", back["target"] is None and back["pet"] is None and back["threat"] is None and back["purse"] == STATE["purse"])
big = s1.unpack_fast(s1.pack_fast(dict(STATE, purse={"money": 2 ** 40, "bagFree": 999}, level={"level": 300, "xp": 2 ** 30, "xpMax": 1})))
check("a number too large for its field is the field's largest value",
      big["purse"] == {"money": 2 ** 32 - 1, "bagFree": 255} and big["level"] == {"level": 255, "xp": 2 ** 24 - 1, "xpMax": 1})
later = s1.pack_fast(STATE) + b"\x07\x07"
check("bytes a later version adds at the end are skipped", s1.unpack_fast(later) == STATE)
check("a fast block shorter than version 1's is refused", raises(lambda: s1.unpack_fast(s1.pack_fast(STATE)[:-1])))

# --- the frame ---
chunk = (4, 65535, 1, 3, b"\x00some bytes")
frame = s1.pack_frame(4711, 65536 + 9, 10, s1.pack_fast(STATE), chunk)
got = s1.unpack_frame(frame)
check("a frame with a chunk comes back: session, seq (wrapped), dwell, fast block, chunk",
      got["session"] == 4711 and got["seq"] == 9 and got["dwell"] == 10 and got["fast"] == STATE and got["chunk"] == chunk)
check("a frame with no object comes back with no chunk", s1.unpack_frame(plain)["chunk"] is None)
hand = s1.unpack_frame(s1.pack_frame(0x1267, 9, 10, s1.pack_fast(STATE)))
check("dwell and seq are not swapped on the way back", (hand["session"], hand["dwell"], hand["seq"]) == (0x1267, 10, 9)
      and s1.pack_frame(0x1267, 9, 10, s1.pack_fast(STATE))[:6] == bytes((1, 0x12, 0x67, 10, 0, 9)))
check("frame_length asks for more until it knows", s1.frame_length(frame[:6]) == (7, False)
      and s1.frame_length(frame[:7]) == (7 + 58 + 6, False) and s1.frame_length(frame[:71]) == (len(frame), True))
bad = bytearray(frame); bad[20] ^= 1
check("a changed byte fails the frame check", raises(lambda: s1.unpack_frame(bytes(bad))))
v2 = bytearray(plain); v2[0] = 2; v2[-2:] = s1.check(bytes(v2[:-2]))
check("an unknown version is refused", raises(lambda: s1.unpack_frame(bytes(v2))))
check("a frame cut short is refused", raises(lambda: s1.unpack_frame(frame[:-1])))
check("a chunk of 0 bytes, 13 chunks or 256 bytes cannot be packed",
      raises(lambda: s1.pack_frame(1, 1, 10, b"", (1, 1, 0, 1, b""))) and raises(lambda: s1.pack_frame(1, 1, 10, b"", (1, 1, 0, 13, b"x")))
      and raises(lambda: s1.pack_frame(1, 1, 10, b"", (1, 1, 0, 1, bytes(256)))))
odd = bytearray(plain); odd[7 + 58 + 3] = 1; odd[-2:] = s1.check(bytes(odd[:-2]))
check("object id 0 with another object field set is refused", raises(lambda: s1.unpack_frame(bytes(odd))))

# --- objects ---
TEXT = '{"free": 12, "items": [[2318, 14], [4234, 3]]}'
check("an object comes back, compressed and not", s1.unpack_object(s1.pack_object(TEXT)) == (1, TEXT)
      and s1.unpack_object(s1.pack_object(TEXT, False)) == (0, TEXT))
check("Chinese text comes back", s1.unpack_object(s1.pack_object("點解我呢區升得咁慢？"))[1] == "點解我呢區升得咁慢？")
check("an object the addon cannot read is format 255 with no text", s1.unpack_object(s1.pack_object(None)) == (255, None))
long_text = "".join(chr(0x4E00 + (i * 7919) % 20000) for i in range(3000))  # does not compress to 12 chunks
parts = s1.chunks_of(s1.pack_object(long_text), 100)
check("an object of more than 12 chunks is sent as format 254", len(parts) == 1 and s1.unpack_object(parts[0]) == (254, None))
spoiled = bytearray(s1.pack_object(TEXT)); spoiled[3] ^= 1
check("a changed byte fails the object check", raises(lambda: s1.unpack_object(bytes(spoiled))))
import zlib  # noqa: E402
wrapped = bytes((1,)) + zlib.compress(TEXT.encode())
check("a Deflate stream with a zlib header is read too", s1.unpack_object(wrapped + s1.check(wrapped)) == (1, TEXT))

broken = bytes((1, 0xFF, 0x01, 0x02))
check("an object that does not inflate is refused as a ValueError, like every other bad object",
      raises(lambda: s1.unpack_object(broken + s1.check(broken))))
latin = bytes((0, 0xFF, 0xFE))
check("an object that is not UTF-8 is refused as a ValueError", raises(lambda: s1.unpack_object(latin + s1.check(latin))))

# --- joining chunks (section 6) ---
def frames_for(text, oid=4, version=7, session=4711, size=10, dwell=10):
    parts = s1.chunks_of(s1.pack_object(text, False), size)
    return [s1.unpack_frame(s1.pack_frame(session, i, dwell, s1.pack_fast(STATE), (oid, version, i, len(parts), part)))
            for i, part in enumerate(parts)]


def run(frames, step=0.1):
    a, out = s1.Assembler(), []
    for i, f in enumerate(frames):
        r = a.feed(f, i * step)
        if r:
            out.append(r)
    return out, a


seq = frames_for(TEXT)
check("chunks in order make the object", run(seq)[0] == [(4, 0, TEXT)])
check("the same chunk seen several times is ignored", run([f for f in seq for _ in range(3)])[0] == [(4, 0, TEXT)])
check("a gap drops the partial object", run(seq[:2] + seq[3:])[0] == [])
check("chunks out of order make nothing", run([seq[1], seq[0]] + seq[2:])[0] == [])
other = frames_for(TEXT.replace("12", "13"), version=8)
check("chunks of two versions never mix", run(seq[:2] + other[2:])[0] == [])
check("a frame with no object in between drops the partial", run(seq[:2] + [s1.unpack_frame(plain)] + seq[2:])[0] == [])
slow, _ = run(seq, step=0.6)
check("a chunk that comes later than 5 x dwell after the last one does not join", slow == [])
stretch = frames_for(TEXT)
stretch[1]["dwell"] = 100  # the next chunk comes 1 s later and claims a long dwell
a = s1.Assembler()
a.feed(stretch[0], 0.0)
late = [a.feed(f, 1.0 + i * 0.1) for i, f in enumerate(stretch[1:])]
check("a later frame's longer dwell does not stretch the limit set when the last chunk was accepted", not any(late))
twice, a = run(seq + seq)
check("a version seen whole again is not reported twice, but its time is renewed", twice == [(4, 0, TEXT)] and a.objects[4][3] > 0.5)
check("a new version is reported", run(seq + other)[0] == [(4, 0, TEXT), (4, 0, TEXT.replace("12", "13"))])
changed = frames_for(TEXT, session=4712)
out, a = run(seq[:2] + changed)
check("a new session forgets what was held and starts again", out == [(4, 0, TEXT)] and a.session == 4712)

# --- the row through an image (sections 3 and 5) ---
def image(session, depth, levels, frame, square=2, scale=1.0, bend=None, dx=0, dy=0):
    cells = s1.row_colours(session, depth, levels, frame)
    lines = ["%d 0 %d %d %.6f %.6f %.6f" % (i * square, square, square, r, g, b) for i, (r, g, b) in enumerate(cells)]
    (tmp / "cells.txt").write_text("\n".join(lines) + "\n")
    hs.render(tmp / "cells.txt", tmp / "shot.bmp", scale, dx, dy, max(400, int(len(cells) * square * scale) + dx + 40), 60)
    data = bytearray((tmp / "shot.bmp").read_bytes())
    if bend:
        for o in range(138, len(data), 4):
            b, g, r = data[o], data[o + 1], data[o + 2]
            data[o], data[o + 1], data[o + 2] = bend(r, g, b)[::-1]
    return s1.read_row(hs.Bitmap(bytes(data)))


LEVELS = (0.75, 1.0, 0.09, None)  # levels 96, 127 and 11 of 127: they read 76, 100 and 9 per cent
for depth in (4, 2):
    for square in (2, 3, 4):
        row = image(4711, depth, LEVELS, frame, square)
        check("depth %d, %d pixels a square: the frame, the session and the level squares come back" % (depth, square),
              row is not None and row["frame"] == got and row["session"] == 4711 and row["depth"] == depth
              and row["levels"] == [76, 100, 9, None])
row = image(4711, 4, LEVELS, frame, dx=13, dy=7)
check("the row is found away from the corner, and its box is reported", row["frame"] == got and row["box"][0] == 13 and row["box"][1] == 7)
check("at depth 4 the nearest two palette colours are reported: 85 apart on a clean image", row["apart"] == 85)


def leak(r, g, b):  # blue leaks into green, as on the display of 12 Nov 2026
    return (r, min(255, g + b * 46 // 255), b)


leaky = image(4711, 4, LEVELS, frame, bend=leak)
check("depth 4 reads through the blue-into-green leak, by the palette", leaky["frame"] == got and leaky["apart"] < 85)
check("a full level reads 100 and an empty one 0", image(1, 2, (1.0, 0.0, 0.999, 0.004), plain)["levels"] == [100, 0, 100, 0])
full = s1.pack_frame(4711, 9, 10, s1.pack_fast(STATE), (4, 7, 0, 1, bytes(range(255))))  # the longest frame, 328 bytes
want = s1.unpack_frame(full)
for depth in (2, 4):
    for scale in (1.0015, 1.1, 1.25, 1.37, 1.5, 2.0, 3.3):  # squares of 2.003 to 6.6 pixels
        row = image(4711, depth, LEVELS, full, square=2, scale=scale)
        check("depth %d at a scale of %.4g: the longest frame comes back" % (depth, scale), row is not None and row["frame"] == want)
    missed = [k / 100 for k in range(100, 300, 13) if (image(4711, depth, LEVELS, full, square=2, scale=k / 100) or {}).get("frame") != want]
    check("depth %d: every scale from 1.00 to 2.95 in steps of 0.13 reads the longest frame" % depth, missed == [])
    small = image(4711, depth, LEVELS, full, square=2, scale=0.75)
    check("depth %d with squares of 1.5 pixels: refused with the reason, not misread" % depth,
          small is not None and small["frame"] is None and "under 2 pixels" in small["why"] and s1.Quality().note(small) is False)


def crush(r, g, b):  # a display on which the palette cannot be told apart
    return (255 if r > 127 else 0, 255 if g > 127 else 0, 255 if b > 127 else 0)


lost = image(4711, 4, LEVELS, frame, bend=crush)
check("when six bits cannot be read, the session and the levels still can, and the reason is given",
      lost is not None and lost["frame"] is None and lost["session"] == 4711 and lost["levels"] == [76, 100, 9, None]
      and lost["apart"] == 0 and lost["why"])
wrong = s1.pack_frame(4712, 9, 10, s1.pack_fast(STATE))
check("a frame whose session is not the row's is refused", image(4711, 2, LEVELS, wrong)["frame"] is None)
(tmp / "cells.txt").write_text("")
hs.render(tmp / "cells.txt", tmp / "shot.bmp", 1.0, 0, 0, 400, 60)
check("an image without a row gives nothing", s1.read_row(hs.Bitmap((tmp / "shot.bmp").read_bytes())) is None)

# --- asking for the fall-back (section 3) ---
q = s1.Quality()
check("a palette whose colours came back too close asks for depth 2 at once", q.note(lost) is True)
q = s1.Quality()
good = image(4711, 4, LEVELS, frame)
asked = [q.note(good) for _ in range(300)]
check("frames that pass never ask", not any(asked))
q = s1.Quality()
far = dict(good, frame=None, apart=85)
asked = [q.note(far if i % 20 == 0 else good) for i in range(400)]
check("more than 2 failed frames in 100, over the last 200, asks", any(asked))
q = s1.Quality()
asked = [q.note(far if i % 100 == 0 else good) for i in range(400)]
check("1 failed frame in 100 does not", not any(asked))
q = s1.Quality()
asked = [q.note(far) for _ in range(200)]
check("a reader that never read a depth-4 frame asks after 200 frames, not before", asked[-1] is True and not any(asked[:199]))
check("a row at depth 2 never asks", s1.Quality().note(image(4711, 2, LEVELS, frame)) is False)

shutil.rmtree(tmp, ignore_errors=True)
print("== %d checks, %d failed" % (checks, fails))
sys.exit(1 if fails else 0)
