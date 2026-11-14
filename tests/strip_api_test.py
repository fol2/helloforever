#!/usr/bin/env python3
"""The reader's local HTTP API (#58): `GET /state` is the present state, `GET /events` is
every event as it happens (server-sent events). Read-only, this computer only, and closed to
a web page in a browser: no CORS header, and a foreign `Host` is refused.
Usage: python3 tests/strip_api_test.py"""
import contextlib
import http.client
import io
import json
import socket
import sys
import time
from pathlib import Path
from types import SimpleNamespace

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "tools"))
import hellolink_strip as hs  # noqa: E402
import strip_api              # noqa: E402

checks = fails = 0


def check(name, cond):
    global checks, fails
    checks += 1
    fails += not cond
    print(("PASS " if cond else "FAIL ") + name)


def get(port, path, host=None, method="GET"):
    """(status, headers in lower case, body as text) of one request."""
    c = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
    c.putrequest(method, path, skip_host=True)
    c.putheader("Host", host or "127.0.0.1:%d" % port)
    c.endheaders()
    r = c.getresponse()
    out = r.status, {k.lower(): v for k, v in r.getheaders()}, r.read().decode()
    c.close()
    return out


def listen(port):
    """A connection to /events, its headers read. Returns (socket, file, status line, headers)."""
    s = socket.create_connection(("127.0.0.1", port), timeout=5)
    s.sendall(b"GET /events HTTP/1.1\r\nHost: 127.0.0.1:%d\r\n\r\n" % port)
    f = s.makefile("rb")
    status, headers = f.readline().decode().strip(), {}
    while True:
        line = f.readline().decode().strip()
        if not line:
            break
        k, _, v = line.partition(":")
        headers[k.lower()] = v.strip()
    return s, f, status, headers


def events_of(f, n):
    """The next `n` events of an /events connection (comment lines are a heartbeat)."""
    got, end = [], time.time() + 10
    while len(got) < n:
        line = f.readline().decode()       # the socket's own limit ends a wait for a line
        if not line or time.time() > end:
            raise AssertionError("the events ended after %d of %d" % (len(got), n))
        if line.startswith("data: "):
            got.append(json.loads(line[6:]))
    return got


def until(what, seconds=3.0):
    end = time.time() + seconds
    while time.time() < end and not what():
        time.sleep(0.02)
    return what()


STATE = {"kind": "state", "session": 4711, "seq": 9, "depth": 4, "fast": {"clock": {"clock": 1}}, "levels": {"health": 76}}
BAGS = {"kind": "object", "id": 4, "format": 1, "text": '{"free": 12, "items": [[2318, 16]]}'}

api = strip_api.Api(0)
port = api.port
check("the server listens on 127.0.0.1 only (%s)" % (api.address,), api.address[0] == "127.0.0.1" and port > 0)

status, headers, body = get(port, "/state")
first = json.loads(body)
check("/state before any row: 200, JSON, no state, no object, condition `waiting`",
      status == 200 and headers.get("content-type", "").startswith("application/json")
      and first == {"state": None, "levels": None, "objects": {}, "condition": "waiting", "age": None})

s, f, line, sse = listen(port)
check("/events answers 200 as text/event-stream (%s)" % line, " 200 " in line + " " and sse.get("content-type", "").startswith("text/event-stream"))
check("one client is listening", until(lambda: api.clients() == 1))
told = [STATE, {"kind": "levels", "levels": {"health": 80}}, BAGS, {"kind": "stale-object", "id": 4}]
for e in told:
    api.tell(e)
got = events_of(f, 5)
check("/events gives the present first, as a `snapshot` event", got[0] == dict(first, kind="snapshot"))
check("... then every event after the connection, in order, as the JSON `watch --json` prints", got[1:] == told)

now = json.loads(get(port, "/state")[2])
check("/state has the last state", now["state"] == STATE and now["condition"] == "live" and 0 <= now["age"] < 5)
check("/state has the last levels", now["levels"] == {"health": 80})
check("/state has the object, marked stale", now["objects"] == {"4": {"format": 1, "text": BAGS["text"], "stale": True}})
api.tell({"kind": "fresh-object", "id": 4})
api.tell(dict(BAGS, text='{"free": 11, "items": []}'))
api.tell({"kind": "object", "id": 2, "format": 255, "text": None})
now = json.loads(get(port, "/state")[2])
check("a newer object replaces the older one, and is not stale", now["objects"]["4"] == {"format": 1, "text": '{"free": 11, "items": []}', "stale": False})
check("an object the addon cannot read is given as such (format 255, no text)", now["objects"]["2"] == {"format": 255, "text": None, "stale": False})
s2, f2, _, _ = listen(port)
late = events_of(f2, 1)[0]
check("a client that comes late gets the objects in its snapshot, as /state has them",
      late["kind"] == "snapshot" and {k: v for k, v in late.items() if k not in ("kind", "age")} == {k: v for k, v in now.items() if k != "age"})
api.tell({"kind": "levels", "levels": {"health": 81}})
check("... and the next event after it", events_of(f2, 1) == [{"kind": "levels", "levels": {"health": 81}}])
for kind in ("stale", "lost", "waiting"):
    api.tell({"kind": kind, "why": "no row"})
    check("after `%s` the condition is `%s`, and the last state is still given" % (kind, kind),
          (lambda d: d["condition"] == kind and d["state"] == STATE)(json.loads(get(port, "/state")[2])))
api.tell(dict(STATE, session=4712, seq=1))
now = json.loads(get(port, "/state")[2])
check("a state of a new session: live again, and the objects of the old session are gone", now["condition"] == "live" and now["objects"] == {})

# closed to everything but a local program that asks for it by its own address
check("a foreign Host is refused with 403 (DNS rebinding)", get(port, "/state", host="evil.example:%d" % port)[0] == 403)
check("... on /events too", get(port, "/events", host="evil.example")[0] == 403)
check("localhost is this server too", get(port, "/state", host="localhost:%d" % port)[0] == 200)
check("an unknown path is 404", get(port, "/nothing")[0] == 404)
check("POST is refused (%d)" % get(port, "/state", method="POST")[0], get(port, "/state", method="POST")[0] in (405, 501))
answers = [get(port, "/state"), get(port, "/nothing"), get(port, "/state", host="evil.example")]
check("no answer carries Access-Control-Allow-Origin", not any("access-control-allow-origin" in h for _, h, _ in answers + [(0, sse, "")]))

# a client that stops reading: dropped, and the reader is not held
big = dict(BAGS, text="x" * 20000)
began = time.time()
for _ in range(4000):                       # 80 MB to a client that reads nothing
    api.tell(big)
took = time.time() - began
check("telling 4000 large events to a client that does not read takes no time (%.2f s)" % took, took < 2.0)
check("... and that client is dropped", until(lambda: api.clients() == 0))
check("the server still answers", get(port, "/state")[0] == 200)
s.close()
s2.close()                                  # both were dropped above
s3, f3, _, _ = listen(port)                 # a new client, which waits for an event
events_of(f3, 1)
check("a new client is listening again", until(lambda: api.clients() == 1))
began = time.time()
api.close()
try:
    rest = f3.read()                        # to the end of the connection
    ended = time.time() - began
except OSError:
    ended = 99
check("close ends a client that waits for an event, at once (%.1f s)" % ended, ended < 3)
s3.close()
try:
    get(port, "/state")
    closed = False
except OSError:
    closed = True
check("after close the port is free", closed)

# a client that says nothing does not keep its thread: every read and write has a limit
real_wait, strip_api.SEND_WAIT = strip_api.SEND_WAIT, 0.3
quick = strip_api.Api(0)
strip_api.SEND_WAIT = real_wait
mute = socket.create_connection(("127.0.0.1", quick.port), timeout=5)
began = time.time()
try:
    gone = mute.recv(1) == b""
except OSError:
    gone = False
check("a client that sends no request is cut off after the limit (%.1f s)" % (time.time() - began), gone and time.time() - began < 3)
mute.close()
quick.close()

# `watch --serve`: what it prints is what it tells the API
heard, clock = [], [1000.0]


class Enough(Exception):
    pass


class Heard:
    port = 1

    def __init__(self, port):
        heard.append(("port", port))

    def tell(self, event):
        heard.append(event)

    def close(self):
        heard.append("closed")


def sleep(seconds):
    clock[0] += seconds
    if clock[0] > 1150:
        raise Enough


real = hs.capture_tool, hs.locate, time.monotonic, time.sleep, strip_api.Api
hs.capture_tool, hs.locate = (lambda _: (Path("tool"), None)), (lambda _: (None, "no row on any display"))
time.monotonic, time.sleep, strip_api.Api = (lambda: clock[0]), sleep, Heard
out = io.StringIO()
try:
    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(io.StringIO()):
        hs.watch(SimpleNamespace(fps=60, json=True, addons=None, capture=None, serve=8787))
except Enough:
    pass
finally:
    hs.capture_tool, hs.locate, time.monotonic, time.sleep, strip_api.Api = real
printed = [json.loads(l) for l in out.getvalue().splitlines()]
check("`watch --serve 8787` starts the API on that port", heard[:1] == [("port", 8787)])
check("... tells it every event it prints (%d)" % len(printed), len(printed) == 4 and [e for e in heard if isinstance(e, dict)] == printed)
check("... and the first is the `waiting` said at the start (#80)", printed[:1] == [{"kind": "waiting", "why": "looking for the row"}])
check("... and closes it when the reader ends", heard[-1] == "closed")



class Broken(io.StringIO):
    def write(self, _):
        raise BrokenPipeError("stderr is gone")


del heard[:]
strip_api.Api = Heard
try:
    with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(Broken()):
        hs.watch(SimpleNamespace(fps=60, json=True, addons=None, capture=None, serve=8787))
except BrokenPipeError:
    pass
finally:
    strip_api.Api = real[4]
check("a start-up message that cannot be written still closes the API (%s)" % heard, heard == [("port", 8787), "closed"])

print("== %d checks, %d failed" % (checks, fails))
sys.exit(1 if fails else 0)
