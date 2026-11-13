"""The reader's local HTTP API (docs/STRIP.md, section 10): one reader, any number of local
programs. One display takes one capture stream, so a second reader is not a way.

    GET /state    the present: the last state, the last levels, the last of each object,
                  the row's condition and the age of the state in seconds
    GET /events   server-sent events, `data: <JSON>` and an empty line: first the present
                  (`{"kind": "snapshot", ...}`, what /state gives), then every event after
                  it, the JSON that `watch --json` prints; nothing is missed in between

Read-only, and for this computer only: it listens on 127.0.0.1, sends no CORS header (a web
page in a browser cannot read the answer) and refuses a request whose Host is not this
server (a web page that points its own name at 127.0.0.1). Nothing is kept on disk.
"""
import json
import queue
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

QUEUE = 1000        # events a client may be behind before it is dropped
HEARTBEAT = 15.0    # seconds without an event before a comment line is sent
SEND_WAIT = 10.0    # seconds a client gets for one read or write, on every route
NAMES = ("127.0.0.1", "localhost")


class Api:
    def __init__(self, port: int):
        self.lock = threading.Lock()
        self.listeners = []          # (queue, gone) of each /events client
        self.state = self.levels = self.when = None
        self.objects = {}
        self.condition = "waiting"   # live, stale, lost or waiting
        self.closed = False
        api = self

        class Handler(BaseHTTPRequestHandler):
            timeout = SEND_WAIT              # of the connection, set before the request is read

            def log_message(self, *_):       # the reader's stderr is for the reader
                pass

            def answer(self, code, kind, body=b""):
                self.send_response(code)
                self.send_header("Content-Type", kind)
                self.send_header("Cache-Control", "no-store")
                if kind != "text/event-stream":
                    self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

            def do_GET(self):
                try:
                    self.get()
                except OSError:              # the client left, or did not read for SEND_WAIT
                    pass

            def get(self):
                name, _, port = self.headers.get("Host", "").strip().lower().partition(":")
                if name not in NAMES or (port and port != str(api.port)):
                    return self.answer(403, "text/plain", b"this server answers to 127.0.0.1 and localhost only\n")
                if self.path == "/state":
                    return self.answer(200, "application/json", (json.dumps(api.snapshot(), ensure_ascii=False) + "\n").encode())
                if self.path != "/events":
                    return self.answer(404, "text/plain", b"GET /state or GET /events\n")
                mine = (queue.Queue(maxsize=QUEUE), threading.Event())
                with api.lock:               # the present and the place in the line, as one step
                    if api.closed:
                        return self.answer(503, "text/plain", b"the reader is leaving\n")
                    mine[0].put(dict(api.present(), kind="snapshot"))
                    api.listeners.append(mine)
                try:
                    self.answer(200, "text/event-stream")
                    while not mine[1].is_set():
                        try:
                            event = mine[0].get(timeout=HEARTBEAT)
                            if event is None:        # dropped or closed: wake and leave
                                break
                            line = "data: %s\n\n" % json.dumps(event, ensure_ascii=False, sort_keys=True)
                        except queue.Empty:
                            line = ": still here\n\n"
                        self.wfile.write(line.encode())
                        self.wfile.flush()
                finally:
                    api.drop(mine)

        self.server = ThreadingHTTPServer(("127.0.0.1", port), Handler)
        self.server.daemon_threads = True
        self.address = self.server.server_address
        self.port = self.address[1]
        threading.Thread(target=self.server.serve_forever, daemon=True).start()

    @staticmethod
    def leave(listener):
        """Tells a listener's thread to end, and wakes it when it waits for an event."""
        listener[1].set()
        try:
            listener[0].put_nowait(None)
        except queue.Full:                   # it is writing: it sees the flag after the write
            pass

    def drop(self, listener):
        self.leave(listener)
        with self.lock:
            if listener in self.listeners:
                self.listeners.remove(listener)

    def clients(self) -> int:
        with self.lock:
            return len(self.listeners)

    def present(self):
        """The present; the caller holds the lock. Events are never changed after `tell`."""
        return {"state": self.state, "levels": self.levels, "objects": {str(k): dict(v) for k, v in self.objects.items()},
                "condition": self.condition, "age": None if self.when is None else round(time.monotonic() - self.when, 2)}

    def snapshot(self):
        with self.lock:
            return self.present()

    def tell(self, event):
        """Takes one event of the reader. Never waits: a client that is QUEUE events behind is
        dropped (it reads /state and listens again)."""
        kind = event.get("kind")
        with self.lock:
            if kind == "state":
                if self.state is not None and self.state.get("session") != event.get("session"):
                    self.objects = {}        # the UI loaded again: its objects come anew
                self.state, self.when, self.condition = event, time.monotonic(), "live"
                self.levels = event.get("levels", self.levels)
            elif kind == "levels":
                self.levels = event.get("levels")
            elif kind == "object":
                self.objects[event["id"]] = {"format": event.get("format"), "text": event.get("text"), "stale": False}
            elif kind in ("stale-object", "fresh-object") and event.get("id") in self.objects:
                self.objects[event["id"]]["stale"] = kind == "stale-object"
            elif kind in ("stale", "lost", "waiting"):
                self.condition = kind
            for listener in self.listeners[:]:
                try:
                    listener[0].put_nowait(event)
                except queue.Full:
                    self.leave(listener)
                    self.listeners.remove(listener)

    def close(self):
        with self.lock:
            self.closed = True               # no new listener after this
            for listener in self.listeners:
                self.leave(listener)
            self.listeners = []
        self.server.shutdown()
        self.server.server_close()
