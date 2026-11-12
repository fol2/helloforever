#!/usr/bin/env python3
"""The strip reader against images the addon never draws. Usage: python3 tests/hellolink_strip_test.py"""
import shutil
import struct
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "tools"))
import hellolink_strip as hs  # noqa: E402

fails = checks = 0
tmp = Path(tempfile.mkdtemp(prefix="hellolink-test-"))


def check(name, cond):
    global fails, checks
    checks += 1
    fails += not cond
    print(("PASS " if cond else "FAIL ") + name)


def digits_of(frame: bytes):
    bits = "".join(format(b, "08b") for b in frame)
    bits += "0" * (-len(bits) % 3)
    return list(hs.FINDER) + [int(bits[i:i + 3], 2) for i in range(0, len(bits), 3)]


def frame_of(text: str, seq: int = 1):
    body = text.encode()
    head = struct.pack(">HB", len(body), seq) + body
    return head + bytes(hs.fletcher16(head))


def image(digits, extra=(), scale=2.0, dx=40, dy=60):
    lines = ["%d %d 6 6 %d %d %d" % (i % 100 * 6, i // 100 * 6, d >> 2 & 1, d >> 1 & 1, d & 1) for i, d in enumerate(digits)]
    (tmp / "cells.txt").write_text("\n".join(lines + list(extra)) + "\n")
    hs.render(tmp / "cells.txt", tmp / "shot.bmp", scale, dx, dy, 1400, 300)
    return (tmp / "shot.bmp").read_bytes()


def decode(data):
    return hs.decode(hs.Bitmap(data))


def raises(fn, kind):
    try:
        fn()
    except kind:
        return True
    return False


good = digits_of(frame_of("hello world"))
check("a valid strip decodes", decode(image(good)) == "hello world")
check("a finder followed by black is not an empty message", decode(image(list(hs.FINDER) + [0] * 40)) is None)
check("a frame with sequence 0 is refused", decode(image(digits_of(frame_of("hello", 0)))) is None)
check("a frame of length 0 is refused", decode(image(digits_of(frame_of("")))) is None)
check("a block of the green square's colour above it does not hide the strip",
      decode(image(good, extra=["6 -20 6 20 0 1 0"])) == "hello world")
check("a block of the finder's colours above every square does not hide the strip",
      decode(image(good, extra=["0 -20 3 20 1 0 0", "6 -20 3 20 0 1 0", "12 -20 3 20 0 0 1"])) == "hello world")

whole = image(good)
check("a header with no pixels is refused", raises(lambda: hs.Bitmap(whole[:138]), ValueError))
check("a file cut short is refused", raises(lambda: hs.Bitmap(whole[:len(whole) // 2]), ValueError))
far = bytearray(whole)
struct.pack_into("<I", far, 10, len(whole) + 1000)
check("a pixel offset past the file is refused", raises(lambda: hs.Bitmap(bytes(far)), ValueError))
huge = bytearray(whole)
struct.pack_into("<i", huge, 18, 2000000000)
check("an absurd width is refused", raises(lambda: hs.Bitmap(bytes(huge)), ValueError))
check("fifty-three bytes are not a BMP", raises(lambda: hs.Bitmap(whole[:53]), ValueError))

real_run, real_rmtree = subprocess.run, shutil.rmtree
made = []


def fake_capture(cmd, **_):
    made.append(Path(cmd[-1]).parent)
    Path(cmd[4]).write_bytes(whole)


def refuse(_path, **_):
    raise PermissionError("cannot delete")


subprocess.run = fake_capture
try:
    check("read_screen decodes a screenshot", hs.read_screen() == ("hello world", 1))
    check("and leaves no screenshot behind", not made[-1].exists())
    shutil.rmtree = refuse
    check("a screenshot that cannot be deleted is an error, not a success", raises(hs.read_screen, OSError))
finally:
    subprocess.run, shutil.rmtree = real_run, real_rmtree
    for d in made:
        shutil.rmtree(d, ignore_errors=True)
    shutil.rmtree(tmp, ignore_errors=True)

print("== %d checks, %d failed" % (checks, fails))
sys.exit(1 if fails else 0)
