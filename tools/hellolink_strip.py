#!/usr/bin/env python3
"""HelloLink strip: read the text the addon draws as coloured squares.

    python3 tools/hellolink_strip.py read --screen          # screenshot every display, decode, delete
    python3 tools/hellolink_strip.py read --image shot.bmp  # decode one BMP
    python3 tools/hellolink_strip.py probe --screen | --image shot.bmp   # the rows of /hlink probe squares
    python3 tools/hellolink_strip.py probe --rate                        # captures a second of a rectangle
    python3 tools/hellolink_strip.py render cells.txt out.bmp --scale 2 --dx 0 --dy 0 --width 800 --height 300

The format (the addon side is HelloLink/HelloLink.lua):
  * a square is one of 8 colours, each channel fully on or off: digit = 4*red + 2*green + blue;
  * the strip starts with the finder, the digits 4 2 1 7 0 6 3 5 (red green blue white black
    yellow cyan magenta), then the frame, three bits a square, most significant bit first,
    100 squares a row;
  * the frame is: length (2 bytes, big-endian), sequence (1 byte), the text, Fletcher-16
    (2 bytes) over everything before it.
`read` prints the text and exits 0, or prints "no strip" and exits 1. `render` exists for the
test: it draws the squares the addon asked for, on a noisy background.
"""
import argparse
import re
import shutil
import struct
import subprocess
import sys
import tempfile
from pathlib import Path

FINDER = bytes([4, 2, 1, 7, 0, 6, 3, 5])
PER_ROW = 100
MAX_TEXT = 1400
MAX_SIDE = 16384  # pixels; larger than any display
FINDER_RE = re.compile(b"".join(b"(" + re.escape(bytes([c])) + b"+)" for c in FINDER))
ON = bytes(1 if v > 127 else 0 for v in range(256))


class Bitmap:
    """An uncompressed 24- or 32-bit BMP, as rows of colour digits from the top."""

    def __init__(self, data: bytes):
        if len(data) < 54 or data[:2] != b"BM":
            raise ValueError("not a BMP file")
        offset, = struct.unpack_from("<I", data, 10)
        width, height, _planes, bpp, compression = struct.unpack_from("<iiHHI", data, 18)
        if bpp not in (24, 32) or compression not in (0, 3):
            raise ValueError("unsupported BMP: %d bits, compression %d" % (bpp, compression))
        if not (0 < width <= MAX_SIDE and 0 < abs(height) <= MAX_SIDE):
            raise ValueError("unsupported BMP size: %d x %d" % (width, height))
        masks = (0xFF0000, 0x00FF00, 0x0000FF)
        if compression == 3:
            if len(data) < 66:
                raise ValueError("BMP too short for its colour masks")
            masks = struct.unpack_from("<3I", data, 54)
        if any(m not in (0xFF, 0xFF00, 0xFF0000, 0xFF000000) for m in masks):
            raise ValueError("unsupported BMP colour masks")
        self.at = [(m.bit_length() - 8) // 8 for m in masks]  # byte of red, green, blue in a pixel
        self.width, self.height = width, abs(height)
        self.step = bpp // 8
        self.stride = (width * self.step + 3) & ~3
        self.top_down = height < 0
        # Every pixel the header promises must be in the file: never read past it, never pad.
        if offset < 54 or offset + self.stride * self.height > len(data):
            raise ValueError("BMP pixel data is not all in the file")
        self.data, self.offset = data, offset
        self.cache = {}

    def digits(self, y: int) -> bytes:
        row = self.cache.get(y)
        if row is None:
            line = y if self.top_down else self.height - 1 - y
            start = self.offset + line * self.stride
            raw = self.data[start:start + self.width * self.step]
            r, g, b = (int.from_bytes(raw[i::self.step].translate(ON), "big") for i in self.at)
            row = (4 * r + 2 * g + b).to_bytes(self.width, "big")  # no carry: a byte is at most 7
            self.cache[y] = row
        return row

    def digit(self, x: float, y: float):
        xi, yi = int(x), int(y)
        if not (0 <= xi < self.width and 0 <= yi < self.height):
            return None
        return self.digits(yi)[xi]


def fletcher16(data: bytes):
    s1 = s2 = 0
    for b in data:
        s1 = (s1 + b) % 255
        s2 = (s2 + s1) % 255
    return s1, s2


def frame_at(bmp: Bitmap, x0: float, y0: float, w: float):
    """The text of a strip whose first square has its top-left corner at (x0, y0), squares w wide."""
    def squares(first, count):
        out = []
        for i in range(first, first + count):
            d = bmp.digit(x0 + (i % PER_ROW + 0.5) * w, y0 + (i // PER_ROW + 0.5) * w)
            if d is None:
                return None
            out.append(d)
        return out

    def to_bytes(ds, count):
        bits = "".join(format(d, "03b") for d in ds)
        return bytes(int(bits[i * 8:i * 8 + 8], 2) for i in range(count))

    if squares(0, len(FINDER)) != list(FINDER):
        return None
    head = squares(len(FINDER), 8)
    if head is None:
        return None
    n, seq = int.from_bytes(to_bytes(head, 2), "big"), to_bytes(head, 3)[2]
    if not 1 <= n <= MAX_TEXT or seq == 0:  # the addon sends no empty text and no sequence 0;
        return None                          # a finder followed by black would pass otherwise
    total = n + 5
    body = squares(len(FINDER), -(-total * 8 // 3))
    if body is None:
        return None
    frame = to_bytes(body, total)
    if fletcher16(frame[:-2]) != (frame[-2], frame[-1]):
        return None
    try:
        return frame[3:-2].decode("utf-8")
    except UnicodeDecodeError:
        return None


def decode(bmp: Bitmap):
    tried = set()
    for y in range(0, bmp.height, 2):
        for m in FINDER_RE.finditer(bmp.digits(y)):
            # The six inner runs are whole squares; the outer two may have run into a neighbour.
            w = (m.start(8) - m.start(2)) / 6
            runs = [m.end(i) - m.start(i) for i in range(1, 9)]
            if w < 3 or any(abs(r - w) > max(1.5, w / 4) for r in runs[1:7]) or min(runs[0], runs[7]) < w * 0.7:
                continue
            x0 = m.start(2) - w
            # The strip's top is the highest row where the whole finder still shows: one
            # square alone could run into a background of its own colour.
            top = y
            while top > 0 and all(bmp.digit(x0 + (i + 0.5) * w, top - 1) == FINDER[i] for i in range(8)):
                top -= 1
            if (m.start(2), top) in tried:
                continue
            tried.add((m.start(2), top))
            # Six squares give the width to a sixth of a pixel; a row is 100 squares long, so
            # try the widths around it, nearest first. The checksum says which one fits.
            for k in range(61):
                dw = (k + 1) // 2 * 0.01 * (1 if k % 2 else -1)
                text = frame_at(bmp, x0, top, w + dw)
                if text is not None:
                    return text
    return None


def on_screen(fn):
    """fn(bitmap) for a screenshot of each display until one returns a value; (value, displays)."""
    tmp = Path(tempfile.mkdtemp(prefix="hellolink-"))
    try:
        shots = [tmp / ("display%d.bmp" % i) for i in range(1, 5)]
        subprocess.run(["screencapture", "-x", "-t", "bmp", *map(str, shots)],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
        found = [s for s in shots if s.exists()]
        for shot in found:
            value = fn(Bitmap(shot.read_bytes()))
            if value is not None:
                return value, len(found)
        return None, len(found)
    finally:
        shutil.rmtree(tmp)  # a screenshot never outlives the read; a failure here is raised, not hidden


def read_screen():
    return on_screen(decode)


PROBE_SIZES = (8, 4, 3, 2)
PROBE_N = 120


def probe_digits(size: int):
    out, state = [], size
    for _ in range(PROBE_N):
        state = (state * 75 + 74) % 65537
        out.append(state % 8)
    return out


def probe_squares(bmp: Bitmap):
    """For each probe row found: {size: (measured square in pixels, wrong digits)}; None if no row."""
    best = {}
    for y in range(bmp.height):
        for m in FINDER_RE.finditer(bmp.digits(y)):
            w = (m.start(8) - m.start(2)) / 6
            size = round(w)
            if size not in PROBE_SIZES or abs(w - size) > 0.34:
                continue
            x0 = m.start(2) - w
            top = y
            while top > 0 and all(bmp.digit(x0 + (i + 0.5) * w, top - 1) == FINDER[i] for i in range(8)):
                top -= 1
            want = probe_digits(size)
            wrong = sum(bmp.digit(x0 + (8 + i + 0.5) * w, top + w / 2) != want[i] for i in range(PROBE_N))
            if size not in best or wrong < best[size][1]:
                best[size] = (w, wrong)
    return best or None


def capture_rate(count: int = 10):
    """Captures a second of a 600 x 80 rectangle, read and parsed, as `watch` will do."""
    import time
    tmp = Path(tempfile.mkdtemp(prefix="hellolink-"))
    try:
        shot = tmp / "rect.bmp"
        start = time.monotonic()
        for _ in range(count):
            subprocess.run(["screencapture", "-x", "-t", "bmp", "-R", "0,0,600,80", str(shot)],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
            Bitmap(shot.read_bytes()).digits(0)
        return count / (time.monotonic() - start)
    finally:
        shutil.rmtree(tmp)


def render(cells: Path, out: Path, scale: float, dx: int, dy: int, width: int, height: int):
    # A background that tries to fool the reader: grey noise, pure colours, and a row that
    # starts like the finder.
    state = 12345
    px = bytearray(width * height * 4)
    for i in range(width * height):
        state = (state * 1103515245 + 12345) & 0x7FFFFFFF
        v = 60 + (state >> 16) % 120
        px[i * 4:i * 4 + 4] = bytes((v, v, v, 255))

    def rect(x, y, w, h, rgb):
        for yy in range(max(0, y), min(height, y + h)):
            for xx in range(max(0, x), min(width, x + w)):
                px[(yy * width + xx) * 4:(yy * width + xx) * 4 + 4] = bytes((rgb[2], rgb[1], rgb[0], 255))

    rect(width - 90, height - 40, 80, 30, (255, 0, 0))
    for i, d in enumerate(FINDER[:5]):
        rect(width - 200 + i * 9, height - 80, 9, 9, (255 * (d >> 2 & 1), 255 * (d >> 1 & 1), 255 * (d & 1)))
    for line in cells.read_text().splitlines():
        x, y, w, h, r, g, b = map(float, line.split())
        left, top = round(dx + x * scale), round(dy + y * scale)
        rect(left, top, round(dx + (x + w) * scale) - left, round(dy + (y + h) * scale) - top,
             (round(r * 255), round(g * 255), round(b * 255)))
    # The header screencapture writes: 124 bytes, 32 bits, bit fields, rows from the top.
    header = struct.pack("<IiiHHIIiiII4I", 124, width, -height, 1, 32, 3, len(px), 2835, 2835, 0, 0,
                         0x00FF0000, 0x0000FF00, 0x000000FF, 0xFF000000).ljust(124, b"\0")
    out.write_bytes(b"BM" + struct.pack("<IHHI", 14 + 124 + len(px), 0, 0, 14 + 124) + header + bytes(px))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    r = sub.add_parser("read")
    src = r.add_mutually_exclusive_group(required=True)
    src.add_argument("--screen", action="store_true")
    src.add_argument("--image", type=Path)
    q = sub.add_parser("probe")
    how = q.add_mutually_exclusive_group(required=True)
    how.add_argument("--screen", action="store_true")
    how.add_argument("--image", type=Path)
    how.add_argument("--rate", action="store_true")
    d = sub.add_parser("render")
    d.add_argument("cells", type=Path)
    d.add_argument("out", type=Path)
    d.add_argument("--scale", type=float, default=1.0)
    for name in ("--dx", "--dy"):
        d.add_argument(name, type=int, default=0)
    d.add_argument("--width", type=int, default=800)
    d.add_argument("--height", type=int, default=300)
    args = ap.parse_args()
    if args.cmd == "render":
        render(args.cells, args.out, args.scale, args.dx, args.dy, args.width, args.height)
        return
    if args.cmd == "probe":
        try:
            if args.rate:
                print("%.1f captures a second of a 600 x 80 rectangle" % capture_rate())
                return
            rows = on_screen(probe_squares)[0] if args.screen else probe_squares(Bitmap(args.image.read_bytes()))
        except (OSError, ValueError) as e:
            sys.exit("probe: %s" % e)
        for size in PROBE_SIZES:
            if rows and size in rows:
                print("%d px: found, square %.2f px, %d of %d wrong" % (size, rows[size][0], rows[size][1], PROBE_N))
            else:
                print("%d px: not found" % size)
        sys.exit(0 if rows else 1)
    if args.screen:
        try:
            text, shots = read_screen()
        except OSError as e:
            sys.exit("the screenshots could not be deleted, delete them by hand: %s" % e)
        where = "%d screenshot(s)" % shots
    else:
        try:
            text, where = decode(Bitmap(args.image.read_bytes())), str(args.image)
        except ValueError as e:
            sys.exit("%s: %s" % (args.image, e))
    if text is None:
        print("no strip in " + where)
        sys.exit(1)
    print(text)


if __name__ == "__main__":
    main()
