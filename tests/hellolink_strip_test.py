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

# probe rows: the height counts as well as the width
def probe_image(size, high):
    ds = list(hs.FINDER) + hs.probe_digits(size)
    lines = ["%d 0 %d %d %d %d %d" % (i * size, size, high, d >> 2 & 1, d >> 1 & 1, d & 1) for i, d in enumerate(ds)]
    (tmp / "cells.txt").write_text("\n".join(lines) + "\n")
    hs.render(tmp / "cells.txt", tmp / "shot.bmp", 1.0, 30, 20, 700, 100)
    return hs.probe_squares(hs.Bitmap((tmp / "shot.bmp").read_bytes()))


check("a probe row of true squares is measured as such", probe_image(4, 4) == {4: (4.0, 4, 0)})
check("a row of 4 x 9 rectangles is not reported as squares of 4", probe_image(4, 9) == {4: (4.0, 9, 0)})

# bars: the scale comes from the distance between the row's two finders
def bars_image(scale, tail=True):
    rev = list(reversed(hs.FINDER))
    lines = ["%d 0 3 3 %d %d %d" % (i * 3, d >> 2 & 1, d >> 1 & 1, d & 1) for i, d in enumerate(rev)]
    lines.append("24 0 420 3 0 0 0")  # the black the addon draws behind the bars
    for k, share in enumerate((0.5, 1.0, 0.25, 0.0)):
        if share:
            lines.append("%d 0 %g 3 1 1 1" % (24 + 4 + k * 104, 100 * share))
    if tail:
        lines += ["%d 0 3 3 %d %d %d" % (hs.BAR_TAIL + i * 3, d >> 2 & 1, d >> 1 & 1, d & 1) for i, d in enumerate(rev)]
    (tmp / "cells.txt").write_text("\n".join(lines) + "\n")
    hs.render(tmp / "cells.txt", tmp / "shot.bmp", scale, 0, 0, 1900, 60)
    return hs.probe_bars(hs.Bitmap((tmp / "shot.bmp").read_bytes()))


def near(got, want=(50, 100, 25, 0)):
    return got is not None and all(abs(a - b) <= 2 for a, b in zip(got, want))


check("bars are read at the size they were drawn", bars_image(1.0) == [50, 100, 25, 0])
# 0.99: every square of the short finder still measures 3 pixels, but the bars are shorter.
# A reader that trusted the finder alone read 49, 98, 22, 0 here.
check("bars at a scale of 0.99 read 50, 100, 25, 0 to within 2", near(bars_image(0.99)))
check("and at 1.15, two thirds and twice the size", near(bars_image(1.15)) and near(bars_image(2 / 3)) and near(bars_image(2.0)))
sweep = [bars_image(i / 100) for i in range(60, 401, 5)]
check("every scale from 0.60 to 4.00 in steps of 0.05 reads right to within 2",
      all(r is None or near(r) for r in sweep) and sum(r is not None for r in sweep) == len(sweep))
check("a row without its second finder is refused", bars_image(1.0, tail=False) is None)

real_run, real_rmtree = subprocess.run, shutil.rmtree
made = []


def fake_capture(cmd, **_):
    made.append(Path(cmd[-1]).parent)
    Path(cmd[4]).write_bytes(whole)


def refuse(_path, ignore_errors=False, **_):
    # like the real rmtree: a failure is raised only when the caller did not ask to hide it
    if not ignore_errors:
        raise PermissionError("cannot delete")


subprocess.run = fake_capture
try:
    check("read_screen decodes a screenshot", hs.read_screen() == ("hello world", 1))
    check("and leaves no screenshot behind", not made[-1].exists())
    shutil.rmtree = refuse
    check("a screenshot that cannot be deleted is an error, not a success", raises(hs.read_screen, OSError))
    shutil.rmtree = real_rmtree
    calls = []

    class Done:
        def __init__(self, code):
            self.returncode = code

    def flaky(cmd, **_):  # the first capture works, the rest fail
        calls.append(cmd)
        if len(calls) == 1:
            Path(cmd[-1]).write_bytes(whole)
            return Done(0)
        return Done(1)

    subprocess.run = flaky
    check("a rate is not reported when a capture failed", raises(lambda: hs.capture_rate(3), OSError))

    def steady(cmd, **_):
        Path(cmd[-1]).write_bytes(whole)
        return Done(0)

    subprocess.run = steady
    check("a rate is reported when every capture worked", hs.capture_rate(3) > 0)
finally:
    subprocess.run, shutil.rmtree = real_run, real_rmtree
    for d in made:
        shutil.rmtree(d, ignore_errors=True)
    shutil.rmtree(tmp, ignore_errors=True)

print("== %d checks, %d failed" % (checks, fails))
sys.exit(1 if fails else 0)
