#!/usr/bin/env python3
"""The live-state strip, format 1 (docs/specs/29.md): the format and nothing else.

No file, no screen, no clock: every function takes values and returns values. The addon's
side is HelloLink/Strip.lua; this module is the reference for what it draws and the reader
of what it drew. Section numbers below are those of the spec.
"""
import math
import re
import zlib

VERSION = 1
FINDER = bytes([4, 2, 1, 7, 0, 6, 3, 5])
FINDER_RE = re.compile(b"".join(b"(" + re.escape(bytes([c])) + b"+)" for c in FINDER))
LEVEL_NAMES = ("health", "power", "targetHealth", "petHealth")
LEVELS_AT, DEPTH_AT, SESSION_AT, PALETTE_AT = 8, 20, 21, 27  # in squares from the row's start
MAX_CHUNKS, MAX_CHUNK = 12, 255
MIN_SQUARE = 2  # pixels a square in the capture, below which a reader refuses the row

# Section 5: the groups of the fast block in order, each a list of (field, bytes).
GROUPS = (
    ("clock", (("clock", 2),)),
    ("health", (("healthMax", 3),)),
    ("power", (("powerMax", 3), ("powerType", 1))),
    ("level", (("level", 1), ("xp", 3), ("xpMax", 3))),
    ("state", (("flags", 2),)),
    ("cast", (("spell", 3), ("tenths", 1))),
    ("target", (("level", 1), ("flags", 1), ("nameHash", 2))),
    ("pet", (("healthMax", 3),)),
    ("position", (("map", 2), ("x", 2), ("y", 2), ("facing", 1))),
    ("purse", (("money", 4), ("bagFree", 1))),
    ("hand", (("item", 3), ("enchant", 2))),
    ("loot", (("counter", 1), ("item", 3), ("quantity", 1))),
    ("uiError", (("error", 2), ("counter", 1))),
    ("threat", (("player", 1), ("pet", 1))),
)
FAST_LEN = 2 + sum(size for _, fields in GROUPS for _, size in fields)


def check(data: bytes) -> bytes:
    """Section 7: two sums modulo 255, written s1 then s2."""
    s1 = s2 = 0
    for b in data:
        s1 = (s1 + b) % 255
        s2 = (s2 + s1) % 255
    return bytes((s1, s2))


# --- the fast block (section 5) -----------------------------------------------------------

def pack_fast(state: dict) -> bytes:
    """`state` maps a group's name to a dict of its fields; a missing group or None is unknown.
    A number larger than its field holds is sent as the field's largest value."""
    known, body = 0, bytearray()
    for i, (name, fields) in enumerate(GROUPS):
        values = state.get(name)
        if values is not None:
            known |= 0x8000 >> i
        for field, size in fields:
            value = 0 if values is None else int(values[field])
            body += max(0, min(value, 256 ** size - 1)).to_bytes(size, "big")
    return known.to_bytes(2, "big") + bytes(body)


def unpack_fast(data: bytes) -> dict:
    """The groups this reader knows; bytes after them (a later version's) are skipped."""
    if len(data) < FAST_LEN:
        raise ValueError("fast block of %d bytes, version 1 has %d" % (len(data), FAST_LEN))
    known, at, out = int.from_bytes(data[:2], "big"), 2, {}
    for i, (name, fields) in enumerate(GROUPS):
        values = {}
        for field, size in fields:
            values[field] = int.from_bytes(data[at:at + size], "big")
            at += size
        out[name] = values if known & (0x8000 >> i) else None
    return out


# --- the frame (section 4) ----------------------------------------------------------------

def pack_frame(session: int, seq: int, dwell: int, fast: bytes, chunk=None) -> bytes:
    """`chunk` is None or (objectId, objectVersion, chunkIndex, chunkCount, bytes)."""
    head = bytes((VERSION,)) + session.to_bytes(2, "big") + bytes((dwell,)) + (seq % 65536).to_bytes(2, "big") + bytes((len(fast),))
    if chunk is None:
        part = bytes(6)
    else:
        oid, version, index, count, data = chunk
        if not (1 <= len(data) <= MAX_CHUNK and 1 <= count <= MAX_CHUNKS and 0 <= index < count and 1 <= oid <= 255):
            raise ValueError("bad chunk")
        part = bytes((oid,)) + (version % 65536).to_bytes(2, "big") + bytes((index, count, len(data))) + data
    body = head + fast + part
    return body + check(body)


def frame_length(prefix: bytes):
    """The whole frame's length in bytes once enough of it is read, else how many bytes are
    needed to know more. Returns (length, enough)."""
    if len(prefix) < 7:
        return 7, False
    at = 7 + prefix[6] + 6  # the end of the object header
    if len(prefix) < at:
        return at, False
    return at + prefix[at - 1] + 2, True


def unpack_frame(data: bytes) -> dict:
    """The frame's fields, or ValueError: a reader reports nothing from a frame that fails."""
    length, enough = frame_length(data)
    if not enough or len(data) < length:
        raise ValueError("frame cut short")
    data = data[:length]
    if data[0] != VERSION:
        raise ValueError("unknown version %d" % data[0])
    if check(data[:-2]) != data[-2:]:
        raise ValueError("frame check failed")
    fast_len = data[6]
    at = 7 + fast_len
    oid, version, index, count, size = data[at], int.from_bytes(data[at + 1:at + 3], "big"), data[at + 3], data[at + 4], data[at + 5]
    chunk = None
    if oid == 0:
        if any(data[at:at + 6]):
            raise ValueError("object id 0 with other fields set")
    else:
        if not (1 <= size and 1 <= count <= MAX_CHUNKS and index < count):
            raise ValueError("bad object part")
        chunk = (oid, version, index, count, data[at + 6:at + 6 + size])
    session = int.from_bytes(data[1:3], "big")
    dwell = data[3]
    if session == 0 or not 5 <= dwell <= 100:
        raise ValueError("bad session or dwell")
    return {"version": data[0], "session": session, "seq": int.from_bytes(data[4:6], "big"), "dwell": dwell,
            "fast": unpack_fast(data[7:at]), "chunk": chunk}


# --- objects (section 6) ------------------------------------------------------------------

def pack_object(text, compress: bool = True) -> bytes:
    """The object bytes for a text; None gives format 255 (the addon cannot read it now)."""
    if text is None:
        body = bytes((255,))
    else:
        raw = text.encode("utf-8")
        if compress:
            squeezer = zlib.compressobj(9, zlib.DEFLATED, -15)
            body = bytes((1,)) + squeezer.compress(raw) + squeezer.flush()
        else:
            body = bytes((0,)) + raw
    return body + check(body)


def chunks_of(obj: bytes, chunk_len: int):
    """The object's chunks at this chunk length; a larger object becomes format 254."""
    if len(obj) > MAX_CHUNKS * chunk_len:
        obj = bytes((254,)) + check(bytes((254,)))
    return [obj[i:i + chunk_len] for i in range(0, len(obj), chunk_len)]


def unpack_object(obj: bytes):
    """(format, text): the text for formats 0 and 1, None for 254 and 255. ValueError if the
    object check fails or the format is unknown."""
    if len(obj) < 3 or check(obj[:-2]) != obj[-2:]:
        raise ValueError("object check failed")
    kind, content = obj[0], obj[1:-2]
    if kind in (254, 255):
        if content:
            raise ValueError("format %d with content" % kind)
        return kind, None
    if kind == 0:
        try:
            return 0, content.decode("utf-8")
        except UnicodeDecodeError as e:
            raise ValueError("object is not UTF-8: %s" % e)
    if kind == 1:
        try:
            raw = zlib.decompress(content, -15)      # a raw Deflate stream
        except zlib.error:
            try:
                raw = zlib.decompress(content)       # or one with a zlib header
            except zlib.error as e:
                raise ValueError("object does not inflate: %s" % e)
        try:
            return 1, raw.decode("utf-8")
        except UnicodeDecodeError as e:
            raise ValueError("object is not UTF-8: %s" % e)
    raise ValueError("unknown object format %d" % kind)


class Assembler:
    """Section 6, 'Which chunks belong together': builds objects from consecutive chunks."""

    def __init__(self):
        self.session = None
        self.partial = None   # (key, [chunks], the time by which the next chunk must come)
        self.last = None      # the object part accepted last, to know a repeat
        self.objects = {}     # objectId -> (version, format, text, when it was last seen whole)

    def feed(self, frame: dict, now: float):
        """Takes a frame that passed its check; returns (objectId, format, text) when a new
        version of an object completes, else None. A version seen whole again only renews
        the time in `objects`."""
        if frame["session"] != self.session:
            self.session, self.partial, self.last, self.objects = frame["session"], None, None, {}
        # The limit was set when the last chunk was accepted, from that frame's dwell: a later
        # frame with a longer dwell cannot stretch it.
        limit = now + 5 * frame["dwell"] / 100
        if self.partial and now > self.partial[2]:
            self.partial = None
        chunk = frame["chunk"]
        if chunk == self.last:
            return None  # the same chunk again: not progress
        self.last = chunk
        if chunk is None:
            self.partial = None
            return None
        oid, version, index, count, data = chunk
        key = (oid, version, count)
        if index == 0:
            self.partial = (key, [data], limit)
        elif self.partial and self.partial[0] == key and len(self.partial[1]) == index:
            self.partial = (key, self.partial[1] + [data], limit)
        else:
            self.partial = None
            return None
        if len(self.partial[1]) < count:
            return None
        whole, self.partial = b"".join(self.partial[1]), None
        try:
            kind, text = unpack_object(whole)
        except ValueError:
            return None
        fresh = oid not in self.objects or self.objects[oid][0] != version
        self.objects[oid] = (version, kind, text, now)
        return (oid, kind, text) if fresh else None


# --- bytes and squares (section 3, 'Bytes to squares') -------------------------------------

def bytes_to_squares(data: bytes, bits: int):
    stream = "".join(format(b, "08b") for b in data)
    stream += "0" * (-len(stream) % bits)
    return [int(stream[i:i + bits], 2) for i in range(0, len(stream), bits)]


def squares_to_bytes(squares, bits: int, count: int) -> bytes:
    stream = "".join(format(s, "0%db" % bits) for s in squares)
    return bytes(int(stream[i * 8:i * 8 + 8], 2) for i in range(count))


def squares_for(count: int, bits: int) -> int:
    return -(-count * 8 // bits)


def digit_colour(d: int):
    return (d >> 2 & 1, d >> 1 & 1, d & 1)


def palette_colour(i: int):
    return (i // 16 / 3, i // 4 % 4 / 3, i % 4 / 3)


def level_digits(per_cent):
    """The three digits of a level square triple for a per cent (0 to 1), or black for None."""
    if per_cent is None:
        return (0, 0, 0)
    level = min(127, math.floor(per_cent * 128))
    return (level // 16, level // 2 % 8, 6 if level % 2 else 2)


def row_colours(session: int, depth: int, levels, frame: bytes):
    """The row as (red, green, blue) from 0 to 1 a square: what the addon draws (section 3).
    `levels` is four per cents (0 to 1) or None, in the order of LEVEL_NAMES."""
    digits = list(FINDER)
    for value in levels:
        digits += level_digits(value)
    digits.append(depth)
    digits += bytes_to_squares((session & 0xFFFF).to_bytes(3, "big"), 3)[2:]  # 18 bits, six digits
    out = [digit_colour(d) for d in digits]
    if depth == 4:
        out += [palette_colour(i) for i in range(64)]
        out += [palette_colour(i) for i in bytes_to_squares(frame, 6)]
    else:
        out += [digit_colour(d) for d in bytes_to_squares(frame, 3)]
    return out


# --- reading a row from a bitmap (sections 3, 5 and 8) -------------------------------------

def read_row(bmp):
    """The first row found in the bitmap, or None. `bmp` has width, height, digits(y),
    digit(x, y) and rgb(x, y), as tools/hellolink_strip.Bitmap.

    Returns a dict: `session` (from the two-level squares), `depth`, `levels` (per cent 0 to
    100 or None for each of LEVEL_NAMES), `frame` (the unpacked frame, or None when no width
    gave a frame that passes its check), `why` (the reason when `frame` is None; a row whose
    squares are under 2 pixels in the capture has only `why` and `square`), `apart`
    (depth 4: how far apart the nearest two palette colours came back), `square` (its side
    in pixels) and `box` (left, top, right, bottom of what was read, for later captures)."""
    for y in range(bmp.height):
        for m in FINDER_RE.finditer(bmp.digits(y)):
            measured = (m.start(8) - m.start(2)) / 6
            runs = [m.end(i) - m.start(i) for i in range(2, 8)]
            if measured < 1 or any(abs(r - measured) > max(1, measured / 4) for r in runs):
                continue
            top = y
            while top > 0 and all(bmp.digit(m.start(2) + (i - 0.5) * measured, top - 1) == FINDER[i] for i in range(8)):
                top -= 1
            best = None
            refused = {"session": None, "depth": None, "levels": [None] * len(LEVEL_NAMES), "frame": None,
                       "why": "squares of about %.1f pixels: under %d pixels a square the row is not read" % (measured, MIN_SQUARE),
                       "apart": None, "square": measured, "box": None}
            # A square under 2 pixels leaves a quarter of a pixel between reading it and reading
            # its neighbour: such a row is refused, not guessed. Six squares give the width to
            # a sixth of a pixel, so well under 2 is refused here and every width tried below
            # must be 2 or more.
            if measured < MIN_SQUARE - 0.25:
                return refused
            # Section 3, 'Scale'. First the grid that fits the edges between squares along the
            # whole row, which gives the width far better than eight squares do; then the
            # widths and origins around the measured one, nearest first.
            line = int(top + measured / 2)
            tries = _fit(_edges(bmp, line, m.start(2)), m) if line < bmp.height else []
            for k in range(1, 61):
                wide = measured + (k + 1) // 2 * 0.01 * (1 if k % 2 else -1)
                tries += [(m.start(2) - wide + shift, wide) for shift in (0, -0.5, 0.5)]
            for x0, w in tries:
                if w < MIN_SQUARE - 0.005:  # 2 pixels, less what a fitted width can be short of it
                    continue
                found = _row_at(bmp, x0, top, w)
                if found is None:
                    continue
                if found["frame"] is not None:
                    return found
                best = best or found
            if best:
                return best
            if measured < MIN_SQUARE:
                return refused
    return None


def _edges(bmp, line: int, start: int):
    """Where the colour changes along a line of the bitmap, from `start` on: the pixels whose
    red, green or blue differs from the pixel before by 20 or more. The full colours are
    compared, not the two-level digits: at depth 4 two neighbouring squares can differ in a
    way the digits do not show."""
    out, before = [], bmp.rgb(start - 1, line) if start > 0 else None
    for x in range(start, bmp.width):
        now = bmp.rgb(x, line)
        if before is not None and max(abs(now[0] - before[0]), abs(now[1] - before[1]), abs(now[2] - before[2])) >= 20:
            out.append(x)
        before = now
    return out


def _fit(edges, m):
    """The origins and square widths (two candidates) that best fit the edges between squares
    along a line (`edges`, from `_edges`). `m` is the finder's match. Fewer than eight edges
    give nothing.

    Every change of colour on the row is an edge at `x0 + k * w` for some whole k. For the
    right `w` the edges all have the same position within a square; for a wrong one they are
    spread. So the width is the one for which the sum of `exp(2 pi i x / w)` over the edges
    is longest. It is searched in three passes, each over more edges and a narrower range:
    40 edges settle it roughly, 160 better, all of them finely. The finder's eight squares
    alone give it to a tenth at best, and a row is hundreds of squares long."""
    if len(edges) < 8:
        return []
    w = (m.start(8) - m.start(2)) / 6
    reach = 0.2 * w
    for count in (40, 160, len(edges)):
        some = edges[:count]
        span = max(some[-1] - some[0], 1)
        step = w * w / (4 * span)
        best, best_w = -1.0, w
        steps = int(reach / step) + 1
        for n in range(-steps, steps + 1):
            cand = w + n * step
            if cand <= 0:
                continue
            turn = 2 * math.pi / cand
            score = abs(sum(complex(math.cos(turn * x), math.sin(turn * x)) for x in some))
            if score > best:
                best, best_w = score, cand
        w, reach = best_w, 6 * step  # the next pass looks well to both sides of this one's best
        if count >= len(edges):
            break
    # Edges sit on whole pixels, so a width w and the width w / (w - 1) line them up equally
    # well (one turns once a square, the other once a pixel less that). Both are returned;
    # the frame check tells them apart.
    out = []
    for width in (w, w / (w - 1) if w > 1 else w):
        turn = 2 * math.pi / width
        total = sum(complex(math.cos(turn * x), math.sin(turn * x)) for x in edges)
        phase = math.atan2(total.imag, total.real) / turn      # where an edge falls, modulo the width
        near = m.start(2) - width                                # the row's left edge, roughly
        out.append((phase + round((near - phase) / width) * width, width))
    return out


def _row_at(bmp, x0: float, top: int, w: float):
    mid = top + w / 2

    def digit(i):
        return bmp.digit(x0 + (i + 0.5) * w, mid)

    head = [digit(i) for i in range(PALETTE_AT)]
    if None in head or head[:8] != list(FINDER) or head[DEPTH_AT] not in (2, 4):
        return None
    depth = head[DEPTH_AT]
    session = int("".join(format(d, "03b") for d in head[SESSION_AT:PALETTE_AT]), 2)
    levels = []
    for v in range(len(LEVEL_NAMES)):
        a, b, c = head[LEVELS_AT + 3 * v:LEVELS_AT + 3 * v + 3]
        levels.append(round(100 * (a * 16 + b * 2 + (c == 6)) / 127) if c in (2, 6) else None)
    out = {"session": session, "depth": depth, "levels": levels, "frame": None, "why": None, "apart": None,
           "square": w, "box": None}
    if session == 0:
        return None
    bits = 3
    first = PALETTE_AT
    if depth == 4:
        palette = [bmp.rgb(x0 + (PALETTE_AT + i + 0.5) * w, mid) for i in range(64)]
        if None in palette:
            return None
        out["apart"] = min(max(abs(p[0] - q[0]), abs(p[1] - q[1]), abs(p[2] - q[2]))
                           for i, p in enumerate(palette) for q in palette[i + 1:])
        bits, first = 6, PALETTE_AT + 64

        def square(i):
            c = bmp.rgb(x0 + (first + i + 0.5) * w, mid)
            if c is None:
                return None
            return min(range(64), key=lambda n: (c[0] - palette[n][0]) ** 2 + (c[1] - palette[n][1]) ** 2 + (c[2] - palette[n][2]) ** 2)
    else:
        def square(i):
            return digit(first + i)

    have, need = [], 7
    while True:
        while len(have) < squares_for(need, bits):
            s = square(len(have))
            if s is None:
                out["why"] = "the row runs off the image"
                return out
            have.append(s)
        need, enough = frame_length(squares_to_bytes(have, bits, need))
        if enough:
            break
        if need > 7 + 255 + 6:
            out["why"] = "frame check failed"
            return out
    if need > 7 + 255 + 6 + MAX_CHUNK + 2:
        out["why"] = "frame check failed"
        return out
    while len(have) < squares_for(need, bits):
        s = square(len(have))
        if s is None:
            out["why"] = "the row runs off the image"
            return out
        have.append(s)
    try:
        frame = unpack_frame(squares_to_bytes(have, bits, need))
    except ValueError as e:
        out["why"] = str(e)
        return out
    if frame["session"] != session:
        out["why"] = "the frame's session is not the row's"
        return out
    out["frame"] = frame
    out["box"] = (round(x0), top, round(x0 + (first + len(have)) * w) + 1, round(top + w) + 1)
    return out


class Quality:
    """Section 3, 'Falling back': when a reader asks the addon for depth 2."""

    def __init__(self):
        self.recent = []      # True for a depth-4 frame that passed, False for one that did not
        self.ever = False     # a depth-4 frame was read at least once

    def note(self, row: dict):
        """Takes what read_row returned; True when the reader should ask for depth 2."""
        if row is None or row["depth"] != 4:
            return False
        ok = row["frame"] is not None
        self.ever = self.ever or ok
        self.recent = (self.recent + [ok])[-200:]
        if row["apart"] is not None and row["apart"] < 12:
            return True
        if not self.ever:
            return len(self.recent) >= 200
        return len(self.recent) >= 200 and self.recent.count(False) > 4
