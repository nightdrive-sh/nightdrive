#!/usr/bin/env python3
"""Who may knock, and when a connection is the device's (#1926): `python3 plugins/vnc-display/lib/gate_test.py`.
A peer outside Tailscale's ranges (or the home subnet) is refused before the display is made, a peer over its rate or a
listener past its cap too, and a connection keeps the display only once wayvnc lists a new client, or for AUTH_WAIT
seconds. No wayvnc, Hyprland or network needed: the listener runs on 127.0.0.1 and wayvnc's client list is faked."""

import shutil
import socket
import sys
import tempfile
import time
import unittest
from ipaddress import ip_network
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent))
import listener as L  # noqa: E402
from gate import TAILSCALE, Rate, allowed, subnet  # noqa: E402


class Addresses(unittest.TestCase):
    def test_tailscale_ranges(self):
        for host in ("100.64.0.1", "100.101.102.103", "100.127.255.254", "fd7a:115c:a1e0::1",
                     "fd7a:115c:a1e0:ab12:4843:cd96:6258:b240", "fd7a:115c:a1e0::1%tailscale0", "::ffff:100.100.1.1"):
            with self.subTest(host=host):
                self.assertTrue(allowed(host, TAILSCALE))

    def test_lan_and_the_rest_refused(self):
        for host in ("192.168.1.50", "10.0.0.2", "100.63.255.255", "100.128.0.0", "127.0.0.1", "::1",
                     "fd7a:115c:a1e1::1", "fe80::1%wlan0", "::ffff:192.168.1.50", "", "not an address"):
            with self.subTest(host=host):
                self.assertFalse(allowed(host, TAILSCALE))

    def test_home_subnet(self):
        home = subnet("192.168.1.20/24")
        self.assertEqual(home, (ip_network("192.168.1.0/24"),))
        self.assertTrue(allowed("192.168.1.77", home))
        self.assertFalse(allowed("192.168.2.77", home))
        self.assertFalse(allowed("100.100.1.1", home))   # the home listener isn't Tailscale's
        self.assertEqual(subnet(""), ())   # nmcli gave nothing: nobody
        self.assertFalse(allowed("192.168.1.77", subnet("")))


class Rates(unittest.TestCase):
    def test_per_peer_and_window(self):
        now = [0.0]
        rate = Rate(3, 60, clock=lambda: now[0])
        self.assertEqual([rate.allow("100.64.0.1") for _ in range(4)], [True, True, True, False])
        self.assertTrue(rate.allow("100.64.0.2"))   # another peer has its own share
        now[0] = 61
        self.assertTrue(rate.allow("100.64.0.1"))   # the window moved on
        self.assertNotIn("100.64.0.2", rate.seen)   # and the quiet peer was forgotten


class Fixture(unittest.TestCase):
    """A listener on 127.0.0.1 with its own networks, and wayvnc's client list as self.clients."""

    def setUp(self):
        patcher = mock.patch.object(L, "log")   # the service's journal lines, not the test's output
        patcher.start()
        self.addCleanup(patcher.stop)
        self.clients = set()
        self.l = L.Listener("t", "tailscale", {"port": "0"}, True, "/nonexistent", "", 60, Rate())
        self.l.ids = lambda: set(self.clients)
        self.l.path = lambda ext: self.vnc_path
        self.l.listen("127.0.0.1")
        self.addCleanup(self.l.close)
        self.port = self.l.sock.getsockname()[1]
        # wayvnc's unix socket: a server that holds whatever comes
        tmp = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, tmp)
        self.vnc_path = str(Path(tmp, "vnc"))
        self.vnc = socket.socket(socket.AF_UNIX)
        self.vnc.bind(self.vnc_path)
        self.vnc.listen(8)
        self.addCleanup(self.vnc.close)

    def knock(self):
        c = socket.create_connection(("127.0.0.1", self.port))
        self.addCleanup(c.close)
        return c


class Accept(Fixture):
    def test_out_of_range_refused_before_anything(self):
        self.l.networks = TAILSCALE   # 127.0.0.1 is not Tailscale's
        c = self.knock()
        self.assertIsNone(self.l.accept())
        c.settimeout(2)
        self.assertEqual(c.recv(1), b"")   # closed at once
        self.assertEqual(self.l.rate.seen, {})   # and it used up nobody's rate

    def test_in_range_rate_and_cap(self):
        self.l.networks = (ip_network("127.0.0.0/8"),)
        self.knock()
        self.assertIsNotNone(self.l.accept())
        self.l.open = L.MAX_OPEN
        self.knock()
        self.assertIsNone(self.l.accept())   # past the cap
        self.l.open = 0
        self.l.rate = Rate(1, 60)
        self.l.rate.allow("127.0.0.1")
        self.knock()
        self.assertIsNone(self.l.accept())   # over its rate


class LogIn(Fixture):
    def relayed(self):
        self.l.networks = (ip_network("127.0.0.0/8"),)
        c = self.knock()
        client = self.l.accept()
        self.l.relay(client)
        theirs = self.vnc.accept()[0]   # wayvnc's end
        self.addCleanup(theirs.close)
        return c

    def test_pending_until_wayvnc_lists_a_new_client(self):
        self.clients = {"1"}   # e.g. lib/warmup.py's look, not gone yet
        self.relayed()
        self.assertIsNotNone(self.l.pending)
        self.assertTrue(self.l.active)
        self.l.check()
        self.assertIsNotNone(self.l.pending)   # the old client alone isn't this connection's login
        self.clients = {"2"}
        self.l.check()
        self.assertIsNone(self.l.pending)
        self.assertEqual(self.l.open, 1)

    def test_no_login_within_auth_wait_closes_it(self):
        c = self.relayed()
        with mock.patch.object(L, "AUTH_WAIT", 0):
            time.sleep(0.01)
            self.l.check()
        self.assertIsNone(self.l.pending)
        c.settimeout(2)
        self.assertEqual(c.recv(1), b"")   # the peer's connection ended
        for _ in range(100):
            if not self.l.active:
                break
            time.sleep(0.02)
        self.assertFalse(self.l.active)   # and it keeps the display no longer

    def test_wayvnc_that_cant_be_asked_lets_nobody_in(self):
        self.l.networks = (ip_network("127.0.0.0/8"),)
        self.l.ids = lambda: None
        c = self.knock()
        self.l.relay(self.l.accept())
        self.assertEqual(self.l.open, 0)
        c.settimeout(2)
        self.assertEqual(c.recv(1), b"")


if __name__ == "__main__":
    unittest.main()
