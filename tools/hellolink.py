#!/usr/bin/env python3
"""HelloLink spike: the side outside the game.

    python3 tools/hellolink.py install <AddOns dir> [--slots 200]  # while the game is closed
    python3 tools/hellolink.py write <AddOns dir> <text | -> [--strip-session N]   # any time; "-" reads stdin

`install` copies HelloLink/ and creates the load-on-demand slot addons. The client only
knows addons that existed when it started, so start it after this. `write` puts the text
into every slot, because the tool cannot know which slot the game loads next.
"""
import argparse
import os
import re
import shutil
import sys
import tempfile
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


def inbox(seq: int, text: str, strip_session=None) -> bytes:
    """A slot's file. `strip_session` adds the reader's request for the live-state strip to
    fall back to depth 2 in that session (docs/specs/29.md, section 3)."""
    ask = "" if strip_session is None else ", strip = { session = %d, depth = 2 }" % strip_session
    return ("HelloLink_Inbox = { seq = %d, text = %s%s }\n" % (seq, lua_string(text), ask)).encode("latin-1")


def slots(addons: Path):
    return sorted(p for p in addons.glob("HelloLink_S[0-9][0-9][0-9]") if p.is_dir())


def put(slot: Path, data: bytes):
    # A temporary file of its own per write, then a rename: the game never sees half a
    # file, and two writers at once cannot publish each other's unfinished one.
    fd, tmp = tempfile.mkstemp(dir=slot, prefix=".inbox-")
    try:
        with os.fdopen(fd, "wb") as f:
            f.write(data)
        os.replace(tmp, slot / "Inbox.lua")
    except BaseException:
        os.unlink(tmp)
        raise


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


STRIP_ASK = re.compile(rb"strip = \{ session = (\d+), depth = 2 \}")


def pending_strip(addons: Path):
    """The session a slot already asks the strip to fall back in, or None."""
    for slot in slots(addons)[:1]:
        try:
            found = STRIP_ASK.search((slot / "Inbox.lua").read_bytes())
        except OSError:
            return None
        return int(found.group(1)) if found else None
    return None


def write(addons: Path, text: str, strip_session=None, quiet: bool = False):
    """Puts the text into every slot. A reader's request for the strip to fall back stays in
    the slots until another session is named: a write without one carries the old one over
    (the addon looks at a slot only now and then; docs/specs/29.md, section 3)."""
    found = slots(addons)
    if not found:
        sys.exit("no HelloLink slots in %s: run `install` first" % addons)
    if strip_session is None:
        strip_session = pending_strip(addons)
    data = inbox(time.time_ns() // 1_000_000, text, strip_session)
    for slot in found:
        put(slot, data)
    if not quiet:
        print("wrote %d bytes to %d slots" % (len(data), len(found)))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    a = sub.add_parser("install"); a.add_argument("addons", type=Path); a.add_argument("--slots", type=int, default=200)
    b = sub.add_parser("write"); b.add_argument("addons", type=Path); b.add_argument("text")
    b.add_argument("--strip-session", type=int, help="ask the strip of that session to fall back to depth 2; "
                   "a request already in the slots is kept by a write without this")
    args = ap.parse_args()
    if args.cmd == "install":
        if not 1 <= args.slots <= 999:
            sys.exit("--slots must be 1 to 999")
        install(args.addons, args.slots)
    else:
        write(args.addons, sys.stdin.read() if args.text == "-" else args.text, args.strip_session)


if __name__ == "__main__":
    main()
