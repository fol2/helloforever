#!/usr/bin/env python3
"""The slot file's `assist` part, as tools/hellolink.py writes it (docs/specs/115.md, section 6;
#127): the hand-written vector byte for byte, the parts each writer carries over, `slots`, the
tool's refusals, and the Lua string encoder on hard text (read back by lua5.1).
Usage: python3 tests/hellolink_assist_test.py"""
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
import hellolink as hl  # noqa: E402

TOOL = [sys.executable, str(ROOT / "tools" / "hellolink.py")]
LUA = os.environ.get("LUA", "lua5.1")
tmp = Path(tempfile.mkdtemp(prefix="hellolink-assist-"))
failed, checks = 0, 0


def check(name, ok, detail=""):
    global failed, checks
    checks += 1
    if not ok:
        failed += 1
        print("FAIL %s %s" % (name, detail))


SET = {"session": 4711, "seq": 12, "re": 3, "cards": [
    {"id": "session", "kind": "event", "prio": 3, "src": "companion", "at": 1794516370, "ttl": 600,
     "text": "This session: 42 fights, 1 death, 14,200 XP an hour", "basis": "the strip since 20:14"}]}

# 1. The vector, written by hand from the spec: the tool must write it byte for byte.
vector = (ROOT / "tests" / "vectors" / "assist_inbox.lua").read_bytes()
made = getattr(hl, "inbox_file", lambda *a, **k: b"")(1794516378971, "", 200, strip=4711, assist=SET, t=1794516378)
check("the tool writes the hand-made slot file byte for byte", made == vector, "\n%r\n%r" % (made, vector))


def run(*args, stdin=None):
    return subprocess.run(TOOL + list(args), input=stdin, capture_output=True, text=True)


def slot(i=1):
    return (tmp / "AddOns" / ("HelloLink_S%03d" % i) / "Inbox.lua").read_text(encoding="latin-1")


def lua_read(path, expr):
    """The value of `expr` after the slot file at `path` ran in Lua 5.1."""
    code = "dofile(%r) io.write(tostring(%s))" % (str(path), expr)
    return subprocess.run([LUA, "-e", code], capture_output=True).stdout


# 2. The parts each writer carries over.
addons = tmp / "AddOns"
done = run("install", str(addons), "--slots", "3")
check("install", done.returncode == 0, done.stderr)
check("an installed slot says how many slots there are", "slots = 3" in slot(1))
run("write", str(addons), "a question's text")
seq = slot(1).split("seq = ")[1].split(",")[0]
done = run("write", str(addons), "--assist", "-", stdin=json.dumps(SET))
check("write --assist exits 0", done.returncode == 0, done.stderr)
s1 = slot(1)
check("write --assist puts the part in every slot", all("assist = { session = 4711, seq = 12, t = " in slot(i) for i in (1, 2, 3)))
check("...and keeps the top seq and text", ("seq = %s," % seq) in s1 and 'text = "a question\'s text"' in s1)
t = int(__import__("re").search(r", t = (\d+)", s1).group(1))
check("...with t the time of the write", abs(t - int(__import__("time").time())) <= 5)
check("...and slots", "slots = 3," in s1)
run("write", str(addons), "a new text")
s2 = slot(1)
check("a text write carries the assist part over, and has a new seq",
      "assist = { session = 4711, seq = 12, t = %d" % t in s2 and ("seq = %s," % seq) not in s2 and '"a new text"' in s2)
seq2 = s2.split("seq = ")[1].split(",")[0]
run("write", str(addons), "--strip-session", "4711")
s3 = slot(1)
check("a strip write keeps the top seq, the text and the assist part",
      ("seq = %s," % seq2) in s3 and '"a new text"' in s3 and "strip = { session = 4711, depth = 2 }" in s3 and "assist = { session = 4711" in s3)
run("write", str(addons), "--assist", "-", stdin=json.dumps(dict(SET, seq=13, cards=[])))
s4 = slot(1)
check("an assist write keeps the strip request; an empty set is written as such",
      "strip = { session = 4711, depth = 2 }" in s4 and "seq = 13, t = " in s4 and "cards = {}" in s4)
check("the slot file runs in Lua and holds what was written",
      lua_read(addons / "HelloLink_S001" / "Inbox.lua", "HelloLink_Inbox.assist.seq .. ' ' .. HelloLink_Inbox.slots .. ' ' .. HelloLink_Inbox.strip.session")
      == b"13 3 4711")

# 3. The tool refuses a set it cannot write as the spec says, and changes nothing.
before = slot(1)
for label, bad in (("nine cards", dict(SET, cards=SET["cards"] * 9)),
                   ("a session that is no whole number", dict(SET, session=4.5)),
                   ("a card that is no table", dict(SET, cards=["x"])),
                   ("a text that is a number", dict(SET, cards=[dict(SET["cards"][0], text=7)])),
                   ("a prio that is a word", dict(SET, cards=[dict(SET["cards"][0], prio="high")])),
                   ("no cards list", {"session": 4711, "seq": 1}),
                   ("not JSON", None)):
    done = run("write", str(addons), "--assist", "-", stdin="{" if bad is None else json.dumps(bad))
    check("refused: " + label, done.returncode != 0 and slot(1) == before, done.stderr[-200:])
done = run("write", str(addons))
check("a write with nothing to write is refused", done.returncode != 0 and slot(1) == before)

# 4. The encoder: a text is data, never code (quotes, backslashes, ]], line breaks, bytes
# that are not UTF-8), read back by Lua byte for byte.
hard = "say \"hi\" \\ back ]] end --[[ x\nline two\r\0 nul é 你好".encode("utf-8") + b"\xff\xfe end"
f = tmp / "hard.lua"
f.write_bytes(b"X = " + hl.lua_string(hard).encode("latin-1") + b"\n")
check("the encoder's text comes back from Lua byte for byte", lua_read(f, "X") == hard)
odd = dict(SET["cards"][0], text='a "quote" ]] and \\ and\nbreak', basis="é ]=] [[x]]", extra="dropped")
done = run("write", str(addons), "--assist", "-", stdin=json.dumps(dict(SET, cards=[odd])))
check("a hard text through write --assist exits 0", done.returncode == 0, done.stderr)
got = lua_read(addons / "HelloLink_S001" / "Inbox.lua", "HelloLink_Inbox.assist.cards[1].text .. '|' .. HelloLink_Inbox.assist.cards[1].basis .. '|' .. tostring(HelloLink_Inbox.assist.cards[1].extra)")
check("...and comes back from Lua as written; a field the spec does not have is not written",
      got == ('a "quote" ]] and \\ and\nbreak|é ]=] [[x]]|nil').encode("utf-8"), repr(got))

shutil.rmtree(tmp)
print("== %d checks, %d failed" % (checks, failed))
sys.exit(1 if failed else 0)
