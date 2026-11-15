#!/usr/bin/env python3
"""HelloLink spike: the side outside the game.

    python3 tools/hellolink.py install <AddOns dir> [--slots 200]  # while the game is closed
    python3 tools/hellolink.py write <AddOns dir> [<text | ->] [--strip-session N] [--assist <json file | ->]

`install` copies HelloLink/ and creates the load-on-demand slot addons. The client only
knows addons that existed when it started, so start it after this. `write` puts the file
into every slot, because the tool cannot know which slot the game loads next.

The slot file has three parts, each with one writer (docs/specs/115.md, section 6): the text
(`seq`, `text`; `/hlink`), the reader's request to the strip (`strip`) and the assistant's
set of cards (`assist`). A write replaces its own part and carries the others over; a write
of `strip` or `assist` keeps the top `seq` and `text`, so `/hlink` does not show an old text
as new. The parts live in `.parts.json` beside the first slot, which the game never reads.
"""
import argparse
import fcntl
import json
import os
import re
import shutil
import sys
import tempfile
import time
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
TOC = "## Interface: 16001\n## Title: HelloLink slot {n:03d}\n## LoadOnDemand: 1\n\nInbox.lua\n"


def lua_string(text) -> str:
    """A Lua string literal of the text (str, or bytes taken as they are): data, never code."""
    out = []
    for b in (text if isinstance(text, bytes) else text.encode("utf-8")):
        if b in (0x22, 0x5C):          # " and \
            out.append("\\" + chr(b))
        elif b < 0x20 or b == 0x7F:    # control bytes, newline included
            out.append("\\%03d" % b)
        else:
            out.append(chr(b))         # one char per byte; written back as latin-1 below
    return '"' + "".join(out) + '"'


CARD_FIELDS = ("id", "kind", "prio", "src", "at", "ttl", "text", "basis", "detail")
CARD_TEXT = {"id", "kind", "src", "text", "basis", "detail"}   # the others are whole numbers


def whole(v) -> bool:
    return isinstance(v, int) and not isinstance(v, bool)


def check_assist(a) -> dict:
    """The set as the tool can write it: whole numbers and strings where the spec has them,
    at most 8 cards; a field a card does not need is left out. Raises ValueError. The addon
    checks the rest (section 6, "What HelloLink takes")."""
    if not isinstance(a, dict) or not all(whole(a.get(k)) for k in ("session", "seq")):
        raise ValueError("the set needs whole numbers session and seq")
    if a.get("re") is not None and not whole(a["re"]):
        raise ValueError("re is a whole number or absent")
    cards = a.get("cards")
    if not isinstance(cards, list) or len(cards) > 8:
        raise ValueError("cards is a list of at most 8")
    out = []
    for c in cards:
        if not isinstance(c, dict):
            raise ValueError("a card is an object")
        card = {}
        for k in CARD_FIELDS:
            v = c.get(k)
            if v is None:
                continue
            if (k in CARD_TEXT and not isinstance(v, str)) or (k not in CARD_TEXT and not whole(v)):
                raise ValueError("card field %s has the wrong type" % k)
            card[k] = v
        out.append(card)
    return {"session": a["session"], "seq": a["seq"], "re": a.get("re"), "cards": out}


def assist_lua(a: dict, t: int) -> str:
    items = ["session = %d" % a["session"], "seq = %d" % a["seq"], "t = %d" % t]
    if a.get("re") is not None:
        items.append("re = %d" % a["re"])
    cards = ["{ %s }" % ", ".join("%s = %s" % (k, lua_string(c[k]) if k in CARD_TEXT else "%d" % c[k])
                                  for k in CARD_FIELDS if k in c) for c in a["cards"]]
    items.append("cards = { %s }" % ", ".join(cards) if cards else "cards = {}")
    return "{ %s }" % ", ".join(items)


def inbox_file(seq: int, text: str, slots_n: int, strip=None, assist=None, t=None) -> bytes:
    """A slot's file. `strip` is the session whose strip is asked to fall back to depth 2
    (docs/specs/29.md, section 3); `assist` the set of cards, written at time `t`."""
    out = "HelloLink_Inbox = { seq = %d, text = %s, slots = %d" % (seq, lua_string(text), slots_n)
    if strip is not None:
        out += ", strip = { session = %d, depth = 2 }" % strip
    if assist is not None:
        out += ", assist = " + assist_lua(assist, t)
    return (out + " }\n").encode("latin-1")


def inbox(seq: int, text: str, strip_session=None) -> bytes:
    """A slot's file with one slot counted; kept for the tests that use it."""
    return inbox_file(seq, text, 1, strip_session)


def slots(addons: Path):
    return sorted(p for p in addons.glob("HelloLink_S[0-9][0-9][0-9]") if p.is_dir())


def put(slot: Path, data: bytes, name: str = "Inbox.lua"):
    # A temporary file of its own per write, then a rename: the game never sees half a
    # file, and two writers at once cannot publish each other's unfinished one.
    fd, tmp = tempfile.mkstemp(dir=slot, prefix=".inbox-")
    try:
        with os.fdopen(fd, "wb") as f:
            f.write(data)
        os.replace(tmp, slot / name)
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
        put(slot, inbox_file(0, "", n))
    print("installed HelloLink and %d slots in %s" % (n, addons))


# The request is the last field of the file this tool writes. The pattern is tied to the
# file's end: the same words inside the text are followed by the text's closing quote, and a
# quote inside the text is written with a backslash, so they cannot end the file this way.
STRIP_ASK = re.compile(rb'", (?:slots = \d+, )?strip = \{ session = (\d+), depth = 2 \} \}\n\Z')


OLD_TOP = re.compile(rb'\AHelloLink_Inbox = \{ seq = (\d+), text = "((?:[^"\\]|\\.)*)"')


def old_top(addons: Path):
    """The `seq` and `text` of a slot written before the parts were kept, or None."""
    for slot in slots(addons)[:1]:
        try:
            found = OLD_TOP.match((slot / "Inbox.lua").read_bytes())
        except OSError:
            return None
        if not found:
            return None
        raw = re.sub(rb"\\(\d{3}|.)", lambda m: bytes([int(m.group(1))]) if m.group(1).isdigit() else m.group(1),
                     found.group(2), flags=re.S)
        return int(found.group(1)), raw.decode("utf-8", "replace")
    return None


def pending_strip(addons: Path):
    """The session a slot already asks the strip to fall back in, or None."""
    for slot in slots(addons)[:1]:
        try:
            found = STRIP_ASK.search((slot / "Inbox.lua").read_bytes())
        except OSError:
            return None
        return int(found.group(1)) if found else None
    return None


def write(addons: Path, text=None, strip_session=None, quiet: bool = False, assist=None):
    """Puts the file into every slot, with the parts given replaced and the others carried
    over. A reader's request for the strip to fall back stays in the slots until another
    session is named (the addon looks at a slot only now and then; docs/specs/29.md,
    section 3). `assist` is a set checked by check_assist."""
    found = slots(addons)
    if not found:
        sys.exit("no HelloLink slots in %s: run `install` first" % addons)
    # One writer at a time reads the parts, replaces its own and writes every slot: two
    # writers (a text, a reader's request, the companion) cannot undo each other.
    with open(found[0] / ".lock", "w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        try:
            parts = json.loads((found[0] / ".parts.json").read_text())
        except (OSError, ValueError):
            # slots written before the parts were kept: their text, its seq and the request stay
            parts = {"strip": pending_strip(addons)}
            top = old_top(addons)
            if top:
                parts["seq"], parts["text"] = top
        if text is not None or "seq" not in parts:
            parts["seq"], parts["text"] = time.time_ns() // 1_000_000, text or ""
        if strip_session is not None:
            parts["strip"] = strip_session
        if assist is not None:
            parts["assist"], parts["t"] = assist, int(time.time())
        data = inbox_file(parts["seq"], parts["text"], len(found), parts.get("strip"), parts.get("assist"), parts.get("t"))
        put(found[0], json.dumps(parts).encode(), ".parts.json")
        for slot in found:
            put(slot, data)
    if not quiet:
        print("wrote %d bytes to %d slots" % (len(data), len(found)))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    a = sub.add_parser("install"); a.add_argument("addons", type=Path); a.add_argument("--slots", type=int, default=200)
    b = sub.add_parser("write"); b.add_argument("addons", type=Path); b.add_argument("text", nargs="?")
    b.add_argument("--strip-session", type=int, help="ask the strip of that session to fall back to depth 2; "
                   "a request already in the slots is kept by a write without this")
    b.add_argument("--assist", help="the assistant's set of cards, a JSON file or - for stdin (docs/specs/115.md)")
    args = ap.parse_args()
    if args.cmd == "install":
        if not 1 <= args.slots <= 999:
            sys.exit("--slots must be 1 to 999")
        install(args.addons, args.slots)
        return
    if args.text is None and args.strip_session is None and args.assist is None:
        sys.exit("nothing to write: give a text, --strip-session or --assist")
    if args.text == "-" and args.assist == "-":
        sys.exit("only one of the text and --assist can come from stdin")
    assist = None
    if args.assist is not None:
        try:
            raw = sys.stdin.read() if args.assist == "-" else Path(args.assist).read_text()
            assist = check_assist(json.loads(raw))
        except (OSError, ValueError) as e:
            sys.exit("--assist: %s" % e)
    text = sys.stdin.read() if args.text == "-" else args.text
    write(args.addons, text, args.strip_session, assist=assist)


if __name__ == "__main__":
    main()
