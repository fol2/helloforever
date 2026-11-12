#!/usr/bin/env python3
"""HelloLink spike: the side outside the game.

    python3 tools/hellolink.py install <AddOns dir> [--slots 50]   # while the game is closed
    python3 tools/hellolink.py write <AddOns dir> <text | ->        # any time; "-" reads stdin

`install` copies HelloLink/ and creates the load-on-demand slot addons. The client only
knows addons that existed when it started, so start it after this. `write` puts the text
into every slot, because the tool cannot know which slot the game loads next.
"""
import argparse
import os
import shutil
import sys
import time
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
TOC = "## Interface: 16001\n## Title: HelloLink slot {n:03d}\n## LoadOnDemand: 1\n\nInbox.lua\n"


def lua_string(text: str) -> str:
    out = []
    for b in text.encode("utf-8"):
        if b in (0x22, 0x5C):          # " and \
            out.append("\\" + chr(b))
        elif b < 0x20 or b == 0x7F:    # control bytes, newline included
            out.append("\\%03d" % b)
        else:
            out.append(chr(b))         # one char per byte; written back as latin-1 below
    return '"' + "".join(out) + '"'


def inbox(seq: int, text: str) -> bytes:
    return ("HelloLink_Inbox = { seq = %d, text = %s }\n" % (seq, lua_string(text))).encode("latin-1")


def slots(addons: Path):
    return sorted(p for p in addons.glob("HelloLink_S[0-9][0-9][0-9]") if p.is_dir())


def put(slot: Path, data: bytes):
    tmp = slot / "Inbox.lua.tmp"
    tmp.write_bytes(data)
    os.replace(tmp, slot / "Inbox.lua")  # the game never sees half a file


def install(addons: Path, n: int):
    if not addons.is_dir():
        addons.mkdir(parents=True)
    shutil.copytree(REPO / "HelloLink", addons / "HelloLink", dirs_exist_ok=True)
    for i in range(1, n + 1):
        slot = addons / ("HelloLink_S%03d" % i)
        slot.mkdir(exist_ok=True)
        (slot / ("HelloLink_S%03d.toc" % i)).write_text(TOC.format(n=i))
        put(slot, inbox(0, ""))
    print("installed HelloLink and %d slots in %s" % (n, addons))


def write(addons: Path, text: str):
    found = slots(addons)
    if not found:
        sys.exit("no HelloLink slots in %s: run `install` first" % addons)
    data = inbox(time.time_ns() // 1_000_000, text)
    for slot in found:
        put(slot, data)
    print("wrote %d bytes to %d slots" % (len(data), len(found)))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    a = sub.add_parser("install"); a.add_argument("addons", type=Path); a.add_argument("--slots", type=int, default=50)
    b = sub.add_parser("write"); b.add_argument("addons", type=Path); b.add_argument("text")
    args = ap.parse_args()
    if args.cmd == "install":
        if not 1 <= args.slots <= 999:
            sys.exit("--slots must be 1 to 999")
        install(args.addons, args.slots)
    else:
        write(args.addons, sys.stdin.read() if args.text == "-" else args.text)


if __name__ == "__main__":
    main()
