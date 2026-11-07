#!/usr/bin/env python3
"""web_download (#2242): `python3 config/mcp/web_download_test.py`. What netguard.py lets through (public servers only,
on every redirect too) and what download.py keeps (size limits, the type read from the content, clean names, its
undo only in a conversation's own folder). A local server stands in for the web: its 127.0.0.1 counts as public here
only, the way a public server would."""

import contextlib
import io
import json
import os
import struct
import sys
import tempfile
import threading
import unittest
import zlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from unittest import mock

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE / "web"))

import download  # noqa: E402
import netguard  # noqa: E402
import sniff  # noqa: E402


def chunk(kind, data):
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))


PNG = (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", 1, 1, 8, 0, 0, 0, 0))
       + chunk(b"IDAT", zlib.compress(b"\x00\x00")) + chunk(b"IEND", b""))
BIG = 26 * 1024 * 1024


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def send(self, status, body=b"", headers=(), length=True):
        self.send_response(status)
        for k, v in headers:
            self.send_header(k, v)
        if length:
            self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        path = self.path
        if path.startswith("/pics/"):
            self.send(200, PNG, [("Content-Type", "application/octet-stream")])
        elif path == "/page":
            self.send(200, b"<!doctype html><html><body>Not a file</body></html>", [("Content-Type", "image/png")])
        elif path == "/script.png":
            self.send(200, b"#!/bin/sh\necho hi\n")
        elif path == "/declared-big":
            self.send(200, PNG, [("Content-Length", str(BIG))], length=False)
        elif path == "/streamed-big":   # no Content-Length: the limit must hold as it streams
            self.send_response(200)
            self.send_header("Connection", "close")
            self.end_headers()
            block = PNG + b"\x00" * (1024 * 1024 - len(PNG))
            try:
                for _ in range(BIG // len(block) + 1):
                    self.wfile.write(block)
            except OSError:
                pass   # the client gave up, as it should
        elif path == "/to-lan":
            self.send(302, headers=[("Location", "http://192.168.1.1/pic.png")])
        elif path == "/to-localhost":
            self.send(302, headers=[("Location", "http://[::1]/pic.png")])
        elif path == "/to-pic":
            self.send(302, headers=[("Location", "/pics/moved%20here.png")])
        elif path == "/loop":
            self.send(302, headers=[("Location", "/loop")])
        else:
            self.send(404)


class Netguard(unittest.TestCase):
    def test_public(self):
        for ip in ("127.0.0.1", "10.1.2.3", "172.16.0.1", "192.168.1.1", "169.254.169.254", "100.100.1.1", "0.0.0.0",
                   "224.0.0.1", "::1", "fe80::1", "fc00::1", "::ffff:192.168.1.1", "2002:c0a8:0101::1",
                   "64:ff9b::7f00:1", "255.255.255.255"):
            self.assertFalse(netguard.public(ip), ip)
        for ip in ("93.184.215.14", "1.1.1.1", "2606:4700:4700::1111", "64:ff9b::101:101"):
            self.assertTrue(netguard.public(ip), ip)

    def test_parse_refuses(self):
        for url in ("file:///etc/passwd", "ftp://example.com/a", "javascript:alert(1)", "http://user:pw@example.com/",
                    "http://exa mple.com/", "http:\\\\example.com\\", "http://example.com:99999/", "http:///x",
                    "https://example.com/" + "a" * 3000):
            with self.assertRaises(netguard.BlockedError, msg=url):
                netguard.parse(url)

    def test_names_that_resolve_privately(self):
        for host in ("localhost", "127.0.0.1", "[::1]", "10.0.0.1"):
            with self.assertRaises(netguard.BlockedError, msg=host):
                netguard.addresses(host.strip("[]"), 80)

    def test_one_private_address_blocks_all(self):
        infos = [(2, 1, 6, "", ("1.1.1.1", 80)), (2, 1, 6, "", ("192.168.0.2", 80))]
        with mock.patch("socket.getaddrinfo", return_value=infos):
            with self.assertRaises(netguard.BlockedError):
                netguard.addresses("rebind.example", 80)


class Sniff(unittest.TestCase):
    def test_kept_types(self):
        ogg = b"OggS" + b"\x00" * 24
        cases = {PNG: "png", b"\xff\xd8\xff\xe0JFIF": "jpg", b"GIF89a..": "gif", b"RIFF\0\0\0\0WEBPVP8 ": "webp",
                 b"RIFF\0\0\0\0WAVEfmt ": "wav", b"%PDF-1.7": "pdf", b"PK\x03\x04": "zip", b"fLaC\0": "flac",
                 ogg + b"\x01vorbis": "ogg", ogg + b"OpusHead": "ogg", b"ID3\x04\0": "mp3", b"\xff\xfb\x90\x64": "mp3"}
        for head, ext in cases.items():
            self.assertEqual(sniff.kind(head)[1], ext, head)

    def test_refused(self):
        for head in (b"<!doctype html>", b"#!/bin/sh", b"\x7fELF\x02", b"<svg xmlns=", b"OggS" + b"\0" * 24 + b"\x80theora",
                     b"RIFF\0\0\0\0AVI ", b"\xff\xff\xff\xff", b"\xff\xfb\xf0\x00", b""):
            self.assertIsNone(sniff.kind(head), head)


class Download(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        threading.Thread(target=cls.server.serve_forever, daemon=True).start()
        cls.base = f"http://127.0.0.1:{cls.server.server_address[1]}"

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.state = Path(self.tmp.name) / "ask"
        self.folder = self.state / "3f1c-run" / "files"
        real = netguard.public
        self.patches = [mock.patch.object(download, "STATE", self.state),
                        mock.patch.dict(os.environ, {download.ENV: str(self.folder)}),
                        mock.patch.object(netguard, "public", lambda ip: ip == "127.0.0.1" or real(ip))]
        for p in self.patches:
            p.start()

    def tearDown(self):
        for p in self.patches:
            p.stop()
        self.tmp.cleanup()

    def run_main(self, *argv):
        out, err = io.StringIO(), io.StringIO()
        code = 0
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            try:
                download.main(list(argv))
            except SystemExit as e:
                code = e.code
        return code, out.getvalue(), err.getvalue()

    def get(self, path, *more):
        return self.run_main("get", self.base + path, *more)

    def files(self):
        return sorted(p.name for p in self.folder.iterdir()) if self.folder.exists() else []

    def test_downloads_a_picture(self):
        code, out, _ = self.get("/pics/Sunset.over%20the%20lake.PNG")
        self.assertEqual(code, 0)
        self.assertEqual(json.loads(out), {"id": "Sunset-over the lake.png", "type": "image/png", "size": len(PNG)})
        path = self.folder / "Sunset-over the lake.png"
        self.assertEqual(path.read_bytes(), PNG)
        self.assertEqual(path.stat().st_mode & 0o777, 0o600)
        with contextlib.suppress(OSError):   # a file system without user xattrs keeps none
            self.assertEqual(os.getxattr(path, download.ORIGIN).decode(), self.base + "/pics/Sunset.over%20the%20lake.PNG")
        code, out, _ = self.get("/pics/x.png", "--name", "../../.Sunset-over the lake")
        self.assertEqual(json.loads(out)["id"], "Sunset-over the lake-2.png")

    def test_redirect_is_followed_and_named_by_where_it_led(self):
        code, out, _ = self.get("/to-pic")
        self.assertEqual((code, json.loads(out)["id"]), (0, "moved here.png"))

    def test_redirect_to_lan_or_localhost_is_blocked(self):
        for path in ("/to-lan", "/to-localhost"):
            code, _, err = self.get(path)
            self.assertEqual(code, 1, path)
            self.assertIn("your own network", err)
        self.assertEqual(self.files(), [])

    def test_redirect_loop(self):
        code, _, err = self.get("/loop")
        self.assertEqual(code, 1)
        self.assertIn("redirects", err)

    def test_wrong_type_is_not_kept(self):
        for path in ("/page", "/script.png"):
            code, _, err = self.get(path)
            self.assertEqual(code, 1, path)
            self.assertIn("isn't one of the types", err)
        self.assertEqual(self.files(), [])

    def test_size_limit(self):
        for path in ("/declared-big", "/streamed-big"):
            code, _, err = self.get(path)
            self.assertEqual(code, 1, path)
            self.assertIn("25 MB", err)
        self.assertEqual(self.files(), [])

    def test_conversation_limit(self):
        self.folder.mkdir(parents=True)
        (self.folder / "old.zip").write_bytes(b"\x00" * (download.RUN_MAX - 10))
        code, _, err = self.get("/pics/a.png")
        self.assertEqual(code, 1)
        self.assertIn("MB left", err)

    def test_only_in_ask_claude(self):
        with mock.patch.dict(os.environ, {download.ENV: ""}):
            code, _, err = self.get("/pics/a.png")
        self.assertEqual(code, 1)
        self.assertIn("only in Ask Claude", err)
        with mock.patch.dict(os.environ, {download.ENV: str(Path(self.tmp.name) / "elsewhere")}):
            self.assertEqual(self.get("/pics/a.png")[0], 1)

    def test_undo_removes_only_its_own(self):
        code, out, _ = self.get("/pics/a.png")
        file_id = json.loads(out)["id"]
        code, out, _ = self.run_main("folder")
        folder = json.loads(out)["folder"]
        outside = Path(self.tmp.name) / "keep.png"
        outside.write_bytes(PNG)
        for bad in (("remove", "--folder", str(Path(self.tmp.name)), "keep.png"),
                    ("remove", "--folder", folder, "../../../keep.png"),
                    ("remove", "--folder", folder, ".part-x")):
            self.assertEqual(self.run_main(*bad)[0], 1, bad)
        self.assertTrue(outside.exists())
        self.assertEqual(self.run_main("remove", "--folder", folder, file_id)[0], 0)
        self.assertEqual(self.files(), [])

    def test_tool_definition(self):
        sys.path.insert(0, str(HERE))
        import registry
        spec = json.loads((HERE / "tools/web.json").read_text())["tools"][0]
        self.assertIsNone(registry.problem(spec, None))
        tool = registry.Tool(spec, HERE, "web.json")
        self.assertEqual((tool.area, tool.right, tool.cls), ("web", "modify", "change"))


if __name__ == "__main__":
    unittest.main()
