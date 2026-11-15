#!/usr/bin/env python3
"""The assistant program (tools/assistant.py; docs/specs/115.md, sections 7 and 11, step 3; #133):
the heartbeat; nothing new while the state is not live; a question answered once; every later
set carries the answered re; a program started again takes re from object 13 and answers no
question twice; a question older than 60 s is not answered; `session` from a recorded run of
events; and the whole program against a stand-in for the reader's API and a scratch AddOns folder.
Usage: python3 tests/assistant_test.py"""
import json
import re
import shutil
import sys
import tempfile
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
import assistant as A   # noqa: E402
import hellolink        # noqa: E402

failed, checks = 0, 0


def check(name, ok, detail=""):
    global failed, checks
    checks += 1
    if not ok:
        failed += 1
        print("FAIL %s %s" % (name, detail))


T0 = 1794516000.0


def state(session=4711, level=(14, 1000, 9000), money=7800):
    return {"kind": "state", "session": session, "seq": 1, "depth": 4,
            "fast": {"level": {"level": level[0], "xp": level[1], "xpMax": level[2]}, "purse": {"money": money, "bagFree": 3}}}


def obj13(ask=None, re_=None, seq=None, lang="en"):
    v = {"on": True, "lang": lang, "seq": seq, "re": re_, "ask": ask, "left": 150, "taken": 0, "refused": 0, "shown": None}
    return {"kind": "object", "id": 13, "format": 1, "text": json.dumps(v)}


def fight(key, this, usual, died=False, name="Defias Thug"):
    v = {"fight": key, "rev": 1, "counted": True, "id": 1984, "level": 14, "name": name,
         "dur": [this, usual, 5], "dps": [30, 30, 5], "taken": [100, 100, 5], "died": [died, 0, 5]}
    return {"kind": "object", "id": 12, "format": 1, "text": json.dumps(v)}


# 1. No set before the session and object 13 are known; then the heartbeat.
b = A.Assistant()
check("no set before anything is known", b.due(T0) is None)
b.feed(state(), T0)
check("no set before object 13 is read (its re must be known first)", b.due(T0) is None)
b.feed(obj13(), T0)
s = b.due(T0)
check("then a set for the session, with no card and no re", s is not None and s["session"] == 4711 and s["cards"] == [] and s["re"] is None)
check("the heartbeat: nothing new within a minute", b.due(T0 + 30) is None)
s2 = b.due(T0 + 61)
check("...and a set again after a minute, the same seq (nothing changed)", s2 is not None and s2["seq"] == s["seq"])

# 2. `session` from a recorded run of events: fights, deaths, XP an hour, money, the slowest.
b = A.Assistant()
run = [state(level=(14, 1000, 9000), money=7800), obj13(),
       fight("hf1-a-1", 12, 15), fight("hf1-a-2", 18, 12, died=True, name="Riverpaw Gnoll"),
       fight("hf1-a-2", 18, 12, died=True, name="Riverpaw Gnoll"),            # a version seen again
       fight("hf1-a-3", 14, 13, name="Defias Thug"),
       state(level=(14, 8500, 9000), money=17000), state(level=(15, 500, 9800), money=19000)]
for i, e in enumerate(run):
    b.feed(e, T0 + i * 300)                                                    # 7 events, 35 minutes
now = T0 + 7 * 300
b.feed(obj13(ask={"n": 1, "topic": "session", "t": int(now) - 5}), now)
s = b.due(now)
c = s and s["cards"] and s["cards"][0]
# XP: 7500 to the end of level 14 (1000 -> 8500), then 500 + (9000 - 8500) = 1000 after the level up: 8500 in 35 min.
check("session: the fights counted once each, the deaths, XP an hour, the money gained",
      c and c["text"] == "This session: 3 fights, 1 death, 14,571 XP an hour, +1 g 12 s", c and c["text"])
check("...the slowest against usual in the detail", c and c.get("detail") == "Slowest against usual: Riverpaw Gnoll 18 s, usual 12 s", c and c.get("detail"))
check("...and its ground: the strip since the session began", c and c["basis"] == "the strip since " + time.strftime("%H:%M", time.localtime(T0)))
check("...an event card of the companion, 600 s", c and c["id"] == "session" and c["kind"] == "event" and c["src"] == "companion" and c["ttl"] == 600)
check("the set carries the answered question's number", s["re"] == 1)
check("the set is one the tool can write", hellolink.check_assist(s)["re"] == 1)

# 3. Answered once; every later set carries re.
check("the same question is not answered again", b.due(now + 2) is None)
later = b.due(now + 70)
check("a later set (the heartbeat) carries re and the card", later and later["re"] == 1 and later["cards"] and later["cards"][0]["id"] == "session")
gone = b.due(now + 700)
check("the card goes after its ttl, the re stays", gone and gone["cards"] == [] and gone["re"] == 1)
b.feed(obj13(ask={"n": 2, "topic": "session", "t": int(now) + 800}, re_=1), now + 800)
nxt = b.due(now + 801)
check("the next question is answered", nxt and nxt["re"] == 2 and nxt["cards"] and nxt["cards"][0]["id"] == "session")

# 4. Nothing new while the state is not live.
b = A.Assistant()
b.feed(state(), T0)
b.feed(obj13(), T0)
b.due(T0)
b.feed({"kind": "stale", "session": 4711, "seq": 1}, T0 + 10)
b.feed(obj13(ask={"n": 1, "topic": "session", "t": int(T0) + 10}), T0 + 10)
s = b.due(T0 + 11)
check("while the reader says stale a question is not answered", s is None or (s["re"] is None and s["cards"] == []))
b.feed(state(), T0 + 20)
s = b.due(T0 + 21)
check("...and live again within 60 s it is", s and s["re"] == 1)
b = A.Assistant()
b.feed({"kind": "snapshot", "condition": "waiting", "state": None, "objects": {}}, T0)
b.feed(obj13(ask={"n": 1, "topic": "session", "t": int(T0)}), T0)
check("with no live state there is no session and no set", b.due(T0 + 1) is None)

# 5. A question older than 60 s is not answered; another topic is not this program's.
b = A.Assistant()
b.feed(state(), T0)
b.feed(obj13(ask={"n": 1, "topic": "session", "t": int(T0) - 61}), T0)
s = b.due(T0)
check("a question asked 61 s ago is not answered", s and s["re"] is None and s["cards"] == [])
b.feed(obj13(ask={"n": 2, "topic": "weather", "t": int(T0)}), T0 + 1)
s = b.due(T0 + 2)
check("a topic it does not know is not answered", s is None or (s["re"] is None and s["cards"] == []))

# 6. Started again: re from object 13; no question answered twice.
b = A.Assistant()
o13 = obj13(ask={"n": 4, "topic": "session", "t": int(T0) - 10}, re_=4, seq=9)["text"]
snap = {"kind": "snapshot", "condition": "live", "state": state(), "objects": {"13": {"format": 1, "stale": False, "text": o13}}}
b.feed(snap, T0)
s = b.due(T0)
check("started again, it takes re from object 13 and answers no question twice", s and s["re"] == 4 and s["cards"] == [])
check("...and its seq follows the one the game holds", s and s["seq"] >= 9)

# 7. A new UI session (a reload) starts the counts again.
b = A.Assistant()
b.feed(state(session=1), T0)
b.feed(obj13(), T0)
b.feed(fight("hf1-x", 10, 12), T0)
b.feed(state(session=2), T0 + 5)
b.feed(obj13(ask={"n": 1, "topic": "session", "t": int(T0) + 5}), T0 + 5)
s = b.due(T0 + 6)
check("a new UI session: the set is for it, and its counts start again",
      s and s["session"] == 2 and s["cards"] and s["cards"][0]["text"].startswith("This session: 0 fights, 0 deaths"))
# Cantonese
b = A.Assistant()
b.feed(state(), T0)
b.feed(obj13(ask={"n": 1, "topic": "session", "t": int(T0)}, lang="yue"), T0)
s = b.due(T0)
check("the card is in the player's language", s and s["cards"] and s["cards"][0]["text"].startswith("今次："), s and s["cards"])
check("money: copper, silver, gold, and a loss", A.money_text(0) == "0 c" and A.money_text(5) == "+5 c" and A.money_text(-12345) == "-1 g 23 s 45 c")

# Review round 1 (#134): a reload after an answer; revisions of a fight.
b = A.Assistant()
b.feed(state(session=1), T0)
b.feed(obj13(ask={"n": 1, "topic": "session", "t": int(T0)}), T0)
s = b.due(T0)
check("session 1: question 1 answered", s and s["re"] == 1)
b.feed(state(session=2), T0 + 10)
check("a reload: no set before the new session's object 13 is read (no old re carried)", b.due(T0 + 11) is None)
b.feed(obj13(ask={"n": 1, "topic": "session", "t": int(T0) + 12}), T0 + 12)
s = b.due(T0 + 12)
check("...then the new session's question 1 is answered", s and s["session"] == 2 and s["re"] == 1 and s["cards"])
b = A.Assistant()
b.feed(state(), T0)
b.feed(obj13(), T0)
b.feed(fight("hf1-r-1", 12, 15), T0)
b.feed(fight("hf1-r-1", 12, 15, died=True), T0 + 1)          # a later revision adds a death
b.feed(fight("hf1-r-2", 30, 10, name="Gone Boar"), T0 + 2)
b.feed({"kind": "object", "id": 12, "format": 1, "text": json.dumps({"fight": "hf1-r-2", "rev": 2, "counted": False})}, T0 + 3)
b.feed(obj13(ask={"n": 1, "topic": "session", "t": int(T0) + 4}), T0 + 4)
c = (b.due(T0 + 4) or {}).get("cards")
check("a fight by its last revision: a death added later counts; a fight that no longer counts goes",
      c and c[0]["text"].startswith("This session: 1 fight, 1 death") and "detail" not in c[0], c)

# 8. The whole program: a stand-in reader and a scratch AddOns folder.
tmp = Path(tempfile.mkdtemp(prefix="assistant-"))
addons = tmp / "AddOns"
import contextlib, io  # noqa: E401
with contextlib.redirect_stdout(io.StringIO()):
    hellolink.install(addons, 3)
now = int(time.time())
feed = [{"kind": "snapshot", "condition": "live", "state": state(session=21517), "levels": {}, "objects": {
            "13": {"format": 1, "stale": False, "text": obj13(ask={"n": 1, "topic": "session", "t": now}, re_=None, seq=1)["text"]}}, "age": 0.1},
        fight("hf1-z-1", 20, 12, name="Kobold Vermin")]


class Reader(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path != "/events":
            self.send_error(404)
            return
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.end_headers()
        try:
            for e in feed:
                self.wfile.write(("data: %s\n\n" % json.dumps(e)).encode())
                self.wfile.flush()
                time.sleep(0.2)
            for _ in range(20):
                self.wfile.write(b": alive\n\n")
                self.wfile.flush()
                time.sleep(0.2)
        except OSError:
            pass                                   # the program left: the run ended

    def log_message(self, *a):
        pass


server = ThreadingHTTPServer(("127.0.0.1", 0), Reader)
threading.Thread(target=server.serve_forever, daemon=True).start()
url = "http://127.0.0.1:%d" % server.server_address[1]
log = tmp / "sets.jsonl"
A.run(addons, url, str(log), until=time.time() + 3)
server.shutdown()
slot = (addons / "HelloLink_S002" / "Inbox.lua").read_text(encoding="latin-1")
check("the program writes the set into every slot, for the session, answering the question",
      "assist = { session = 21517, seq = " in slot and ", re = 1," in slot and 'id = "session"' in slot, slot[:300])
lines = [json.loads(x) for x in log.read_text().splitlines()]
check("--log has each set written", lines and lines[0]["re"] == 1)
check("it answered once in the run: one set with the card, re 1 in every set", len(lines) == 1 and lines[0]["re"] == 1 and len(lines[0]["cards"]) == 1,
      json.dumps(lines)[:300])
# 9. The reader goes away: the heartbeat goes on; a closed stream is not tried again at once.
A.HEARTBEAT, A.RETRY = 1, 0.5
calls = []


class Once(BaseHTTPRequestHandler):
    def do_GET(self):
        calls.append(time.time())
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.end_headers()
        if len(calls) == 1:                                   # the first time: the present, then the stream ends
            try:
                self.wfile.write(("data: %s\n\n" % json.dumps(feed[0])).encode())
                self.wfile.flush()
            except OSError:
                pass

    def log_message(self, *a):
        pass


server = ThreadingHTTPServer(("127.0.0.1", 0), Once)
threading.Thread(target=server.serve_forever, daemon=True).start()
log2 = tmp / "offline.jsonl"
A.run(addons, "http://127.0.0.1:%d" % server.server_address[1], str(log2), until=time.time() + 3.5)
server.shutdown()
sets = [json.loads(x) for x in log2.read_text().splitlines()] if log2.exists() else []
check("with the reader's stream ended the program still writes a set about every heartbeat", len(sets) >= 3, len(sets))
check("...and does not try the stream again at once (a pause between tries)", 2 <= len(calls) <= 9, len(calls))
shutil.rmtree(tmp)

print("== %d checks, %d failed" % (checks, failed))
sys.exit(1 if failed else 0)
