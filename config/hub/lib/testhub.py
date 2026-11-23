"""A Hub in memory on 127.0.0.1, for the client's tests (not a server to use).

CI has only this repo, not the Hub's (~/Projects/nightdrive-hub), so the tests that sync speak to this one. It keeps
the protocol's rules the client depends on (docs/protocol.md there): one version counter, base checked on every write
and deletion, the same content is no change whatever the base, tombstones, 409 with the Hub's state, changes in
pages. e2e_test.py runs the same syncs against the real Hub when its checkout is there.
"""
import hashlib
import json
import threading
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, unquote, urlsplit


class Memory:
    def __init__(self):
        self.server_id = str(uuid.uuid4())
        self.version = 0
        self.files = {}     # (collection, path): {"version", "hash", "body", "deleted"}
        self.lock = threading.Lock()
        self.page = 1000    # changes per page; a test sets it small to see paging
        self.refuse = set()     # paths answered 400 bad_name, as the real Hub does for a name it won't take


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    # Headers and body go out in two writes: with Nagle on, each answer waits ~40 ms for the client's delayed ACK
    disable_nagle_algorithm = True
    mem = None

    def log_message(self, *a):
        pass

    def send(self, status, body=b"", headers=None, ctype="application/octet-stream"):
        if isinstance(body, dict):
            body, ctype = json.dumps(body).encode(), "application/json"
        self.send_response(status)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Hub-Server", self.mem.server_id)
        for k, v in (headers or {}).items():
            self.send_header(k, v)
        self.end_headers()
        self.wfile.write(body)

    def state(self, status, f):
        if f is None:
            return self.send(status, b"", {"Hub-Version": "0"})
        if f["deleted"]:
            return self.send(status, b"", {"Hub-Version": str(f["version"]), "Hub-Deleted": "1"})
        self.send(status, f["body"], {"Hub-Version": str(f["version"]), "Hub-Hash": f["hash"]})

    def do_GET(self):
        u = urlsplit(self.path)
        q = parse_qs(u.query)
        if u.path == "/v1/info":
            return self.send(200, {"name": "Nightdrive Hub", "protocol": 1, "server": self.mem.server_id})
        coll, _, rest = u.path[len("/v1/c/"):].partition("/")
        with self.mem.lock:
            if rest == "changes":
                since = int(q.get("since", ["0"])[0])
                rows = sorted(((k[1], f) for k, f in self.mem.files.items() if k[0] == coll and f["version"] > since),
                              key=lambda r: r[1]["version"])
                page = rows[:self.mem.page]
                cursor = page[-1][1]["version"] if page else since
                return self.send(200, {"changes": [{"path": p, "version": f["version"], "hash": f["hash"],
                                                    "size": len(f["body"]), "deleted": f["deleted"]} for p, f in page],
                                       "cursor": cursor, "more": len(rows) > len(page)})
            f = self.mem.files.get((coll, unquote(rest[len("files/"):])))
            if f is None:
                return self.send(404, {"error": "not_found", "message": "No such file"})
            self.state(410 if f["deleted"] else 200, f)

    def write(self, delete):
        u = urlsplit(self.path)
        coll, _, rest = u.path[len("/v1/c/"):].partition("/")
        path = unquote(rest[len("files/"):])
        base = int(parse_qs(u.query)["base"][0])
        body = b"" if delete else self.rfile.read(int(self.headers["Content-Length"]))
        if path in self.mem.refuse:
            return self.send(400, {"error": "bad_name", "message": "refused"})
        with self.mem.lock:
            key = (coll, path)
            f = self.mem.files.get(key)
            h = hashlib.sha256(body).hexdigest()
            if delete:
                if f is None:
                    return self.send(404, {"error": "not_found", "message": "No such file"})
                if f["deleted"]:
                    return self.send(200, {"version": f["version"], "changed": False})
            elif f and not f["deleted"] and f["hash"] == h:
                return self.send(200, {"version": f["version"], "hash": h, "size": len(body), "changed": False})
            if (f["version"] if f else 0) != base:
                return self.state(409, f)
            self.mem.version += 1
            self.mem.files[key] = {"version": self.mem.version, "hash": None if delete else h, "body": body,
                                   "deleted": delete}
            if delete:
                return self.send(200, {"version": self.mem.version, "changed": True})
            self.send(200, {"version": self.mem.version, "hash": h, "size": len(body), "changed": True})

    def do_PUT(self):
        self.write(False)

    def do_DELETE(self):
        self.write(True)


class TestHub:
    """start() → url; .mem is the Hub's content; stop()."""

    def __init__(self):
        self.mem = Memory()
        handler = type("H", (Handler,), {"mem": self.mem})
        self.server = ThreadingHTTPServer(("127.0.0.1", 0), handler)
        self.server.daemon_threads = True
        self.url = "http://127.0.0.1:%d" % self.server.server_address[1]
        threading.Thread(target=self.server.serve_forever, kwargs={"poll_interval": 0.05}, daemon=True).start()

    def live(self, coll="tasks"):
        """{path: body} of the live files."""
        return {k[1]: f["body"] for k, f in self.mem.files.items() if k[0] == coll and not f["deleted"]}

    def stop(self):
        self.server.shutdown()
        self.server.server_close()
