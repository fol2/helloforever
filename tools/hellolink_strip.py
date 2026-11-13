#!/usr/bin/env python3
"""HelloLink strip: read the text the addon draws as coloured squares.

    python3 tools/hellolink_strip.py read --screen          # screenshot every display, decode, delete
    python3 tools/hellolink_strip.py read --image shot.bmp  # decode one BMP
    python3 tools/hellolink_strip.py probe --screen | --image shot.bmp   # the rows of the /hlink probe commands
    python3 tools/hellolink_strip.py probe --rate                        # captures a second of a rectangle
    python3 tools/hellolink_strip.py watch [--json] [--addons <AddOns dir>]  # format 1: follow the row on screen
    python3 tools/hellolink_strip.py rows a.bmp b.bmp ...                 # format 1: each image's row, as JSON
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
import threading
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

    @classmethod
    def from_bgra(cls, width: int, height: int, data: bytes):
        """A bitmap from raw pixels: blue green red alpha, rows from the top (a capture frame)."""
        if width <= 0 or height <= 0 or width > MAX_SIDE or height > MAX_SIDE or len(data) < width * height * 4:
            raise ValueError("bad frame: %d x %d with %d bytes" % (width, height, len(data)))
        self = cls.__new__(cls)
        self.width, self.height, self.step, self.stride = width, height, 4, width * 4
        self.top_down, self.data, self.offset, self.at, self.cache = True, data, 0, [2, 1, 0], {}
        return self

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
            apart = min(gap(palette[i], palette[j]) for i in range(symbols) for j in range(i + 1, symbols))
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


# --- following the row (format 1, docs/specs/29.md section 8) ---------------------------------
CAPTURE_SOURCE = Path(__file__).resolve().parent / "strip_capture.swift"


def frames_from(pipe):
    """The frames a capture stream writes (tools/strip_capture.swift): each "HLC1", width and
    height as 32-bit little-endian numbers, then the pixels. Yields bitmaps until the pipe
    ends; a frame cut short by the end is dropped; anything else is a ValueError."""
    while True:
        head = pipe.read(12)
        if len(head) < 12:
            return
        if head[:4] != b"HLC1":
            raise ValueError("not a capture frame")
        width, height = struct.unpack("<II", head[4:])
        if not (0 < width <= MAX_SIDE and 0 < height <= MAX_SIDE):
            raise ValueError("bad frame size %d x %d" % (width, height))
        data = pipe.read(width * height * 4)
        if len(data) < width * height * 4:
            return
        yield Bitmap.from_bgra(width, height, data)


def capture_tool(given=None):
    """The built capture stream: the one given, or one built from the source beside this file
    into the user's cache folder when it is missing or older than the source. Returns
    (path, None), or (None, why) when there is none: the caller then falls back to one
    `screencapture` a frame (docs/specs/29.md, section 8)."""
    if given:
        return (Path(given), None) if Path(given).is_file() else (None, "%s is not a file" % given)
    built = Path.home() / "Library" / "Caches" / "HelloLink" / "strip_capture"
    try:
        if not built.exists() or built.stat().st_mtime < CAPTURE_SOURCE.stat().st_mtime:
            built.parent.mkdir(parents=True, exist_ok=True)
            done = subprocess.run(["swiftc", "-O", "-swift-version", "5", str(CAPTURE_SOURCE), "-o", str(built)],
                                  capture_output=True, text=True)
            if done.returncode != 0:
                return None, "swiftc could not build it: " + done.stderr.strip()[-300:]
    except OSError as e:
        return None, "it could not be built: %s" % e
    return built, None


class CaptureFailed(OSError):
    """The capture process itself failed (not: it shows no row)."""


ONE_FRAME_WAIT = 3.0     # seconds for a capture's first frame
STOP_WAIT = 2.0          # seconds a capture process gets to stop by itself
STOPPED = (0, -15, -9)   # how a process that was told to stop may end: by itself, SIGTERM, SIGKILL


def stop(process):
    """Tells a capture process to stop: SIGTERM, then SIGKILL when it is still there after
    STOP_WAIT. It is asked first so that it can close its capture stream; a process that is
    killed cannot."""
    if process.poll() is None:
        process.terminate()
    try:
        process.wait(timeout=STOP_WAIT)
    except subprocess.TimeoutExpired:
        process.kill()


def ended(process, told: bool):
    """Waits for a capture process whose output is over, and returns (its error text, its
    exit code). `told`: the caller is the one who stops it (it left early, or gave up), so an
    end by SIGTERM or SIGKILL is no failure and comes back as 0. A process that ended its
    output by itself gets STOP_WAIT to leave by itself, so its own exit code stands; one that
    then stays is stopped, and that is a failure."""
    stuck = False
    if not told:
        try:
            process.wait(timeout=STOP_WAIT)
        except subprocess.TimeoutExpired:
            stuck = True
    if told or stuck:
        stop(process)
    error = process.stderr.read().decode("utf-8", "replace").strip()
    code = process.wait()
    if stuck:
        return error or "it did not leave after its output ended", code or 1
    return error, 0 if told and code in STOPPED else code


def one_frame(command):
    """The first frame a capture command gives; None when it ended cleanly without one. The
    process is always stopped. Raises CaptureFailed with the reason when the process failed,
    and when it gave no frame in ONE_FRAME_WAIT: a stream gives its first frame at once, also
    of a display where nothing moves, so silence means the capture service is not answering
    (seen 13 Nov 2026), and the caller falls back to `screencapture`."""
    try:
        shot = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    except OSError as e:
        raise CaptureFailed("%s could not be started: %s" % (command[0], e))
    frame = failed = None
    gave_up = threading.Event()

    def give_up():                       # in the timer's thread: the read below ends when the process does
        gave_up.set()
        stop(shot)

    patience = threading.Timer(ONE_FRAME_WAIT, give_up)
    patience.start()
    try:
        frame = next(frames_from(shot.stdout), None)
    except ValueError as e:
        failed = "bad output: %s" % e
    finally:
        late = gave_up.is_set()          # read before the timer is cancelled: what the read saw
        patience.cancel()
        took = frame is not None
        error, code = ended(shot, took or bool(failed) or gave_up.is_set())
        shot.stdout.close()
        shot.stderr.close()
    if failed or (not took and code != 0):
        raise CaptureFailed(failed or error or "exit %d" % code)
    if late:                             # also when a frame came after the limit: the limit holds
        raise CaptureFailed("no frame in %g s" % ONE_FRAME_WAIT)
    return frame


def locate(tool: Path):
    """Looks at one frame of each display for the row. Returns ((display, width, row), None),
    or (None, why) when no display shows it. Raises CaptureFailed when the tool fails."""
    import strip1
    try:
        listed = subprocess.run([str(tool), "list"], capture_output=True, text=True)
    except OSError as e:
        raise CaptureFailed("%s could not be started: %s" % (tool, e))
    if listed.returncode != 0:
        raise CaptureFailed(listed.stderr.strip() or "exit %d" % listed.returncode)
    displays = [tuple(int(v) for v in line.split()) for line in listed.stdout.splitlines() if line.strip()]
    if not displays:
        return None, "no display (are the displays asleep?)"
    for index, width, height in displays:
        # the row is 2 to 4 pixels high and sits at the top by default: the top 64 lines
        # first, then the whole display
        for lines in (64, height):
            frame = one_frame([str(tool), "stream", str(index), "0", "0", str(width), str(lines), "30", "1"])
            row = frame and strip1.read_row(frame)
            if row and row["grid"]:
                return (index, width, row), None
    return None, "no row on any display"


def stream_frames(command, idle: float):
    """Frames from a capture process, and None each time `idle` seconds pass without one (a
    stream gives a frame only when its rectangle changed). A thread reads the pipe. The
    generator ends when the process ends cleanly; when the caller stops early (close, break)
    the process is killed and the thread is told to stop and waited for. A process that
    fails, or output that is not frames, raises CaptureFailed with the reason."""
    import queue
    import threading
    try:
        process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    except OSError as e:
        raise CaptureFailed("%s could not be started: %s" % (command[0], e))
    frames, stop, end = queue.Queue(maxsize=8), threading.Event(), object()

    def hand(item):                      # a put that gives up when the reader has left
        while not stop.is_set():
            try:
                frames.put(item, timeout=0.1)
                return True
            except queue.Full:
                pass
        return False

    def pump():
        try:
            for frame in frames_from(process.stdout):
                if not hand(frame):
                    return
            hand(end)
        except ValueError as e:
            hand(e)

    thread = threading.Thread(target=pump, daemon=True)
    thread.start()
    failed, clean = None, False
    try:
        while True:
            try:
                item = frames.get(timeout=idle)
            except queue.Empty:
                yield None
                continue
            if item is end:
                clean = True
                break
            if isinstance(item, ValueError):
                failed = "bad output: %s" % item
                break
            yield item
    finally:
        stop.set()
        error, code = ended(process, not clean)   # the caller left, or the output was bad
        thread.join(timeout=2)
        process.stdout.close()
        process.stderr.close()
    if failed or code != 0:
        raise CaptureFailed(failed or error or "exit %d" % code)


def screencapture_frames(pause: float = 0.2):
    """The fall-back when there is no capture stream: one image a turn, of the display that
    shows the row. Until a display shows it, one `screencapture` takes every display and the
    first image with the row is given (with no row anywhere, the first display's, so that the
    reader counts one miss a turn); from then on only that display is captured, until the row
    leaves it. Slow (a few a second at best), so a reader on it cannot follow a short `dwell`.
    No screenshot outlives its read."""
    import time
    import strip1
    at = None                                # the display that shows the row, counted from 1
    while True:
        tmp = Path(tempfile.mkdtemp(prefix="hellolink-"))
        try:
            shots = {n: tmp / ("display%d.bmp" % n) for n in ([at] if at else range(1, 5))}
            subprocess.run(["screencapture", "-x", "-t", "bmp", *(["-D", str(at)] if at else []), *map(str, shots.values())],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
            images = [(n, Bitmap(s.read_bytes())) for n, s in shots.items() if s.exists()]   # a display keeps its number
        finally:
            shutil.rmtree(tmp)
        # ponytail: the row is searched for here and again by the reader; at a few images a
        # second that costs nothing that matters. Pass the row on if it ever does.
        shown = [(n, image) for n, image in images if (strip1.read_row(image) or {}).get("grid")]
        if shown:
            at, image = shown[0]
            yield image
        else:
            at = None
            yield images[0][1] if images else None
        time.sleep(pause)


def watch(args):
    """Follows the row and prints one line for each thing that is new. Stops at Ctrl-C."""
    import json
    import time
    import strip1
    if not 1 <= args.fps <= 120:
        sys.exit("--fps must be 1 to 120")

    def say(event):
        print(json.dumps(event, ensure_ascii=False, sort_keys=True), flush=True)

    def note(text):
        print(text, file=sys.stderr, flush=True)

    def handle(events):
        again = False
        for event in events:
            if event["kind"] == "ask" and args.addons:
                import hellolink
                hellolink.write(args.addons, "", event["session"], quiet=True)
                note("asked the strip of session %d to fall back to 3 bits a square" % event["session"])
            if event["kind"] == "relocate":
                again = True
            if args.json or event["kind"] != "state":
                say(event)
            else:
                unknown = " ".join(k for k, v in event["fast"].items() if v is None)
                print("seq %d  depth %d  %s%s" % (event["seq"], event["depth"],
                      " ".join("%s=%s" % (k, "-" if v is None else v) for k, v in event["levels"].items()),
                      unknown and "  unknown: " + unknown or ""), flush=True)
        return again

    watcher = strip1.Watcher()   # one for the whole run: it remembers a session across a new search

    def by_screencapture(why):
        note("no capture stream (%s): one screencapture a frame from here on, which is slow" % why)
        watcher.hint = None      # a place found in a stream's rectangle is not a place on a display
        for frame in screencapture_frames():
            now = time.monotonic()
            handle(watcher.feed(frame, now) if frame is not None else watcher.idle(now))

    tool, why = capture_tool(args.capture)
    if tool is None:
        return by_screencapture(why)
    waiting = None
    try:
        while True:
            found, why = locate(tool)
            if not found:
                if why != waiting:
                    say({"kind": "waiting", "why": why})
                    waiting = why
                handle(watcher.idle(time.monotonic()))
                time.sleep(2)
                continue
            waiting = None
            display, width, row = found
            x0, top, side = row["grid"]
            left, upper = max(0, int(x0) - 2), max(0, int(top) - 1)
            lines = int(side + 0.999) + 2
            watcher.hint = None      # the place is given in the new rectangle's own pixels
            command = [str(tool), "stream", str(display), str(left), str(upper), str(width - left), str(lines), str(args.fps)]
            stream = stream_frames(command, 0.5)
            try:
                for frame in stream:
                    now = time.monotonic()
                    if handle(watcher.feed(frame, now) if frame is not None else watcher.idle(now)):
                        break                  # look for the row again
            finally:
                stream.close()                 # stops the process and its reader thread
            time.sleep(0.2)                    # a row that is gone is not searched for in a tight loop
    except CaptureFailed as e:
        return by_screencapture("the capture stream failed: %s" % e)


def rows_of_images(images, step: float):
    """Format 1 (tools/strip1.py): reads the row of each image in turn, as captures `step`
    seconds apart, and prints one JSON line an image: what the row holds, and an object when
    one completes."""
    import json
    import strip1
    joiner = strip1.Assembler()
    for i, path in enumerate(images):
        row = strip1.read_row(Bitmap(path.read_bytes()))
        if row is None:
            print(json.dumps({"i": i, "row": False}))
            continue
        frame, done = row["frame"], None
        if frame is not None:
            done = joiner.feed(frame, i * step)
        chunk = frame and frame["chunk"]
        print(json.dumps({
            "i": i, "row": True, "session": row["session"], "depth": row["depth"], "levels": row["levels"],
            "why": row["why"], "apart": row["apart"], "square": row["square"],
            "seq": frame and frame["seq"], "dwell": frame and frame["dwell"], "fast": frame and frame["fast"],
            "chunk": chunk and [chunk[0], chunk[1], chunk[2], chunk[3], len(chunk[4])],
            "object": done and list(done)}, ensure_ascii=False, sort_keys=True))


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
    f = sub.add_parser("watch")
    f.add_argument("--json", action="store_true", help="every event as a JSON line")
    f.add_argument("--fps", type=int, default=60, help="captures a second asked of the stream")
    f.add_argument("--addons", type=Path, help="the game's AddOns folder: lets the reader ask the strip to fall back")
    f.add_argument("--capture", help="a built strip_capture, instead of building tools/strip_capture.swift")
    w = sub.add_parser("rows")
    w.add_argument("images", type=Path, nargs="+")
    w.add_argument("--step", type=float, default=0.1)
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
    if args.cmd == "watch":
        try:
            watch(args)
        except KeyboardInterrupt:
            pass
        return
    if args.cmd == "rows":
        rows_of_images(args.images, args.step)
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
            import math
            print("depth %d levels (%.4g bits a square), %d px: %d of %d wrong; the nearest two colours came back %d apart"
                  % (levels, 3 * math.log2(levels), w, wrong, DEPTH_N, apart))
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
