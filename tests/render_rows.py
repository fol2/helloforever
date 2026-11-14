#!/usr/bin/env python3
"""For tests/strip1_addon_test.lua: renders each cells file (as `hellolink_strip.py render`
does) and reads the rows of the images (as `hellolink_strip.py rows` does), in one process.
One process a watch, not one a frame: the addon test drew some 2500 frames, each in a Python
process of its own, and passed CI's ten minutes (#95).
Usage: python3 tests/render_rows.py --scale S --step T a.txt b.txt ..."""
import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "tools"))
import hellolink_strip as hs  # noqa: E402

ap = argparse.ArgumentParser()
ap.add_argument("--scale", type=float, required=True)
ap.add_argument("--step", type=float, default=0.1)
ap.add_argument("cells", type=Path, nargs="+")
args = ap.parse_args()
images = []
for cells in args.cells:
    image = cells.with_suffix(".bmp")
    hs.render(cells, image, args.scale, 0, 0, 2560, 12)
    images.append(image)
hs.rows_of_images(images, args.step)
