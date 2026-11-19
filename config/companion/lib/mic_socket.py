"""The dictation key's way to the app's microphone (mic.py): a Unix socket in the user's runtime folder that only this
user's processes may use (SO_PEERCRED), apart from the one tailscaled uses. One JSON line asked, one answered:

    {"op": "status"}            → {"ready": "iPad" | null, "lid": "closed" | "open"}
    {"op": "start"}             → {"id": 3, "name": "iPad"}, once the app listens; or {"error": "…"}
    {"op": "stop", "id": 3}     → {"text": "…"}: the app's words ("" when none came); without id, the one going on
    {"op": "abort"}             → {}

`companion mic …` (bin/companion) is its client, and hypr/scripts/dictate uses that.
"""
import json
import os
import socket
import socketserver
import threading

import access
import mic

SOCKET = os.path.join(access.RUNTIME, "nightdrive", "companion-mic.sock")
MAX_LINE = 4096
CLIENT_TIMEOUT = mic.START_WAIT + mic.TEXT_WAIT + 5     # seconds: the longest answer is a stop's


def answer(m, req):
    op = req.get("op") if isinstance(req, dict) else None
    if op == "status":
        dev = m.available()
        return {"ready": m.devices[dev]["name"] if dev else None, "lid": "closed" if mic.lid_closed() else "open"}
    if op == "start":
        try:
            return m.start()
        except mic.MicError as e:
            return {"error": str(e)}
    if op == "stop":
        mic_id = req.get("id")
        return {"text": m.stop(mic_id if isinstance(mic_id, int) else None)}
    if op == "abort":
        m.abort()
        return {}
    return {"error": "No such request"}


class _Handler(socketserver.StreamRequestHandler):
    def handle(self):
        line = self.rfile.readline(MAX_LINE)
        try:
            req = json.loads(line)
        except ValueError:
            req = None
        self.wfile.write((json.dumps(answer(self.server.mic, req)) + "\n").encode())


class _Server(socketserver.ThreadingMixIn, socketserver.UnixStreamServer):
    daemon_threads = True

    def verify_request(self, request, client_address):
        return access.peer_uid(request) == os.getuid()


def serve(m):
    """Listens in a thread of its own, for the server's lifetime."""
    try:
        os.unlink(SOCKET)       # a server that died leaves it behind
    except FileNotFoundError:
        pass
    old = os.umask(0o177)
    try:
        srv = _Server(SOCKET, _Handler)
    finally:
        os.umask(old)
    srv.mic = m
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    return srv


def ask(req, timeout=CLIENT_TIMEOUT):
    """The client: one request, its answer; {"error": …} when the server isn't there."""
    try:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
            s.settimeout(timeout)
            s.connect(SOCKET)
            s.sendall((json.dumps(req) + "\n").encode())
            with s.makefile("rb") as f:
                return json.loads(f.readline() or b"{}")
    except (OSError, ValueError):
        return {"error": "Companion isn't running"}
