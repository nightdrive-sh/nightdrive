"""The companion's server: the web app's files and its API (protocol.md), on a Unix socket that only tailscaled may use;
`tailscale serve` puts it on the tailnet over HTTPS (who gets in: access.py). One thread looks at the desktop every POLL seconds and keeps the state; each page open holds a
Server-Sent Events stream that gets the whole state when it changes.
"""
import json
import mimetypes
import os
import socket
import socketserver
import subprocess
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import access
import control
import sessions

POLL = 1.5          # seconds between looks at the desktop
USAGE_EVERY = 60    # seconds between asks for the plan's usage (claude-usage caches it for two minutes itself)
KEEPALIVE = 15      # seconds between comments on a quiet event stream
WEB = os.path.join(os.path.dirname(os.path.dirname(os.path.realpath(__file__))), "web")
THEME = os.path.expanduser("~/.cache/nightdrive/theme.json")
USAGE = os.path.expanduser("~/.config/topbar/scripts/claude-usage")
# The menus' font, served to the iPad (which hasn't got it): name in the URL → fontconfig's style
FONTS = {"regular": "Regular", "medium": "Medium", "bold": "Bold"}
FONT_TYPES = {".otf": "font/otf", ".ttf": "font/ttf", ".woff2": "font/woff2", ".woff": "font/woff"}
MAX_BODY = 64 * 1024  # bytes a request's body may have: a send is at most control.MAX_TEXT characters
# The page's own files and nothing else: a text that got into the page as markup can't load or send anywhere, and no
# other page can frame it to catch a tap
SECURITY_HEADERS = {
    "Content-Security-Policy": "default-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; "
                               "object-src 'none'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'",
    "X-Content-Type-Options": "nosniff",
    "X-Frame-Options": "DENY",
    "Referrer-Policy": "no-referrer",
}
DEMO_USAGE = {"windows": [{"key": "session", "percent": 62}, {"key": "weekly", "percent": 31}]}


def font_file(style):
    try:
        path = subprocess.run(["fc-match", "-f", "%{file}", f"JetBrains Mono:style={style}"], capture_output=True,
                              text=True, timeout=5).stdout
    except (OSError, subprocess.SubprocessError):
        return None
    return path if "jetbrains" in path.lower() and os.path.splitext(path)[1] in FONT_TYPES else None


class State:
    def __init__(self, demo):
        self.demo = demo
        self.sessions = sessions.Demo() if demo else sessions.Sessions()
        self.actions = control.DEMO_CONFIG if demo else control.CONFIG
        self.cond = threading.Condition()
        self.json = "{}"
        self.version = 0
        self.usage = DEMO_USAGE if demo else {}
        self.usage_at = 0
        self.wake = threading.Event()

    def _theme(self):
        try:
            with open(THEME) as f:
                return json.load(f)
        except (OSError, ValueError):
            return {}

    def _usage(self):
        if self.demo or time.time() - self.usage_at < USAGE_EVERY:
            return self.usage
        self.usage_at = time.time()
        try:
            self.usage = json.loads(subprocess.run([USAGE], capture_output=True, timeout=20).stdout or "{}")
        except (OSError, subprocess.SubprocessError, ValueError):
            pass
        return self.usage

    def build(self):
        return {"host": socket.gethostname().split(".")[0], "demo": self.demo, "theme": self._theme(),
                "usage": self._usage(), "sessions": self.sessions.look(),
                "actions": control.public_actions(self.actions)}

    def loop(self):
        while True:
            try:
                text = json.dumps(self.build(), ensure_ascii=False)
            except Exception as e:   # a look that failed keeps the last state; the next one tries again
                print("companion: look failed:", e, flush=True)
                text = self.json
            if text != self.json:
                with self.cond:
                    self.json, self.version = text, self.version + 1
                    self.cond.notify_all()
            self.wake.wait(POLL)
            self.wake.clear()


class Handler(BaseHTTPRequestHandler):
    server_version = "NightdriveCompanion"
    state: State = None
    owner: access.Owner = None
    port = 0                # the demo's, for its Host check

    def log_message(self, fmt, *args):
        pass

    def _send(self, code, body, ctype="application/json"):
        data = body if isinstance(body, bytes) else json.dumps(body).encode()
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-cache")
        self.end_headers()
        self.wfile.write(data)

    def end_headers(self):
        for k, v in SECURITY_HEADERS.items():
            self.send_header(k, v)
        super().end_headers()

    def _allowed(self):
        if self.state.demo:
            return access.allowed_demo(self.headers, self.port)
        return access.allowed_tailnet(self.headers, self.owner)

    def do_GET(self):
        if not self._allowed():
            return self._send(403, {"error": "Only this computer's own Tailscale user"})
        path = self.path.split("?")[0]
        if path == "/api/state":
            return self._send(200, self.state.json.encode())
        if path == "/api/presets":
            return self._send(200, control.presets())
        if path == "/api/events":
            return self._events()
        if path.startswith("/fonts/"):
            return self._font(path.split("/")[-1])
        self._static(path)

    def _static(self, path):
        rel = "index.html" if path in ("", "/") else path.lstrip("/")
        full = os.path.realpath(os.path.join(WEB, rel))
        if not full.startswith(WEB + os.sep) or not os.path.isfile(full):
            return self._send(404, {"error": "Not found"})
        ctype = "application/manifest+json" if full.endswith(".webmanifest") else \
            (mimetypes.guess_type(full)[0] or "application/octet-stream")
        with open(full, "rb") as f:
            self._send(200, f.read(), ctype + ("; charset=utf-8" if ctype.startswith("text/") else ""))

    def _font(self, name):
        path = font_file(FONTS[name]) if name in FONTS else None
        if not path:
            return self._send(404, {"error": "No such font"})
        with open(path, "rb") as f:
            data = f.read()
        self.send_response(200)
        self.send_header("Content-Type", FONT_TYPES[os.path.splitext(path)[1]])
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "max-age=604800")
        self.end_headers()
        self.wfile.write(data)

    def _events(self):
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("X-Accel-Buffering", "no")
        self.end_headers()
        seen = -1
        try:
            while True:
                with self.state.cond:
                    if self.state.version == seen:
                        self.state.cond.wait(KEEPALIVE)
                    version, text = self.state.version, self.state.json
                if version != seen:
                    seen = version
                    self.wfile.write(f"event: state\ndata: {text}\n\n".encode())
                else:
                    self.wfile.write(b": keepalive\n\n")
                self.wfile.flush()
        except (BrokenPipeError, ConnectionResetError, OSError):
            pass

    def do_POST(self):
        if not self._allowed():
            return self._send(403, {"error": "Only this computer's own Tailscale user"})
        if self.headers.get("X-Companion") != "1":
            return self._send(403, {"error": "Missing X-Companion header"})
        try:
            n = int(self.headers.get("Content-Length") or 0)
            if not 0 <= n <= MAX_BODY:
                return self._send(413, {"error": "Too long"})
            body = json.loads(self.rfile.read(n) or b"null") if n else None
        except ValueError:
            return self._send(400, {"error": "The body isn't JSON"})
        parts = self.path.split("?")[0].strip("/").split("/")[1:]   # after "api"
        try:
            self._route(parts, body)
        except (ValueError, KeyError) as e:
            return self._send(400, {"error": str(e)})
        except (OSError, subprocess.SubprocessError) as e:
            return self._send(500, {"error": f"It didn't work: {e}"})
        self.state.wake.set()
        self._send(200, {"ok": True})

    def _route(self, parts, body):
        demo, ses = self.state.demo, self.state.sessions
        body = body if isinstance(body, dict) else {}
        match parts:
            case ["sessions", "new"]:
                demo or control.new_session(body.get("text", ""))
            case ["sessions", sid, ("allow" | "deny") as what]:
                perm = ses.permission(sid)
                if not perm:
                    raise ValueError("It no longer asks")
                if what == "allow" and not perm["allow"]:
                    raise ValueError("This one is answered in its terminal: it doesn't show all it allows")
                ses.answer(sid, what)
                ses.seen(sid)
            case ["sessions", sid, "send"]:
                ses.seen(sid)
                demo or control.type_text(sid, body.get("text", ""), bool(body.get("submit")))
            case ["sessions", sid, "stop"]:
                demo or control.stop(sid)
            case ["sessions", sid, "focus"]:
                ses.seen(sid)
                demo or control.focus(sid)
            case ["send"]:
                demo or control.type_text(None, body.get("text", ""), bool(body.get("submit")))
            case ["actions", n, "run"]:
                demo or control.run_action(int(n), self.state.actions)
            case ["actions", n]:
                control.set_action(int(n), body or None, self.state.actions)
            case _:
                raise ValueError("No such request")


class TailscaleServer(socketserver.ThreadingMixIn, socketserver.UnixStreamServer):
    """HTTP on a Unix socket, for tailscaled alone (access.py)."""
    daemon_threads = True

    def verify_request(self, request, client_address):
        return access.peer_uid(request) == access.TAILSCALED_UID


def serve(port, demo):
    state = State(demo)
    Handler.state = state
    threading.Thread(target=state.loop, daemon=True).start()
    if demo:
        Handler.port = port
        httpd = ThreadingHTTPServer(("127.0.0.1", port), Handler)
        httpd.daemon_threads = True
        print(f"companion: http://127.0.0.1:{port} (demo)", flush=True)
    else:
        Handler.owner = access.Owner()
        access.make_socket_dir()
        old = os.umask(0o177)       # the socket rw for its user alone; root (tailscaled) gets in regardless
        try:
            httpd = TailscaleServer(access.SOCKET, Handler)
        finally:
            os.umask(old)
        print(f"companion: {access.SOCKET}, for tailscale serve", flush=True)
    httpd.serve_forever()
