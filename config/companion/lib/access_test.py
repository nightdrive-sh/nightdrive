"""Who gets into Companion's server (access.py): only tailscaled on the socket, only the owner's login through it.

    python3 config/companion/lib/access_test.py
"""
import os
import socket
import sys
import tempfile
import threading
import unittest
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import access  # noqa: E402
import server  # noqa: E402

OWNER = "me@example.com"


class Headers(dict):
    """A request's headers as BaseHTTPRequestHandler gives them: get() by name."""


def owner(login):
    o = access.Owner()
    o.login, o.at = login, 1e18     # known, and not asked again
    return o


class TailnetTest(unittest.TestCase):
    def test_owner_gets_in(self):
        self.assertTrue(access.allowed_tailnet(Headers({"Tailscale-User-Login": OWNER}), owner(OWNER)))

    def test_no_login_is_refused_not_taken_as_local(self):
        # a tagged device or Funnel: tailscale serve sets no login
        self.assertFalse(access.allowed_tailnet(Headers(), owner(OWNER)))
        self.assertFalse(access.allowed_tailnet(Headers({"Tailscale-User-Login": ""}), owner(OWNER)))

    def test_another_user_is_refused(self):
        self.assertFalse(access.allowed_tailnet(Headers({"Tailscale-User-Login": "friend@example.com"}), owner(OWNER)))

    def test_unknown_owner_lets_no_one_in(self):
        self.assertFalse(access.allowed_tailnet(Headers({"Tailscale-User-Login": OWNER}), owner(None)))

    def test_owner_asked_again_after_a_failure(self):
        o = access.Owner()
        with mock.patch.object(access, "tailscale_owner", side_effect=[None, OWNER]) as ask, \
                mock.patch.object(access, "time", mock.Mock(**{"time.side_effect": [1000, 1000, 1001, 1030, 1030]})):
            self.assertIsNone(o.get())
            self.assertIsNone(o.get())          # not asked again at once
            self.assertEqual(o.get(), OWNER)
        self.assertEqual(ask.call_count, 2)

    def test_requests_in_parallel_wait_for_the_first_ask(self):
        # Right after a restart the page reconnects with its state and its stream at once: the one that doesn't ask
        # must not take the login not yet known for a refusal (#3081)
        o, asked = access.Owner(), threading.Event()

        def slow_owner():
            asked.set()
            threading.Event().wait(0.2)     # tailscale status takes a moment
            return OWNER

        got = []
        with mock.patch.object(access, "tailscale_owner", side_effect=slow_owner) as ask:
            first = threading.Thread(target=lambda: got.append(o.get()))
            first.start()
            asked.wait(2)
            got.append(o.get())
            first.join()
        self.assertEqual(got, [OWNER, OWNER])
        self.assertEqual(ask.call_count, 1)


class DemoTest(unittest.TestCase):
    def test_own_host_only(self):
        self.assertTrue(access.allowed_demo(Headers({"Host": "127.0.0.1:8746"}), 8746))
        self.assertTrue(access.allowed_demo(Headers({"Host": "localhost:8746"}), 8746))
        # a rebound name (a web page's) or none at all
        self.assertFalse(access.allowed_demo(Headers({"Host": "evil.example:8746"}), 8746))
        self.assertFalse(access.allowed_demo(Headers(), 8746))


class SocketTest(unittest.TestCase):
    """The real server on a socket: a peer that isn't TAILSCALED_UID gets nothing, not even an answer."""

    def serve(self):
        folder = tempfile.mkdtemp()
        path = os.path.join(folder, "s.sock")
        state = mock.Mock(demo=False, json="{}")
        handler = type("H", (server.Handler,), {"state": state, "owner": owner(OWNER)})
        httpd = server.TailscaleServer(path, handler)
        threading.Thread(target=httpd.serve_forever, daemon=True).start()
        self.addCleanup(httpd.server_close)
        self.addCleanup(httpd.shutdown)
        return path

    def get(self, path, login=None):
        with socket.socket(socket.AF_UNIX) as s:
            s.settimeout(5)
            s.connect(path)
            extra = f"Tailscale-User-Login: {login}\r\n" if login else ""
            out = b""
            try:
                s.sendall(f"GET /api/state HTTP/1.0\r\nHost: x\r\n{extra}\r\n".encode())
                while chunk := s.recv(4096):
                    out += chunk
            # Refused: the server closes a peer it won't serve as soon as it accepts it, so depending on who gets there
            # first the request can't be sent (BrokenPipe) or the close comes as a reset (ConnectionReset). Either way
            # nothing came back, which is what the caller checks; a served request's answer is read before its close.
            except (BrokenPipeError, ConnectionResetError):
                pass
            return out.decode()

    @unittest.skipIf(os.getuid() == 0, "running as root: the peer is tailscaled's uid")
    def test_other_peer_refused(self):
        path = self.serve()
        self.assertEqual(self.get(path, OWNER), "")

    def test_tailscaled_with_owner(self):
        path = self.serve()
        with mock.patch.object(access, "TAILSCALED_UID", os.getuid()):     # this test plays tailscaled
            self.assertIn(" 200 ", self.get(path, OWNER).splitlines()[0])
            self.assertIn(" 403 ", self.get(path, "friend@example.com").splitlines()[0])
            self.assertIn(" 403 ", self.get(path).splitlines()[0])

    def test_page_load_burst_fits_the_backlog(self):
        """A page load asks for all its files at once, and tailscaled dials without waiting (EAGAIN → 502). With
        socketserver's backlog of 5 a module now and then got a 502, and one failed import stops the whole page: only
        index.html's static Dictate showed (#3080). Nothing is accepted here, so every dial must fit the backlog."""
        folder = tempfile.mkdtemp()
        path = os.path.join(folder, "s.sock")
        httpd = server.TailscaleServer(path, server.Handler)
        self.addCleanup(httpd.server_close)
        burst = 2 * len(os.listdir(server.WEB))     # every file of the page, twice over: room to grow
        clients = []
        try:
            for _ in range(burst):
                c = socket.socket(socket.AF_UNIX)
                clients.append(c)
                c.setblocking(False)
                c.connect(path)         # BlockingIOError when the backlog is full
        finally:
            for c in clients:
                c.close()

    def test_security_headers(self):
        path = self.serve()
        with mock.patch.object(access, "TAILSCALED_UID", os.getuid()):
            out = self.get(path, OWNER)
        self.assertIn("frame-ancestors 'none'", out)
        self.assertIn("X-Content-Type-Options: nosniff", out)


if __name__ == "__main__":
    unittest.main()
