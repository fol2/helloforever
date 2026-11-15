#!/usr/bin/env python3
"""The assistant program (docs/specs/115.md, section 7; the spec calls it the companion): it
reads the reference reader's local API and answers the player's questions with cards, written
into the slot files that HelloLink reads (section 6).

    python3 tools/assistant.py --addons <AddOns dir> [--reader http://127.0.0.1:8787] [--log <file>]

It listens to the reader's /events (the present first, then every event); it starts no capture
of its own, keeps no state on disk and takes no screenshot. It writes the assistant's part of
the slot files at least once a minute, and at once when it answers. It reads only the reader's
API and writes only slot files: it presses no key and touches no window.

A question is object 13's `ask` (`{"n", "topic", "t"}`) whose `n` is not yet answered and whose
`t` is no more than 60 s ago. The one topic of step 3 is `session`: since the program began to
follow this UI session, the counted fights and deaths (object 12), the XP an hour and the money
gained (the fast block), and the enemy that took longest against its usual time.
"""
import argparse
import json
import socket
import sys
import time
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import hellolink  # noqa: E402

HEARTBEAT = 60        # seconds: a set at least this often, so the game knows the program is alive
ANSWER_WITHIN = 60    # seconds: an older question is not answered (the bar said "no answer")
CARD_TTL = 600        # seconds an answer stays on the bar

TEXT = {
    "en": {"session": "This session: {fights}, {deaths}{xp}{money}",
           "fights": ("{n} fight", "{n} fights"), "deaths": ("{n} death", "{n} deaths"),
           "xp": ", {n} XP an hour", "money": ", {m}",
           "slow": "Slowest against usual: {name} {this} s, usual {usual} s",
           "basis": "the strip since {hm}"},
    "yue": {"session": "今次：{fights}，{deaths}{xp}{money}",
            "fights": ("{n} 場", "{n} 場"), "deaths": ("死 {n} 次", "死 {n} 次"),
            "xp": "，每個鐘 {n} XP", "money": "，{m}",
            "slow": "比平時慢得最多：{name} {this} 秒，平時 {usual} 秒",
            "basis": "由 {hm} 起嘅 strip"},
}


def money_text(copper: int) -> str:
    sign = "+" if copper > 0 else "-" if copper < 0 else ""
    c = abs(copper)
    parts = [("%d g" % (c // 10000)) if c >= 10000 else "", ("%d s" % (c // 100 % 100)) if c >= 100 else "",
             ("%d c" % (c % 100)) if c % 100 or c == 0 else ""]
    return sign + " ".join(p for p in parts if p)


def whole(v) -> bool:
    return isinstance(v, int) and not isinstance(v, bool)


class Assistant:
    """What the program knows and when it writes. `feed` takes the reader's events; `due` gives
    the set to write now (a dict for hellolink.check_assist), or None."""

    def __init__(self):
        self.live = False
        self.session = None
        self.seen13 = False         # object 13 read once: its re is known before the first write
        self.re = None              # the last question answered (carried in every later set)
        self.seq = 0
        self.cards = []             # cards given: event cards, until their ttl
        self.lang = "en"
        self.ask = None             # object 13's last question
        self.last_write = None
        self.changed = False
        self._reset(None)

    def _reset(self, now):
        self.start = now
        self.xp_gained, self.level = 0, None
        self.money_first = self.money_last = None
        self.fight_keys, self.deaths, self.slowest = set(), 0, None

    # --- what the reader says ---
    def feed(self, e: dict, now: float):
        kind = e.get("kind")
        if kind == "snapshot":
            self.live = e.get("condition") == "live"
            if isinstance(e.get("state"), dict):
                self._state(e["state"], now, keep_live=True)
            for oid, o in sorted((e.get("objects") or {}).items()):
                if isinstance(o, dict) and not o.get("stale"):
                    self._object(int(oid), o.get("text"), now)
        elif kind == "state":
            self.live = True
            self._state(e, now)
        elif kind == "object":
            self._object(e.get("id"), e.get("text"), now)
        elif kind in ("stale", "lost", "waiting"):
            self.live = False

    def _state(self, e, now, keep_live=False):
        session = e.get("session")
        if whole(session) and session != self.session:
            self.session = session
            self._reset(now)
            self.cards, self.changed = [], True
        fast = e.get("fast") or {}
        lv = fast.get("level")
        if isinstance(lv, dict) and all(whole(lv.get(k)) for k in ("level", "xp", "xpMax")):
            new = (lv["level"], lv["xp"], lv["xpMax"])
            if self.level:
                old = self.level
                if new[0] == old[0] and new[1] >= old[1]:
                    self.xp_gained += new[1] - old[1]
                elif new[0] == old[0] + 1:            # a level up: the rest of the old bar, then the new
                    self.xp_gained += max(0, old[2] - old[1]) + new[1]
            self.level = new
        purse = fast.get("purse")
        if isinstance(purse, dict) and whole(purse.get("money")):
            if self.money_first is None:
                self.money_first = purse["money"]
            self.money_last = purse["money"]

    def _object(self, oid, text, now):
        try:
            v = json.loads(text) if isinstance(text, str) else None
        except ValueError:
            return
        if oid == 12 and isinstance(v, dict) and v.get("counted") is True and isinstance(v.get("fight"), str):
            if v["fight"] not in self.fight_keys:
                self.fight_keys.add(v["fight"])
                died = v.get("died")
                if isinstance(died, list) and died and died[0] is True:
                    self.deaths += 1
            dur = v.get("dur")
            if isinstance(dur, list) and len(dur) == 3 and whole(dur[0]) and whole(dur[1]):
                over = dur[0] - dur[1]
                if over > 0 and (self.slowest is None or over > self.slowest[0]):
                    self.slowest = (over, str(v.get("name") or "?"), dur[0], dur[1])
        elif oid == 13:
            self.seen13 = True
            if not isinstance(v, dict):
                self.ask = None
                return
            if self.re is None and whole(v.get("re")):
                self.re = v["re"]              # started again: carry on the answered question
            if whole(v.get("seq")) and v["seq"] > self.seq:
                self.seq = v["seq"]
            if v.get("lang") in TEXT:
                self.lang = v["lang"]
            a = v.get("ask")
            self.ask = a if isinstance(a, dict) and whole(a.get("n")) and whole(a.get("t")) else None

    # --- what the program says ---
    def session_card(self, now: float) -> dict:
        t = TEXT[self.lang]
        n = len(self.fight_keys)
        fights = t["fights"][0 if n == 1 else 1].format(n=n)
        deaths = t["deaths"][0 if self.deaths == 1 else 1].format(n=self.deaths)
        xp = ""
        if self.start is not None and now - self.start >= 60:
            xp = t["xp"].format(n="{:,}".format(round(self.xp_gained * 3600 / (now - self.start))))
        money = ""
        if self.money_first is not None:
            money = t["money"].format(m=money_text(self.money_last - self.money_first))
        card = {"id": "session", "kind": "event", "prio": 3, "src": "companion", "at": int(now), "ttl": CARD_TTL,
                "text": t["session"].format(fights=fights, deaths=deaths, xp=xp, money=money),
                "basis": t["basis"].format(hm=time.strftime("%H:%M", time.localtime(self.start or now)))}
        if self.slowest:
            _, name, this, usual = self.slowest
            card["detail"] = t["slow"].format(name=name, this=this, usual=usual)
        return card

    def due(self, now: float):
        if self.session is None or not self.seen13:
            return None                       # no set before the program knows the session and the last answer
        a = self.ask
        if (self.live and a and a.get("topic") == "session" and a["n"] != self.re
                and now - a["t"] <= ANSWER_WITHIN):
            self.re = a["n"]
            self.cards = [c for c in self.cards if c["id"] != "session"] + [self.session_card(now)]
            self.changed = True
        alive = [c for c in self.cards if c["at"] + c["ttl"] > now]
        if len(alive) != len(self.cards):
            self.cards, self.changed = alive, True
        if not self.changed and self.last_write is not None and now - self.last_write < HEARTBEAT:
            return None
        if self.changed:
            self.seq += 1
        self.changed, self.last_write = False, now
        return {"session": self.session, "seq": self.seq, "re": self.re, "cards": list(self.cards)}


def events(url: str, timeout: float = 20):
    """The reader's events, and None after a quiet `timeout` (so the heartbeat still runs)."""
    with urllib.request.urlopen(url + "/events", timeout=timeout) as r:
        while True:
            try:
                raw = r.readline()
            except socket.timeout:
                yield None
                continue
            if not raw:
                return
            line = raw.decode("utf-8", "replace").strip()
            if line.startswith("data: "):
                try:
                    yield json.loads(line[6:])
                except ValueError:
                    continue
            elif line.startswith(":"):
                yield None                   # a sign of life from the reader


def run(addons: Path, reader: str, log=None, until=None):
    """Follows the reader and writes sets until `until` (a time, for tests) or for ever."""
    bot = Assistant()
    while until is None or time.time() < until:
        try:
            for e in events(reader):
                now = time.time()
                if e is not None:
                    bot.feed(e, now)
                s = bot.due(now)
                if s is not None:
                    hellolink.write(addons, None, None, quiet=True, assist=hellolink.check_assist(s))
                    if log:
                        with open(log, "a") as f:
                            f.write(json.dumps(dict(s, written=int(now))) + "\n")
                if until is not None and time.time() >= until:
                    return
        except (OSError, ValueError):
            bot.live = False
            time.sleep(min(5, max(0, (until or time.time() + 5) - time.time())))


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--addons", type=Path, required=True, help="the game's AddOns folder, with HelloLink's slots")
    ap.add_argument("--reader", default="http://127.0.0.1:8787", help="the reader's local API")
    ap.add_argument("--log", help="a file to which each set written is added, one JSON line")
    args = ap.parse_args()
    run(args.addons, args.reader.rstrip("/"), args.log)


if __name__ == "__main__":
    main()
