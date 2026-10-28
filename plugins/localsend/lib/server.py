"""The receiver's HTTPS server: LocalSend's v2 API (github.com/localsend/protocol) over receiver.Receiver. The bodies are
bounded: a JSON request by JSON_MAX, an upload by the size its prepare-upload gave, so no sender can fill the disk or
the memory past what was shown on the code card."""
import ipaddress
import json
import ssl
import sys
import threading
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from common import PORT, info, remember
from receiver import Receiver, TooBig

CHUNK = 1 << 20
JSON_MAX = 4 << 20           # bytes of a JSON request: a prepare-upload of a few thousand files, or a long text
HANDSHAKE_TIMEOUT = 20       # seconds for the TLS handshake
DRAIN_MAX = 1 << 20          # bytes of a refused body still read, so the sender gets the answer (see drain)
IDLE_TIMEOUT = 300           # seconds a connection may sit without sending (the phone's user typing the code)


def local(ip):
    """A sender on this network (private or link-local), not one from the internet (a public address: a firewall
    that lets the port through, a VPN)."""
    try:
        a = ipaddress.ip_address(ip)
    except ValueError:
        return False
    return a.is_private or a.is_link_local


def handler(r):
    class Handler(BaseHTTPRequestHandler):
        protocol_version = "HTTP/1.1"
        timeout = IDLE_TIMEOUT

        def log_message(self, fmt, *a):
            print(f"{self.client_address[0]} {fmt % a}", flush=True)   # the journal: journalctl --user -u nightdrive-localsend

        def reply(self, code, data=None):
            body = json.dumps(data).encode() if data is not None else b""
            self.send_response(code)
            if data is not None:
                self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            if self.close_connection:
                self.send_header("Connection", "close")
            self.end_headers()
            self.wfile.write(body)

        def length(self):
            """The Content-Length: None without one, -1 when it's broken."""
            v = self.headers.get("Content-Length")
            if v is None:
                return None
            return int(v) if v.strip().isdigit() else -1

        def read_json(self):
            """(the JSON body or None, an error status or None). A body not read is left on the connection, so an
            error closes it."""
            n = self.length() or 0
            if n < 0 or "chunked" in (self.headers.get("Transfer-Encoding") or "").lower():
                self.close_connection = True
                return None, 400
            if n > JSON_MAX:
                self.close_connection = True
                return None, 413
            try:
                return json.loads(self.rfile.read(n) or b"{}"), None
            except ValueError:
                return None, 400

        def body(self, limit):
            """The request body in pieces, at most limit bytes (TooBig past it): a Content-Length, or chunked (LocalSend on
            iOS sends files without a length)."""
            if "chunked" in (self.headers.get("Transfer-Encoding") or "").lower():
                while True:
                    size = int(self.rfile.readline(1024).split(b";")[0].strip() or b"x", 16)   # ValueError: broken
                    if size < 0:
                        raise ValueError("negative chunk size")
                    if size == 0:
                        while self.rfile.readline(1024).strip():   # trailers up to the empty line
                            pass
                        return
                    limit -= size
                    if limit < 0:
                        raise TooBig()
                    while size > 0:
                        chunk = self.rfile.read(min(CHUNK, size))
                        if not chunk:
                            raise OSError("connection closed")
                        size -= len(chunk)
                        yield chunk
                    self.rfile.readline(1024)   # the CRLF after the chunk
            else:
                left = self.length() or 0
                if left < 0:
                    raise ValueError("broken Content-Length")
                if left > limit:
                    raise TooBig()
                while left > 0:
                    chunk = self.rfile.read(min(CHUNK, left))
                    if not chunk:
                        raise OSError("connection closed")
                    left -= len(chunk)
                    self.unread = left
                    yield chunk

        def drain(self):
            """Reads what's left of a short refused body: closing with it unread resets the connection, and the sender
            sees that instead of the answer. A long one is left: its sender gets the reset."""
            left = self.length() if self.unread is None else self.unread
            if left and 0 < left <= DRAIN_MAX and "chunked" not in (self.headers.get("Transfer-Encoding") or "").lower():
                try:
                    self.rfile.read(left)
                except OSError:
                    pass

        def route(self):
            u = urllib.parse.urlsplit(self.path)
            return u.path.rstrip("/"), dict(urllib.parse.parse_qsl(u.query))

        def do_GET(self):
            path, _ = self.route()
            if path in ("/api/localsend/v2/info", "/api/localsend/v1/info"):
                self.reply(200, info(full=False))
            else:
                self.reply(404)

        def do_POST(self):
            path, q = self.route()
            ip = self.client_address[0]
            if path in ("/api/localsend/v2/register", "/api/localsend/v2/prepare-upload"):
                body, err = self.read_json()
                if err or not isinstance(body, dict):
                    self.reply(err or 400)
                elif path.endswith("/register"):
                    remember(ip, body, r.fingerprint)
                    self.reply(200, info(full=False))
                else:
                    self.reply(*r.prepare(ip, body, q.get("pin", "")))
            elif path == "/api/localsend/v2/upload":
                self.unread = None
                code = r.upload(ip, q, self.length(), self.body)
                if code != 200:
                    self.drain()
                    self.close_connection = True   # what's left of the body isn't read
                self.reply(code)
            elif path == "/api/localsend/v2/cancel":
                self.reply(r.cancel(ip, q))
            else:
                self.close_connection = True
                self.reply(404)
    return Handler


class Server(ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True

    def __init__(self, receiver):
        super().__init__(("", PORT), handler(receiver))
        self.ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        self.ctx.load_cert_chain(receiver.cert, receiver.key)

    def handle_error(self, request, client_address):
        print(f"{client_address[0]} connection error: {sys.exc_info()[1]!r}", flush=True)   # a sender gone mid-request

    def verify_request(self, request, client_address):
        return local(client_address[0])

    def finish_request(self, request, client_address):
        # TLS in the request's own thread: a slow or stuck handshake doesn't hold up the others
        request.settimeout(HANDSHAKE_TIMEOUT)
        try:
            request = self.ctx.wrap_socket(request, server_side=True)
        except (ssl.SSLError, OSError):
            return
        super().finish_request(request, client_address)


def run():
    r = Receiver()
    server = Server(r)
    threading.Thread(target=r.multicast, daemon=True).start()
    print(f"LocalSend: {info()['alias']} on port {PORT}, files to {r.dest}", flush=True)
    server.serve_forever()
