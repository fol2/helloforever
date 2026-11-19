#!/usr/bin/env python3
"""Writes reader/hellolink/tests/floats.txt: one float a line as Python's repr() writes it (the
shortest text that reads back the same; of those, the nearest to the exact value). The Rust
test (hellolink/tests/floats.rs) reads each line as a number and must write the same text.

    python3 reader/tests/floats.py      # from the repository's top
"""
import json
import math
import random
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
rnd = random.Random(197)
values = [0.0, -0.0, 1.0, -1.0, 0.1, 0.5, 2.5, 1e-4, 9.999e-5, 1e15, 1e16, 9999999999999998.0, 1e22, 1e23,
          5e-324, 2.2250738585072014e-308, 2.225073858507201e-308, 1.7976931348623157e308, math.pi, 1 / 3]
values += [1794516378.0 + i / 256 for i in range(256)]           # Unix times to 1/256 s (the review's case)
values += [1794516378.25 + i * 0.001 for i in range(200)]
values += [k + j / 2 ** m for k in (1, 3, 1000, 2 ** 20, 2 ** 30 + 7) for m in (8, 10, 13, 20) for j in (1, 3, 5, 7)]
values += [2.0 ** e for e in range(-1074, 1024, 7)]
values += [round(i * 0.016, 3) for i in range(300)]              # the record's `t`
for name in ("rows.jsonl",):                                     # the step 1 fixtures' `square`
    for path in sorted((ROOT / "reader/hellolink/tests/fixtures").glob("*/" + name)):
        for line in path.read_text().splitlines():
            row = json.loads(line)
            if isinstance(row.get("square"), float):
                values.append(row["square"])
while len(values) < 6000:
    kind = rnd.random()
    if kind < 0.4:      # any finite bit pattern
        v = struct.unpack("<d", rnd.getrandbits(64).to_bytes(8, "little"))[0]
        if math.isfinite(v):
            values.append(v)
    elif kind < 0.7:
        values.append(rnd.uniform(-1e4, 1e4))
    else:
        values.append(rnd.uniform(0, 1) * 10.0 ** rnd.randint(-30, 30))
(ROOT / "reader/hellolink/tests/floats.txt").write_text("".join(repr(v) + "\n" for v in values))
print(len(values), "floats")
