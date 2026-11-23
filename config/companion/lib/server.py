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
import zlib
from urllib.parse import parse_qs, unquote
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import access
import control
import inbox
import media
import mic
import mic_socket
import presence
import sessions

POLL = 1.5          # seconds between looks at the desktop
USAGE_EVERY = 60    # seconds between asks for the plan's usage (claude-usage caches it for two minutes itself)
KEEPALIVE = 15      # seconds between pings on a quiet event stream: the page reconnects when they stop
FRESH_WAIT = 5      # seconds a page opening the stream waits for a look made after it came, before the last one
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
DEMO_USAGE = [{"account": "default", "windows": [{"key": "session", "percent": 62}, {"key": "weekly", "percent": 31}]},
              {"account": "work", "windows": [{"key": "session", "percent": 8}, {"key": "weekly", "percent": 74}]}]


def web_version():
    """A stamp of the page's files (names, sizes, times): it changes with any of them, and a page open with another
    one offers to reload. A few stats a look, nothing read."""
    parts = []
    for name in sorted(os.listdir(WEB)):
        try:
            st = os.stat(os.path.join(WEB, name))
        except OSError:
            continue
        parts.append(f"{name}:{st.st_size}:{st.st_mtime_ns}")
    return format(zlib.crc32("|".join(parts).encode()), "08x")   # not hash(): it changes with each start


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
        self.presence = presence.Demo() if demo else presence.Presence()
        self.presence_file = None if demo else presence.StateFile()   # for claude-notify (#3065); not the demo's
        self.inbox = inbox.Demo() if demo else inbox.Inbox()
        self.cond = threading.Condition()
        self.mic = mic.Mic(self.cond)     # the app as the computer's microphone (mic.py)
        self.actions = control.DEMO_CONFIG if demo else control.CONFIG
        self.json = "{}"
        self.version = 0
        self.usage = DEMO_USAGE if demo else []
        self.usage_at = 0
        self.wake = threading.Event()
        self.watchers = 0          # pages with the event stream open: with none, no looks at all
        self.built = 0.0           # when the last look finished

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
            # every account's, as the Claude menu shows them: [{account, windows: [{key, percent, resetsAt}]}]
            got = json.loads(subprocess.run([USAGE, "--all"], capture_output=True, timeout=20).stdout or "[]")
            self.usage = got if isinstance(got, list) else [got]
        except (OSError, subprocess.SubprocessError, ValueError):
            pass
        return self.usage

    def build(self):
        return {"host": socket.gethostname().split(".")[0], "demo": self.demo, "theme": self._theme(),
                "usage": self._usage(), "sessions": self.sessions.look(), "active": self.sessions.active,
                # away from the computer (locked, idle, or as set on the page): a tile's tap opens its view there
                "presence": self.presence.look(),
                # Nightdrive Inbox's unread count, and a stamp: the page reads the list again when it changes (inbox.py)
                "inbox": self.inbox.state(),
                # the lid is closed: the dictation key wants the app's microphone (mic.py), and the app keeps awake
                "mic": {"wanted": not self.demo and mic.lid_closed()},
                "actions": control.public_actions(self.actions), "web": web_version()}

    def loop(self):
        while True:
            if self.watchers:
                try:
                    built = self.build()
                    text = json.dumps(built, ensure_ascii=False)
                    if self.presence_file:
                        self.presence_file.write(built["presence"])
                except Exception as e:   # a look that failed keeps the last state; the next one tries again
                    print("companion: look failed:", e, flush=True)
                    text = self.json
                with self.cond:
                    if text != self.json:
                        self.json, self.version = text, self.version + 1
                    self.built = time.time()
                    self.cond.notify_all()
            elif self.presence_file:
                self.presence_file.remove()     # nobody looks now: the hook goes by the window, as without Companion
            # Nobody watching: no looks until a page opens the stream. A look runs claude-sessions, ~0.3 s of CPU:
            # every POLL seconds all day, a fifth of a core on a laptop's battery for a page nobody had open.
            self.wake.wait(POLL if self.watchers else None)
            self.wake.clear()

    def watch(self, delta):
        """A page opened (1) or closed (-1) the event stream; the loop wakes either way, a new page gets a look at once."""
        with self.cond:
            self.watchers += delta
        self.wake.set()


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
            # the app's page, ready to be the computer's microphone, gets its commands on its stream (mic.py)
            query = parse_qs(self.path.partition("?")[2])
            return self._events(None if self.state.demo else mic.device_id((query.get("mic") or [None])[0]))
        parts = path.strip("/").split("/")
        if len(parts) == 4 and parts[:2] == ["api", "sessions"] and parts[3] in ("log", "permission"):
            ses = self.state.sessions
            try:
                # permission: the request whole, for Review before its Allow (permission.py)
                return self._send(200, ses.log(parts[2]) if parts[3] == "log" else ses.request(ses.window(parts[2])))
            except ValueError as e:
                return self._send(404, {"error": str(e)})
        if parts[:2] == ["api", "inbox"]:
            return self._inbox(parts[2:])
        if path.startswith("/fonts/"):
            return self._font(path.split("/")[-1])
        self._static(path)

    def _inbox(self, parts):
        """GET /api/inbox (the list), /api/inbox/ID (a message whole), /api/inbox/ID/files/NAME (one of its files)."""
        box = self.state.inbox
        try:
            if not parts:
                return self._send(200, box.list())
            if len(parts) == 1:
                return self._send(200, box.show(parts[0]))
            if len(parts) == 3 and parts[1] == "files":
                path, ctype = box.file(parts[0], unquote(parts[2]))
                # ?as=m4a: audio Safari can't play (Ogg), converted; ranges either way, for <audio>/<video> (media.py)
                if parse_qs(self.path.partition("?")[2]).get("as") == ["m4a"]:
                    path, ctype = media.as_m4a(path, ctype), "audio/mp4"
                return media.send(self, path, ctype)
        except (inbox.InboxError, media.MediaError) as e:
            return self._send(404, {"error": str(e)})
        except (OSError, subprocess.SubprocessError, ValueError) as e:
            return self._send(500, {"error": f"Inbox didn't answer: {e}"})
        return self._send(404, {"error": "Not found"})

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

    def _events(self, device=None):
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("X-Accel-Buffering", "no")
        self.end_headers()
        seen = -1
        came = time.time()
        self.state.watch(1)
        m = self.state.mic
        token = m.open(device) if device else None
        try:
            with self.state.cond:        # the desktop as it is now, not as it was when the last page went
                self.state.cond.wait_for(lambda: self.state.built >= came, timeout=FRESH_WAIT)
            while True:
                with self.state.cond:
                    if self.state.version == seen and not m.pending(device, token):
                        self.state.cond.wait(KEEPALIVE)
                    version, text = self.state.version, self.state.json
                    commands = m.take(device, token)
                for c in commands:
                    self.wfile.write(f"event: mic\ndata: {json.dumps(c)}\n\n".encode())
                if version != seen:
                    seen = version
                    self.wfile.write(f"event: state\ndata: {text}\n\n".encode())
                elif not commands:
                    self.wfile.write(b"event: ping\ndata:\n\n")    # an event, not a comment: the page sees it
                self.wfile.flush()
        except (BrokenPipeError, ConnectionResetError, OSError):
            pass
        finally:
            if device:
                m.close(device, token)
            self.state.watch(-1)

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
                perm = ses.permission(ses.window(sid))
                if not perm:
                    raise ValueError("It no longer asks")
                # the request the page showed: the state is up to POLL old, and a newer one may be waiting
                if perm["request"] != body.get("request"):
                    raise ValueError("It asks something else now: read it again")
                if what == "allow" and not perm["allow"]:
                    raise ValueError("This one is answered in its terminal: it doesn't show all it allows")
                ses.answer(sid, what, perm["request"])
                ses.seen(sid)
            case ["sessions", sid, "reply"]:
                # a question with choices: the answers for the request the page showed (sessions.check_answers)
                ses.reply(ses.window(sid), body.get("request"), body.get("answers"))
                ses.seen(sid)
            case ["sessions", sid, "send"]:
                ses.seen(ses.window(sid))
                if demo:
                    ses.typed(sid, body.get("text", ""))
                else:
                    control.type_text(sid, body.get("text", ""), bool(body.get("submit")))
            case ["sessions", sid, "stop"]:
                demo or control.stop(ses.window(sid))
            case ["sessions", sid, "close"]:
                demo or control.close_window(ses.window(sid))
            case ["sessions", sid, "focus"]:
                ses.seen(ses.window(sid))
                demo or control.focus(sid)
            case ["send"]:
                # "session": Enter only when the window that has the keyboard is a session's (the dictation button)
                submit = ses.active_is_session() if body.get("submit") == "session" else bool(body.get("submit"))
                demo or control.type_text(None, body.get("text", ""), submit)
            case ["mic"]:
                # the app's page is shown (ready: true, every few seconds) or went (false): mic.py
                device = mic.device_id(body.get("device"))
                if not device:
                    raise ValueError("No device")
                demo or self.state.mic.ready(device, body.get("name"), bool(body.get("ready")))
            case ["mic", "event"]:
                device = mic.device_id(body.get("device"))
                if not device or not isinstance(body.get("id"), int):
                    raise ValueError("No device")
                demo or self.state.mic.event(device, body["id"], body.get("type"), body.get("text", ""),
                                             body.get("error", ""))
            case ["inbox", mid, ("read" | "unread") as what]:
                self.state.inbox.read(mid, unread=what == "unread")
            case ["inbox", mid, ("archive" | "unarchive") as what]:
                self.state.inbox.archive(mid, undo=what == "unarchive")
            case ["presence"]:
                self.state.presence.set(body.get("away"))
            case ["actions", n, "run"]:
                demo or control.run_action(int(n), self.state.actions)
            case ["actions", n]:
                control.set_action(int(n), body or None, self.state.actions)
            case _:
                raise ValueError("No such request")


class TailscaleServer(socketserver.ThreadingMixIn, socketserver.UnixStreamServer):
    """HTTP on a Unix socket, for tailscaled alone (access.py)."""
    daemon_threads = True
    # A page load dials once per file, all at once, and tailscaled doesn't wait on a full backlog: it answers 502. With
    # socketserver's 5, a module now and then failed, and one failed import stops the whole page (#3080)
    request_queue_size = socket.SOMAXCONN

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
        mic_socket.serve(state.mic)     # the dictation key's way to the app's microphone
        old = os.umask(0o177)       # the socket rw for its user alone; root (tailscaled) gets in regardless
        try:
            httpd = TailscaleServer(access.SOCKET, Handler)
        finally:
            os.umask(old)
        print(f"companion: {access.SOCKET}, for tailscale serve", flush=True)
    httpd.serve_forever()
