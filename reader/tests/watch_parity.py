#!/usr/bin/env python3
"""Writes the Watcher's parity fixtures, reader/hellolink/tests/watch/: sequences of captures
and idle turns, with the events and the record the Python reader makes of them.

    python3 reader/tests/watch_parity.py      # from the repository's top; Python 3.14

For each sequence NAME it writes NAME.steps.jsonl (one step a line: the time and a capture,
or an idle turn), NAME.events (one line an event: the step's index, a space, the event as
json.dumps(..., ensure_ascii=False, sort_keys=True)) and NAME.record.jsonl (what the
Recorder wrote). The Rust test (hellolink/tests/watch_parity.rs) builds the same captures,
feeds them to its Watcher and Recorder, and must write the same bytes.

A step is {"t": T} with one of:
  "idle": true                      no capture came: Watcher.idle(T)
  "blank": true                     a capture of 2560 x 4 black pixels
  "shot": {session, depth, levels, frame (hex), bend, width}
                                    the capture of tests/strip_watch_test.py: the row's squares
                                    from x = 2 drawn on 2560 x 4, `width` columns kept, each
                                    pixel bent ("crush", "darker" or null)
  "cells": NAME/row_N.txt, "scale": S
                                    a cells file of hellolink/tests/fixtures, drawn on 2560 x 12
The sequences come from the builders of tests/strip_watch_test.py and
tests/strip_record_test.py, and one mixed at random with a fixed seed.
"""
import json
import random
import shutil
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
import hellolink_strip as hs  # noqa: E402
import strip1 as s1         # noqa: E402

OUT = ROOT / "reader" / "hellolink" / "tests" / "watch"
CELLS = ROOT / "reader" / "hellolink" / "tests" / "fixtures"
STARTED = 1794516378.0 + 1 / 256   # Python writes ...0039062, Rust's shortest text ...0039063 (#197)
STATE = {"clock": {"clock": 1}, "health": {"healthMax": 1158}}
LEVELS = [0.75, 1.0, None, None]
BENDS = {
    None: None,
    "crush": lambda c: tuple(255 if v > 127 else 0 for v in c),
    "darker": lambda c: tuple(max(0, v - 6) for v in c),
}
tmp = Path(tempfile.mkdtemp(prefix="watch-parity-"))


def capture(shot):
    cells = s1.row_colours(shot["session"], shot["depth"], shot["levels"], bytes.fromhex(shot["frame"]))
    (tmp / "cells.txt").write_text("".join("%d 1 2 2 %.6f %.6f %.6f\n" % (2 + i * 2, r, g, b)
                                           for i, (r, g, b) in enumerate(cells)))
    hs.render(tmp / "cells.txt", tmp / "shot.bmp", 1.0, 0, 0, 2560, 4)
    bmp = hs.Bitmap((tmp / "shot.bmp").read_bytes())
    bend, raw = BENDS[shot["bend"]], bytearray()
    for y in range(4):
        for x in range(shot["width"]):
            c = bmp.rgb(x, y)
            r, g, b = bend(c) if bend else c
            raw += bytes((b, g, r, 255))
    return hs.Bitmap.from_bgra(shot["width"], 4, bytes(raw))


def image(step, cache={}):
    key = json.dumps(step, sort_keys=True)
    if key not in cache:
        if "blank" in step:
            cache[key] = hs.Bitmap.from_bgra(2560, 4, bytes(2560 * 4 * 4))
        elif "cells" in step:
            hs.render(CELLS / step["cells"], tmp / "cells.bmp", step["scale"], 0, 0, 2560, 12)
            cache[key] = hs.Bitmap((tmp / "cells.bmp").read_bytes())
        else:
            cache[key] = capture(step["shot"])
    return cache[key]


def shot(t, seq, session=4711, depth=4, levels=LEVELS, chunk=None, dwell=10, state=STATE, bend=None,
         width=2560, frame=None):
    if frame is None:
        frame = s1.pack_frame(session, seq, dwell, s1.pack_fast(state), chunk)
    return {"t": t, "shot": {"session": session, "depth": depth, "levels": list(levels), "frame": frame.hex(),
                             "bend": bend, "width": width}}


def idle(*times):
    return [{"t": t, "idle": True} for t in times]


def blanks(t0, n, dt):
    return [{"t": t0 + i * dt, "blank": True} for i in range(n)]


# --- the sequences ---------------------------------------------------------------------------

def basics():
    """tests/strip_watch_test.py, 'the Watcher': state, levels, an object, lost, found, a session."""
    out = [shot(0.0, 1), shot(0.02, 1), shot(0.04, 1, levels=(0.5, 1.0, None, None)), shot(0.06, 2)]
    text = '{"map": 1437, "zone": "Wetlands", "sub": ""}'
    parts = s1.chunks_of(s1.pack_object(text, False), 20)
    for i, part in enumerate(parts):
        out += [shot(0.1 + i * 0.1, 3 + i, chunk=(3, 500, i, len(parts), part))] * 3
    out += blanks(1.0, 40, 0.02) + [shot(2.0, 2), shot(2.1, 1, session=4712)]
    return out


def time_alone():
    """'what time makes old': stale, the search every 3 s, stale and fresh objects, dwell 0.2 s."""
    single = (3, 9, 0, 1, s1.pack_object("{}", False))
    out = [shot(0.1 * i, 1) for i in range(30)] + [shot(3.2, 1), shot(3.4, 1)] + idle(4.0)
    out += [shot(5.0, 2)] + idle(8.5, 9.0, 12.0, 15.5)
    out += [shot(16.0, 3, chunk=single)] + idle(37.0, 38.0, 60.0, 98.0, 98.9, 99.5)
    out += [shot(100.0, 4, chunk=single)] + idle(184.0)
    wrong = bytearray(single[4])
    wrong[-1] ^= 1
    out += [shot(185.0, 5, chunk=(2, 1, 0, 1, s1.pack_object("null", False))),
            shot(185.2, 6, chunk=(3, 9, 0, 1, bytes(wrong))), shot(185.4, 7, chunk=(3, 9, 0, 1, bytes(wrong)))]
    out += [shot(186.0, 8, chunk=single, dwell=20)] + idle(300.0, 351.0, 352.0, 352.5)
    return out


def never():
    return idle(0.0, 2.0, 3.5, 5.0, 7.0, 60.0)


def fallback():
    """'one Watcher for the whole run' and 'asking for the fall-back'."""
    wrong = s1.pack_frame(4999, 1, 10, s1.pack_fast(STATE))
    out = [shot(i * 0.02, 1, frame=wrong) for i in range(205)]
    out += [shot(5.0 + i * 0.02, 1 + i, bend="crush") for i in range(5)]
    out += [shot(6.0 + i * 0.02, 1 + i, bend="crush", session=4712) for i in range(5)]
    return out


def rate():
    """The fall-back after good reads: 196 good frames, then 5 that fail. Of the last 200 more
    than 4 must fail: no ask at frame 200, an ask at 201 (#197)."""
    wrong = s1.pack_frame(4999, 1, 10, s1.pack_fast(STATE))
    return [shot(i * 0.02, 1) for i in range(196)] + [shot(i * 0.02, 1, frame=wrong) for i in range(196, 201)]


def record():
    """tests/strip_record_test.py: the ten captures of its record."""
    one, two = (s1.pack_frame(4711, n, 10, s1.pack_fast(STATE)) for n in (1, 2))
    bad = bytearray(two)
    bad[8] ^= 0x01
    half = (0.5, 1.0, None, None)
    out = [shot(0.0, 0, frame=one), shot(0.016, 0, frame=one), shot(0.032, 0, frame=one, levels=half),
           shot(0.048, 0, frame=two), shot(0.064, 0, frame=two, bend="darker"), shot(0.08, 0, frame=bytes(bad)),
           shot(0.096, 0, frame=bytes(bad), depth=2, levels=(0.25, 1.0, None, None)),
           shot(0.112, 0, frame=two, width=300), shot(0.128, 0, frame=two, levels=half, width=100),
           {"t": 0.144, "blank": True}]
    return [dict(s, t=100.0 + s["t"]) for s in out]


def cells():
    """The addon's own rows: the cells files of the step 1 fixtures, 0.1 s apart."""
    out, t = [], 0.0
    for name in ("objects", "depth2", "runs-off", "fitted"):
        scale = float((CELLS / name / "args").read_text().split()[0])
        for path in sorted((CELLS / name).glob("row_*.txt"), key=lambda p: int(p.stem[4:])):
            out.append({"t": round(t, 3), "cells": "%s/%s" % (name, path.name), "scale": scale})
            t += 0.1
    return out


def mixed():
    """Everything at once, at random with a fixed seed: new and repeated seqs, levels, objects in
    chunks (format 0 and 1, some chunks lost), failing frames, no row, idle gaps, depth 2, a
    darker or crushed palette, a row cut short, other sessions and dwells."""
    rnd = random.Random(195)
    texts = ['{"zone": "Dun Morogh", "sub": "Kharanos"}', "café — naïve ☃ 雪", "x" * 300,
             json.dumps({"bags": [[i, i * 7, i % 3] for i in range(40)]}), None]
    objects = [(oid, rnd.choice(texts), rnd.choice((0, 1))) for oid in (1, 2, 5, 9)]
    version = {oid: 1 for oid, _, _ in objects}
    out, t, seq, session, dwell, depth = [], 0.0, 1, 4711, 10, 4
    levels, health = list(LEVELS), 1158
    pending = []                        # the chunks of the object being sent
    for _ in range(320):
        t += rnd.choice((0.016, 0.016, 0.02, 0.05, 0.1, 0.1, 0.3, 1.0, 3.5, 4.0, 30.0, 90.0))
        t = round(t, 3)
        roll = rnd.random()
        if roll < 0.08:
            out += idle(t)
            continue
        if roll < 0.12:
            out.append({"t": t, "blank": True})
            continue
        if roll < 0.14:
            session = rnd.choice((4711, 4712, 300, 65535))
        if roll > 0.97:
            dwell = rnd.choice((5, 10, 20, 100))
        if rnd.random() < 0.06:
            depth = 2 if depth == 4 else 4
        if rnd.random() < 0.5:
            seq = (seq + rnd.choice((1, 1, 2, 65535))) % 65536
        if rnd.random() < 0.1:
            levels[rnd.randrange(4)] = rnd.choice((None, 0.0, 0.25, 0.5, 0.99, 1.0))
        if rnd.random() < 0.2:
            health = rnd.choice((0, 1158, 99999, 2 ** 24))
        if not pending:
            oid, text, compress = rnd.choice(objects)
            if rnd.random() < 0.3:
                version[oid] = (version[oid] + 1) % 65536
            size = rnd.choice((20, 40, 60))
            parts = s1.chunks_of(s1.pack_object(text, compress == 1), size)
            pending = [(oid, version[oid], i, len(parts), p) for i, p in enumerate(parts)]
        chunk = pending.pop(0) if rnd.random() < 0.8 else None
        if chunk and rnd.random() < 0.05:
            chunk = pending.pop(0) if pending else chunk     # one lost
        state = {"clock": {"clock": seq}, "health": {"healthMax": health}, "power": {"powerMax": 100, "powerType": 0}}
        frame = bytearray(s1.pack_frame(session, seq, dwell, s1.pack_fast(state), chunk))
        if rnd.random() < 0.05:
            frame[rnd.randrange(len(frame))] ^= 1 << rnd.randrange(8)   # read wrong
        bend = rnd.choice((None,) * 18 + ("darker", "crush"))
        width = 300 if rnd.random() < 0.03 else 2560
        out.append(shot(t, seq, session=session, depth=depth, levels=levels, frame=bytes(frame), bend=bend,
                        width=width))
    return out


SEQUENCES = {"basics": basics, "time": time_alone, "never": never, "fallback": fallback, "rate": rate, "record": record,
             "cells": cells, "mixed": mixed}


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for name, make in SEQUENCES.items():
        steps = make()
        (OUT / ("%s.record.jsonl" % name)).unlink(missing_ok=True)   # the Recorder appends
        watcher, record = s1.Watcher(), hs.Recorder(OUT / ("%s.record.jsonl" % name), started=STARTED)
        watcher.on_row = record.note
        lines = []
        for i, step in enumerate(steps):
            if step.get("idle"):
                events = watcher.idle(step["t"])
            else:
                events = watcher.feed(image(step), step["t"])
            lines += ["%d %s" % (i, json.dumps(e, ensure_ascii=False, sort_keys=True)) for e in events]
        record.close()
        (OUT / ("%s.steps.jsonl" % name)).write_text("".join(json.dumps(s, ensure_ascii=False) + "\n" for s in steps))
        (OUT / ("%s.events" % name)).write_text("".join(line + "\n" for line in lines))
        print("%s: %d steps, %d events" % (name, len(steps), len(lines)))
    shutil.rmtree(tmp, ignore_errors=True)


main()
