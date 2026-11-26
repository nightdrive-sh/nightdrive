#!/usr/bin/env python3
"""Where Home Assistant's token may go (#1748): `python3 plugins/home-assistant/network_test.py`.
- https anywhere; http on the tailnet only when its address is a Tailscale one routed through tailscale0, and then sent
  to that address; any other http address only on a home network, known by its connection and its router's MAC both.
- Looking for an address that answers sends no token; the token goes only to the address chosen.
- An address chosen on another network (or remembered the old way, without one) is chosen again.
- A redirect isn't followed, so the token doesn't go along to its address.
The network, DNS and Home Assistant are stand-ins: nothing is sent anywhere but to 127.0.0.1."""

import http.server
import io
import os
import socket
import sys
import tempfile
import threading
import unittest
from pathlib import Path
from unittest import mock

LIB = Path(__file__).resolve().parent / "lib"
sys.path.insert(0, str(LIB))
import client  # noqa: E402
import network  # noqa: E402

HOME_NET = network.Network("uuid-home", "60:22:32:7A:D7:D3", "Kotiverkko")
TWIN = network.Network("uuid-home", "02:00:00:00:00:01", "Kotiverkko")   # same profile, another router
CAFE = network.Network("uuid-cafe", "02:00:00:00:00:02", "Café")
TAILSCALE_IP = "100.97.71.82"
LOCAL = "http://homeassistant.local:8123"
TAIL = "http://ha:8123"
NABU = "https://x.ui.nabu.casa"


def dns(names):
    """socket.getaddrinfo answering names {host: ip}"""
    def getaddrinfo(host, port, *a, **k):
        if host not in names:
            raise socket.gaierror("no such name")
        fam = socket.AF_INET6 if ":" in names[host] else socket.AF_INET
        return [(fam, socket.SOCK_STREAM, 6, "", (names[host], port))]
    return getaddrinfo


def routes(dev):
    """ip -j route get: every address through dev"""
    return lambda *args: [{"dst": args[-1], "dev": dev}] if args[:2] == ("route", "get") else []


class Base(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.dir = tmp.name
        for target, name, value in [(network, "ANSWERS", "networks"), (client, "CACHE", "url"),
                                    (client, "CONFIG", "config")]:
            p = mock.patch.object(target, name, os.path.join(self.dir, value))
            p.start()
            self.addCleanup(p.stop)

    def on(self, names, dev="tailscale0"):
        for p in (mock.patch("socket.getaddrinfo", dns(names)), mock.patch.object(network, "ip_json", routes(dev))):
            p.start()
            self.addCleanup(p.stop)


class Route(Base):
    def test_https_anywhere(self):
        self.on({})
        self.assertEqual(network.route(NABU, CAFE), (NABU, None))
        self.assertEqual(network.route(NABU, None), (NABU, None))

    def test_tailnet_is_pinned_to_the_address_checked(self):
        self.on({"ha": TAILSCALE_IP})
        self.assertEqual(network.route(TAIL, CAFE), (f"http://{TAILSCALE_IP}:8123", "ha:8123"))
        self.on({"ha": "fd7a:115c:a1e0::51"})
        self.assertEqual(network.route(TAIL + "/x", None), ("http://[fd7a:115c:a1e0::51]:8123/x", "ha:8123"))

    def test_a_tailscale_address_off_tailscale0_is_plain(self):
        # Tailscale down: a café's DNS may say 100.x, and its router would get the packets
        self.on({"ha": TAILSCALE_IP}, dev="wlan0")
        self.assertIsNone(network.route(TAIL, CAFE))
        self.assertTrue(network.plain(TAIL))

    def test_a_name_the_cafe_resolves_elsewhere_is_plain(self):
        self.on({"ha": "192.168.1.10", "homeassistant.local": "10.0.0.5"})
        self.assertIsNone(network.route(TAIL, CAFE))
        self.assertIsNone(network.route(LOCAL, CAFE))

    def test_mdns_names_arent_looked_up(self):
        # Off home, nss-mdns takes 5 s to give up on homeassistant.local: never the tailnet anyway
        with mock.patch("socket.getaddrinfo", side_effect=AssertionError("looked up")):
            self.assertIsNone(network.tailnet_ip("homeassistant.local"))
            self.assertIsNone(network.tailnet_ip("HA.LOCAL."))

    def test_plain_http_only_at_home(self):
        self.on({"homeassistant.local": "192.168.1.10"})
        network.remember(HOME_NET, "home")
        network.remember(CAFE, "not")
        self.assertEqual(network.route(LOCAL, HOME_NET), (LOCAL, None))
        self.assertIsNone(network.route(LOCAL, CAFE))
        self.assertIsNone(network.route(LOCAL, TWIN), "the same Wi-Fi profile behind another router")
        self.assertIsNone(network.route(LOCAL, None))
        self.assertIsNone(network.route("ftp://ha", HOME_NET))


class Answers(Base):
    def test_remember_and_forget(self):
        network.remember(HOME_NET, "home")
        self.assertEqual(os.stat(network.ANSWERS).st_mode & 0o777, 0o600)
        self.assertEqual(network.answer(network.Network("uuid-home", "60:22:32:7a:d7:d3")), "home", "MAC in any case")
        self.assertEqual(network.answer(TWIN), "")
        network.remember(HOME_NET, "not")
        self.assertEqual(network.answer(HOME_NET), "not")
        network.remember(HOME_NET, None)
        self.assertEqual(network.answer(HOME_NET), "")
        self.assertEqual(network.answer(None), "")


class Pick(Base):
    def client(self, net, urls=(LOCAL, TAIL, NABU), answering=None):
        """A Client on net; sent: every request (url, token, host); answering: the urls that answer"""
        with open(client.CONFIG, "w") as f:
            f.write(f'HA_URLS="{" ".join(urls)}"\nHA_TOKEN=secret\n')
        self.sent = []

        def request(base, tok, method, path, body=None, timeout=None, host=None):
            self.sent.append((base, tok, host))
            if answering is not None and base not in answering:
                raise OSError("no answer")
            return {}
        for p in (mock.patch.object(client, "request", request), mock.patch.object(network, "current", lambda: net),
                  mock.patch.object(client.Client, "ask_home", lambda *a: None)):
            p.start()
            self.addCleanup(p.stop)
        return client.Client()

    def test_away_the_plain_address_gets_nothing(self):
        self.on({"ha": TAILSCALE_IP, "homeassistant.local": "10.0.0.5"})
        c = self.client(CAFE)
        c.call("GET", "/api/states")
        self.assertEqual(self.sent, [(f"http://{TAILSCALE_IP}:8123", None, "ha:8123"),
                                     (f"http://{TAILSCALE_IP}:8123", "secret", "ha:8123")])

    def test_at_home_the_local_address(self):
        self.on({"homeassistant.local": "192.168.1.10"}, dev="wlan0")
        network.remember(HOME_NET, "home")
        self.client(HOME_NET).call("GET", "/api/states")
        self.assertEqual(self.sent, [(LOCAL, None, None), (LOCAL, "secret", None)])

    def test_probes_never_carry_the_token(self):
        self.on({"ha": TAILSCALE_IP})
        self.client(CAFE, answering={NABU}).call("GET", "/api/states")
        self.assertTrue(all(tok is None for base, tok, _ in self.sent[:-1]))
        self.assertEqual(self.sent[-1], (NABU, "secret", None))

    def test_remembered_from_home_isnt_used_away(self):
        # The old cache: an address alone, the first in HA_URLS, was used anywhere without asking
        self.on({"homeassistant.local": "10.0.0.5"}, dev="wlan0")
        with open(client.CACHE, "w") as f:
            f.write(LOCAL)
        self.client(CAFE).call("GET", "/api/states")
        self.assertNotIn(LOCAL, [b for b, _, _ in self.sent])
        with open(client.CACHE, "w") as f:
            f.write(f"{LOCAL}\t{HOME_NET.key}")
        self.client(CAFE).call("GET", "/api/states")
        self.assertNotIn(LOCAL, [b for b, _, _ in self.sent])

    def test_remembered_on_this_network_is_used(self):
        self.on({"homeassistant.local": "192.168.1.10"}, dev="wlan0")
        network.remember(HOME_NET, "home")
        with open(client.CACHE, "w") as f:
            f.write(f"{LOCAL}\t{HOME_NET.key}")
        self.client(HOME_NET).call("GET", "/api/states")
        self.assertEqual(self.sent, [(LOCAL, "secret", None)])

    def test_only_plain_away_says_why(self):
        self.on({}, dev="wlan0")
        c = self.client(CAFE, urls=(LOCAL,))
        with self.assertRaises(SystemExit), mock.patch("sys.stderr", io.StringIO()) as err:
            c.call("GET", "/api/states")
        self.assertIn("only on your home network", err.getvalue())
        self.assertEqual(self.sent, [])


class Redirect(unittest.TestCase):
    def test_not_followed(self):
        got = []

        class Handler(http.server.BaseHTTPRequestHandler):
            def do_GET(self):
                got.append((self.path, self.headers.get("Authorization")))
                self.send_response(302 if self.path == "/api/" else 200)
                self.send_header("Location", "/elsewhere")
                self.end_headers()

            def log_message(self, *a):
                pass
        server = http.server.HTTPServer(("127.0.0.1", 0), Handler)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        self.addCleanup(server.server_close)
        self.addCleanup(server.shutdown)
        with self.assertRaises(client.urllib.error.HTTPError) as e:
            client.request(f"http://127.0.0.1:{server.server_port}", "secret", "GET", "/api/", timeout=5)
        e.exception.close()
        self.assertEqual(e.exception.code, 302)
        self.assertEqual(got, [("/api/", "Bearer secret")])


if __name__ == "__main__":
    unittest.main()
