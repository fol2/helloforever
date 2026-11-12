#!/usr/bin/env python3
"""HelloLink strip: read the text the addon draws as coloured squares.

    python3 tools/hellolink_strip.py read --screen          # screenshot every display, decode, delete
    python3 tools/hellolink_strip.py read --image shot.bmp  # decode one BMP
    python3 tools/hellolink_strip.py probe --screen | --image shot.bmp   # the rows of the /hlink probe commands
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

    def rgb(self, x: float, y: float):
        """The pixel's (red, green, blue), or None outside the image."""
        xi, yi = int(x), int(y)
        if not (0 <= xi < self.width and 0 <= yi < self.height):
            return None
        line = yi if self.top_down else self.height - 1 - yi
        at = self.offset + line * self.stride + xi * self.step
        return tuple(self.data[at + i] for i in self.at)

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
    """For each probe row found: {size: (width of a square, height of the row, wrong digits)}, in
    pixels; None if no row. The height is that of the finder, measured as the width is."""
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
            bottom = top
            while bottom + 1 < bmp.height and all(bmp.digit(x0 + (i + 0.5) * w, bottom + 1) == FINDER[i] for i in range(8)):
                bottom += 1
            height = bottom - top + 1
            want = probe_digits(size)
            wrong = sum(bmp.digit(x0 + (8 + i + 0.5) * w, top + height / 2) != want[i] for i in range(PROBE_N))
            if size not in best or wrong < best[size][2]:
                best[size] = (w, height, wrong)
    return best or None


BARS_RE = re.compile(b"".join(b"(" + re.escape(bytes([c])) + b"+)" for c in reversed(FINDER)))
BAR_NAMES = ("health", "power", "target health", "pet health", "threat", "pet threat")
BAR_PX, BAR_GAP, BAR_SQUARE = 100, 4, 3


BAR_SHAPE = re.compile(b"\x00{0,2}(\x07*)\x00*$")
BAR_TAIL = 8 * BAR_SQUARE + BAR_GAP + len(BAR_NAMES) * (BAR_PX + BAR_GAP)  # where the second finder starts


def probe_bars(bmp: Bitmap):
    """The fill of each bar of `/hlink probe bars`, in per cent; None if the row is not there.

    The row is the reversed finder, the bars, and the reversed finder again BAR_TAIL design
    pixels after the first. The scale is taken from the distance between the two, so a bar is
    placed to the pixel at any scale. A short finder alone cannot give that: its squares can
    all measure 3 pixels at a scale of 0.99. A row without its second finder is refused."""
    for y in range(bmp.height):
        row = bmp.digits(y)
        heads = [m for m in BARS_RE.finditer(row)
                 if (m.start(8) - m.start(2)) / 6 >= 1.5]
        for a in heads:
            w = (a.start(8) - a.start(2)) / 6
            for b in heads:
                scale = (b.start(2) - a.start(2)) / BAR_TAIL
                if scale <= 0 or abs(scale * BAR_SQUARE - w) > max(0.5, w / 4):
                    continue
                origin = a.start(2) - BAR_SQUARE * scale  # the row's left edge
                fills = []
                for k in range(len(BAR_NAMES)):
                    left = origin + (8 * BAR_SQUARE + BAR_GAP + k * (BAR_PX + BAR_GAP)) * scale
                    x, end = round(left), round(left + BAR_PX * scale)
                    # One pixel either side belongs to the black gaps: the bar's edges fall
                    # between pixels at most scales. In that window a bar is black for at most
                    # two pixels, white for its fill, then black to the end.
                    shape = BAR_SHAPE.match(row[max(0, x - 1):end + 1])
                    if end <= x or not shape:
                        fills = None
                        break
                    fills.append(min(100, round(len(shape.group(1)) * 100 / (end - x))))
                if fills is not None:
                    return fills
    return None


def turned(by: int):
    """The finder's digits turned by some places: a finder of its own for a kind of probe row."""
    digits = FINDER[by:] + FINDER[:by]
    return digits, re.compile(b"".join(b"(" + re.escape(bytes([c])) + b"+)" for c in digits))


def whole_squares(m):
    """The side of a finder's squares when all six inner ones are the same whole number of pixels."""
    runs = [m.end(i) - m.start(i) for i in range(2, 8)]
    return runs[0] if len(set(runs)) == 1 and min(m.end(1) - m.start(1), m.end(8) - m.start(8)) >= runs[0] else None


def top_of(bmp: Bitmap, finder, x0: float, w: float, y: int):
    while y > 0 and all(bmp.digit(x0 + (i + 0.5) * w, y - 1) == finder[i] for i in range(8)):
        y -= 1
    return y


# --- the depth engine: how many colours a square can carry ---------------------------------
DEPTH_FINDER, DEPTH_RE = turned(1)
DEPTH_LINE, DEPTH_N = 256, 240


def depth_colour(i: int, levels: int):
    """Symbol i of levels cubed, as (red, green, blue) between 0 and 1."""
    return (i // (levels * levels) / (levels - 1), i // levels % levels / (levels - 1), i % levels / (levels - 1))


def depth_pattern(levels: int):
    out, state = [], levels
    for _ in range(DEPTH_N):
        state = (state * 75 + 74) % 65537
        out.append(state % levels ** 3)
    return out


def probe_depth(bmp: Bitmap):
    """A row of `/hlink probe depth`: (levels a channel, pixels a square, wrong pattern squares,
    the smallest distance between two palette colours as they came back); None if not there.

    The engine does not know what a colour should look like on this screen. It reads the
    palette the row carries (every colour once, in order) and names each pattern square by
    the palette colour nearest to it. So it measures what this screen can tell apart."""
    for y in range(bmp.height):
        for m in DEPTH_RE.finditer(bmp.digits(y)):
            w = whole_squares(m)
            if not w:
                continue
            x0 = m.start(2) - w
            top = top_of(bmp, DEPTH_FINDER, x0, w, y)

            def at(i):
                return bmp.rgb(x0 + (i % DEPTH_LINE + 0.5) * w, top + (i // DEPTH_LINE + 0.5) * w)

            def digit(i):
                return bmp.digit(x0 + (i % DEPTH_LINE + 0.5) * w, top + (i // DEPTH_LINE + 0.5) * w)

            if digit(8) is None or digit(9) is None:
                continue
            levels = digit(8) * 8 + digit(9)
            if not 2 <= levels <= 8:
                continue
            symbols = levels ** 3
            palette = [at(10 + i) for i in range(symbols)]
            cells = [at(10 + symbols + i) for i in range(DEPTH_N)]
            if None in palette or None in cells:
                continue

            def gap(a, b):
                return max(abs(a[0] - b[0]), abs(a[1] - b[1]), abs(a[2] - b[2]))

            def nearest(c):
                return min(range(symbols), key=lambda i: (c[0] - palette[i][0]) ** 2 + (c[1] - palette[i][1]) ** 2 + (c[2] - palette[i][2]) ** 2)

            wrong = sum(nearest(c) != want for c, want in zip(cells, depth_pattern(levels)))
            apart = min(gap(palette[i], palette[j]) for i in range(symbols) for j in range(i + 1, min(symbols, i + levels * levels + 1)))
            return levels, float(w), wrong, apart
    return None


# --- colour curves: a secret per cent as squares --------------------------------------------
CURVE_FINDER, CURVE_RE = turned(2)
CURVE_NAMES = ("health", "power", "target health", "pet health")


def probe_curves(bmp: Bitmap):
    """A row of `/hlink probe curves`: for each guess of the range (1, 100), the per cent of each
    value or None where the squares hold no level; None if the row is not there."""
    for y in range(bmp.height):
        for m in CURVE_RE.finditer(bmp.digits(y)):
            w = whole_squares(m)
            if not w:
                continue
            x0 = m.start(2) - w
            top = top_of(bmp, CURVE_FINDER, x0, w, y)
            out = {}
            for r, name in enumerate((1, 100)):
                values = []
                for v in range(len(CURVE_NAMES)):
                    first = 8 + (r * len(CURVE_NAMES) + v) * 3
                    a, b, c = (bmp.digit(x0 + (first + k + 0.5) * w, top + w / 2) for k in range(3))
                    values.append(round((a * 16 + b * 2 + (c == 6)) * 100 / 128) if c in (2, 6) else None)
                out[name] = values
            return out
    return None


def capture_rate(count: int = 10):
    """Captures a second of a 600 x 80 rectangle, each one searched for a text frame and for
    probe rows as `watch` will search it. Every capture must succeed and be a new file."""
    import time
    tmp = Path(tempfile.mkdtemp(prefix="hellolink-"))
    try:
        start = time.monotonic()
        for i in range(count):
            shot = tmp / ("rect%d.bmp" % i)
            done = subprocess.run(["screencapture", "-x", "-t", "bmp", "-R", "0,0,600,80", str(shot)],
                                  stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
            if getattr(done, "returncode", 1) != 0 or not shot.exists():
                raise OSError("capture %d of %d failed" % (i + 1, count))
            bmp = Bitmap(shot.read_bytes())
            shot.unlink()
            decode(bmp)
            probe_squares(bmp)
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
                print("%.1f captures a second of a 600 x 80 rectangle, each searched and decoded" % capture_rate())
                return
            def every(bmp):
                found = (probe_squares(bmp), probe_bars(bmp), probe_curves(bmp), probe_depth(bmp))
                return found if any(f is not None for f in found) else None

            found = on_screen(every)[0] if args.screen else every(Bitmap(args.image.read_bytes()))
        except (OSError, ValueError) as e:
            sys.exit("probe: %s" % e)
        rows, fills, curves, depth = found or (None, None, None, None)
        if fills:
            print("bars: " + ", ".join("%s %d%%" % pair for pair in zip(BAR_NAMES, fills)))
        if curves:
            for scale, values in curves.items():
                print("curve(%d): " % scale + ", ".join(
                    "%s %s" % (n, "-" if v is None else "%d%%" % v) for n, v in zip(CURVE_NAMES, values)))
        if depth:
            levels, w, wrong, apart = depth
            print("depth %d levels (%d bits a square), %d px: %d of %d wrong; the nearest two colours came back %d apart"
                  % (levels, round(3 * (levels.bit_length() - 1)) if levels in (2, 4, 8) else 0, w, wrong, DEPTH_N, apart))
        if (fills or curves or depth) and not rows:
            sys.exit(0)
        for size in PROBE_SIZES:
            if rows and size in rows:
                w, h, wrong = rows[size]
                shape = "" if h == size and abs(w - size) < 0.005 else " (NOT the square asked for)"
                print("%d px: found, %.2f px wide and %d px high%s, %d of %d wrong" % (size, w, h, shape, wrong, PROBE_N))
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
