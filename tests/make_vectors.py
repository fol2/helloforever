#!/usr/bin/env python3
"""Writes the test vectors of docs/STRIP.md into tests/vectors/: one state, the frame's bytes,
and the row as an image at depth 4 and at depth 2. Run it only when the format changes; the
files are committed, and tests/strip1_test.py reads them back.

    python3 tests/make_vectors.py
"""
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "tools"))
import hellolink_strip as hs  # noqa: E402
import strip1 as s1           # noqa: E402

STATE = {
    "clock": {"clock": 54321}, "health": {"healthMax": 1158}, "power": {"powerMax": 1335, "powerType": 2},
    "level": {"level": 29, "xp": 2004, "xpMax": 64000}, "state": {"flags": 128 + 2 + 1},
    "cast": None, "target": {"level": 23, "flags": 128 + 1, "nameHash": 0x3D4F},
    "pet": {"healthMax": 1355}, "position": {"map": 1437, "x": 32768, "y": 16384, "facing": 64},
    "purse": {"money": 7800, "bagFree": 12}, "hand": {"item": 2504, "enchant": 599},
    "loot": {"counter": 1, "item": 2318, "quantity": 2}, "uiError": {"counter": 3, "error": 51},
    "threat": {"player": 58, "pet": 100},
}
SESSION, SEQ, DWELL = 4711, 9, 10
OBJECT_TEXT = '{"map": 1437, "zone": "Wetlands", "sub": "Black Channel Marsh"}'
LEVELS = (0.75, 0.83, 0.12, None)   # player health, player power, target health, no pet value
# Objects 7, 8 (#62), 9 (#64) and 10 (#68), each in a frame of its own after the first: the same state, the next seq.
MORE = (
    (7, 801, '{"source": "RXPGuides", "guide": "29-32 Duskwood", "map": 1434, "x": 21823, "y": 7799, "title": null, "step": 109, '
             '"text": "   Kill |cFFFF5722Young Stranglethorn Tigers|r\\n6/10 Young Stranglethorn Tiger slain"}'),
    (7, 802, "null"),
    (8, 803, '{"rested": 12345}'),
    (9, 804, '{"source": "ShortestPathForever", "owner": "RestedXP", "goal": {"map": 1415, "x": 31934, "y": 34315, "title": "RestedXP"}, "seconds": 40, "index": 1, "guided": true, "legCount": 1, "legs": [{"mode": "walk", "seconds": 40, "text": "Walk to RestedXP"}]}'),
    (9, 805, "null"),
    (10, 806, '{"name": "Eugen", "realm": "Test Realm"}'),
)


def main():
    out = HERE / "vectors"
    obj = s1.pack_object(OBJECT_TEXT, False)
    frame = s1.pack_frame(SESSION, SEQ, DWELL, s1.pack_fast(STATE), (3, 500, 0, 1, obj))
    vector = {
        "session": SESSION, "seq": SEQ, "dwell": DWELL, "state": STATE,
        "object": {"id": 3, "version": 500, "format": 0, "text": OBJECT_TEXT, "bytes": obj.hex()},
        "frame": frame.hex(), "frameBytes": len(frame),
        "levelsDrawn": list(LEVELS), "levelsRead": [76, 83, 12, None],
        "squaresDepth2": s1.bytes_to_squares(frame, 3), "squaresDepth4": s1.bytes_to_squares(frame, 6),
        "objects": [{"id": oid, "version": version, "format": 0, "text": text, "bytes": s1.pack_object(text, False).hex(),
                     "seq": SEQ + n, "frame": s1.pack_frame(SESSION, SEQ + n, DWELL, s1.pack_fast(STATE),
                                                            (oid, version, 0, 1, s1.pack_object(text, False))).hex()}
                    for n, (oid, version, text) in enumerate(MORE, 1)],
        "images": {"strip1_depth4.bmp": {"depth": 4, "square": 2, "left": 0, "top": 0},
                   "strip1_depth2.bmp": {"depth": 2, "square": 2, "left": 0, "top": 0}},
    }
    (out / "strip1.json").write_text(json.dumps(vector, indent=1, sort_keys=True) + "\n")
    for name, how in vector["images"].items():
        cells = s1.row_colours(SESSION, how["depth"], LEVELS, frame)
        lines = ["%d 0 2 2 %.6f %.6f %.6f" % (i * 2, r, g, b) for i, (r, g, b) in enumerate(cells)]
        (out / "cells.txt").write_text("\n".join(lines) + "\n")
        hs.render(out / "cells.txt", out / name, 1.0, 0, 0, len(cells) * 2, 2)
    (out / "cells.txt").unlink()
    print("wrote", ", ".join(sorted(p.name for p in out.iterdir())))


if __name__ == "__main__":
    main()
