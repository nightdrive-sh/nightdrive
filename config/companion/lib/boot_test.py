"""The page never stays half loaded (web/boot.js, #3081): a file that fails loads the page once more, and when that
fails too, the page says so with Reload. Runs the demo server with files made to fail, in a headless Chromium.

    python3 config/companion/lib/boot_test.py
"""
import os
import re
import shutil
import subprocess
import sys
import tempfile
import threading
import unittest
from http.server import ThreadingHTTPServer

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import server  # noqa: E402

CHROMIUM = next((shutil.which(b) for b in ("chromium-browser", "chromium", "google-chrome") if shutil.which(b)), None)
BUDGET_MS = 10000     # virtual time the page gets: a retry and the stream's first state fit well in it


class Failing(server.Handler):
    """The demo's handler with some of the page's files answering 502, as tailscale serve did (#3080)."""
    fail = {}           # file name → how many more times it fails (a large number: always)
    served = []         # the files asked for, in order

    def _static(self, path):
        name = path.lstrip("/") or "index.html"
        self.served.append(name)
        if self.fail.get(name, 0) > 0:
            self.fail[name] -= 1
            return self._send(502, b"Bad gateway", "text/plain")
        return super()._static(path)

    def _events(self, device=None):
        # The state once, and the stream closed: a stream held open keeps Chromium's virtual time from running out
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.end_headers()
        self.wfile.write(f"retry: 600000\nevent: state\ndata: {self.state.json}\n\n".encode())


@unittest.skipUnless(CHROMIUM, "needs Chromium for a headless page load")
class BootTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        Failing.state = server.State(True)
        cls.httpd = ThreadingHTTPServer(("127.0.0.1", 0), Failing)
        cls.httpd.daemon_threads = True
        Failing.port = cls.httpd.server_address[1]
        threading.Thread(target=cls.httpd.serve_forever, daemon=True).start()
        threading.Thread(target=Failing.state.loop, daemon=True).start()

    @classmethod
    def tearDownClass(cls):
        cls.httpd.shutdown()
        cls.httpd.server_close()

    def load(self, fail):
        """The page's DOM after loading it with these files failing, and the files that were asked for."""
        Failing.fail, Failing.served = dict(fail), []
        with tempfile.TemporaryDirectory(ignore_cleanup_errors=True) as profile:
            out = subprocess.run([CHROMIUM, "--headless=new", "--disable-gpu", "--no-first-run", f"--user-data-dir={profile}",
                                  f"--virtual-time-budget={BUDGET_MS}", "--dump-dom", f"http://127.0.0.1:{Failing.port}/"],
                                 capture_output=True, text=True, timeout=60)
        return out.stdout, Failing.served

    def html_classes(self, dom):
        m = re.search(r"<html[^>]*class=\"([^\"]*)\"", dom)
        return set(m.group(1).split()) if m else set()

    def test_whole_load(self):
        dom, served = self.load({})
        self.assertEqual(self.html_classes(dom), {"ready"})
        self.assertIn('class="tile', dom)
        self.assertEqual(served.count("index.html"), 1)

    def test_a_module_failing_once_is_tried_again(self):
        dom, served = self.load({"compose.js": 1})
        self.assertEqual(self.html_classes(dom), {"ready"})
        self.assertIn('class="tile', dom)      # the sessions, not Dictate alone
        self.assertEqual(served.count("index.html"), 2)

    def test_a_module_failing_twice_says_so(self):
        dom, served = self.load({"compose.js": 99})
        self.assertIn("load-failed", self.html_classes(dom))
        self.assertNotIn('class="tile', dom)
        self.assertIn('<a href="/">Reload</a>', dom)
        self.assertEqual(served.count("index.html"), 2)     # one try more, not a loop

    def test_a_stylesheet_failing_twice_says_so(self):
        dom, served = self.load({"app.css": 99})
        self.assertIn("load-failed", self.html_classes(dom))
        self.assertRegex(dom, r'<p class="what">[^<]*app\.css')
        self.assertEqual(served.count("index.html"), 2)

    def test_a_stylesheet_failing_once_is_tried_again(self):
        dom, served = self.load({"app.css": 1})
        self.assertEqual(self.html_classes(dom), {"ready"})
        self.assertEqual(served.count("index.html"), 2)


if __name__ == "__main__":
    unittest.main()
