#!/usr/bin/env python3
"""The reader tool against images the addon never draws: the bitmap, the depth probe and the
screenshots it takes. Format 0 and the other spike probes were removed (#45).
Usage: python3 tests/hellolink_strip_test.py"""
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


def raises(fn, kind):
    try:
        fn()
    except kind:
        return True
    return False


check("format 0 is gone from the reader: no decoder, no text reader, no spike probes (#45)",
      not any(hasattr(hs, name) for name in ("decode", "frame_at", "fletcher16", "read_screen", "probe_squares",
                                             "probe_bars", "probe_curves", "capture_rate")))

# A bitmap of some squares on the renderer's noisy background.
(tmp / "cells.txt").write_text("".join("%d 0 6 6 %d %d %d\n" % (i * 6, i & 4 and 1, i & 2 and 1, i & 1) for i in range(40)))
hs.render(tmp / "cells.txt", tmp / "shot.bmp", 2.0, 40, 60, 1400, 300)
whole = (tmp / "shot.bmp").read_bytes()
check("a rendered image is a bitmap the reader takes", hs.Bitmap(whole).width == 1400)
check("a header with no pixels is refused", raises(lambda: hs.Bitmap(whole[:138]), ValueError))
check("a file cut short is refused", raises(lambda: hs.Bitmap(whole[:len(whole) // 2]), ValueError))
far = bytearray(whole)
struct.pack_into("<I", far, 10, len(whole) + 1000)
check("a pixel offset past the file is refused", raises(lambda: hs.Bitmap(bytes(far)), ValueError))
huge = bytearray(whole)
struct.pack_into("<i", huge, 18, 2000000000)
check("an absurd width is refused", raises(lambda: hs.Bitmap(bytes(huge)), ValueError))
check("fifty-three bytes are not a BMP", raises(lambda: hs.Bitmap(whole[:53]), ValueError))

# the depth engine: colours are told apart by the palette the row carries, not by fixed levels
def depth_image(levels, px, bend=None):
    symbols = levels ** 3
    row = list(hs.DEPTH_FINDER) + [levels // 8, levels % 8]
    cells = [(d >> 2 & 1, d >> 1 & 1, d & 1) for d in row]
    cells += [hs.depth_colour(i, levels) for i in range(symbols)]
    cells += [hs.depth_colour(i, levels) for i in hs.depth_pattern(levels)]
    lines = ["%d %d %d %d %.6f %.6f %.6f" % (i % 256 * px, i // 256 * px, px, px, r, g, b) for i, (r, g, b) in enumerate(cells)]
    (tmp / "cells.txt").write_text("\n".join(lines) + "\n")
    hs.render(tmp / "cells.txt", tmp / "shot.bmp", 1.0, 20, 30, 1400, 120)
    data = bytearray((tmp / "shot.bmp").read_bytes())
    if bend:  # what a display's colour management does: channels leak into each other
        for o in range(138, len(data), 4):
            b, g, r = data[o], data[o + 1], data[o + 2]
            data[o], data[o + 1], data[o + 2] = bend(r, g, b)[::-1]
    return hs.probe_depth(hs.Bitmap(bytes(data)))


def leak(r, g, b):  # blue leaks into green as seen in the game: (0, 0, 255) came back (0, 46, 255)
    return (r, min(255, g + b * 46 // 255), b)


clean = depth_image(4, 2)
check("the depth engine reads 4 levels a channel with no error", clean is not None and clean[:3] == (4, 2.0, 0))
bent = depth_image(4, 2, leak)
check("and still with blue leaking into green, because it reads the palette first", bent is not None and bent[2] == 0)
check("it reports how far apart the nearest two colours came back", bent[3] < clean[3] and clean[3] == 85)
# two colours far apart in the palette's order (0 and 37 of 216) that come back the same
twin = depth_image(6, 2, lambda r, g, b: (0, 0, 0) if (r, g, b) == (51, 0, 51) else (r, g, b))
check("every pair of palette colours is compared: two far apart in order that came back identical are 0 apart",
      twin is not None and twin[3] == 0)
deep = depth_image(8, 1)
check("8 levels a channel at 1 pixel a square, 512 colours: no error on a clean image", deep is not None and deep[:3] == (8, 1.0, 0))
lost = depth_image(8, 1, leak)  # the leak pushes bright greens to 255: some colours come back the same
check("with the leak some of the 512 colours come back identical, and the engine says so: 0 apart, squares wrong",
      lost is not None and lost[3] == 0 and lost[2] > 0)

real_run, real_rmtree = subprocess.run, shutil.rmtree
made = []


def fake_capture(cmd, **_):
    made.append(Path(cmd[4]).parent)
    Path(cmd[4]).write_bytes(whole)


def refuse(_path, ignore_errors=False, **_):
    # like the real rmtree: a failure is raised only when the caller did not ask to hide it
    if not ignore_errors:
        raise PermissionError("cannot delete")


subprocess.run = fake_capture
try:
    check("on_screen hands each screenshot to the reader", hs.on_screen(lambda bmp: bmp.width) == (1400, 1))
    check("and leaves no screenshot behind", not made[-1].exists())
    shutil.rmtree = refuse
    check("a screenshot that cannot be deleted is an error, not a success", raises(lambda: hs.on_screen(lambda bmp: 1), OSError))
finally:
    subprocess.run, shutil.rmtree = real_run, real_rmtree
    for d in made:
        shutil.rmtree(d, ignore_errors=True)
    shutil.rmtree(tmp, ignore_errors=True)

print("== %d checks, %d failed" % (checks, fails))
sys.exit(1 if fails else 0)
