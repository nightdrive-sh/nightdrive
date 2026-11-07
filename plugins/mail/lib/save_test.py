#!/usr/bin/env python3
"""Claude's saves from Mail (#2291): `python3 plugins/mail/lib/save_test.py`. A stranger's attachment names are made
safe to save under, and a message printed as a PDF loads nothing from the network: a local server stands in for the
sender's and counts every request (the PDF test needs Chromium, and is skipped without it)."""

import email
import email.policy
import http.server
import shutil
import sys
import threading
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import pdf  # noqa: E402
from save import NAME_BYTES, clean_name  # noqa: E402


class Names(unittest.TestCase):
    def test_kept(self):
        for name in ("invoice.pdf", "Lasku 2026-11.pdf", "kuva (1).jpg", "naïve résumé.docx", "a.tar.gz"):
            self.assertEqual(clean_name(name), name)

    def test_no_path(self):
        self.assertEqual(clean_name("../../.bashrc"), "bashrc")
        self.assertEqual(clean_name("..\\..\\Windows\\evil.exe"), "evil.exe")
        self.assertEqual(clean_name("/etc/passwd"), "passwd")

    def test_not_hidden_nor_an_option(self):
        self.assertEqual(clean_name(".profile"), "profile")
        self.assertEqual(clean_name("-rf.txt"), "rf.txt")
        self.assertEqual(clean_name("~ report.pdf"), "report.pdf")
        self.assertEqual(clean_name("notes.txt. . "), "notes.txt")

    def test_invisible_characters_out(self):
        self.assertEqual(clean_name("invoice‮fdp.exe"), "invoicefdp.exe")   # right-to-left override
        self.assertEqual(clean_name("pay​ment.pdf"), "payment.pdf")         # zero-width space
        self.assertEqual(clean_name("a\nb\tc.txt"), "a b c.txt")
        self.assertEqual(clean_name("x\x00y.txt"), "xy.txt")

    def test_empty_falls_back(self):
        for name in ("", None, "...", "/", "‮", " - "):
            self.assertEqual(clean_name(name), "attachment")
        self.assertEqual(clean_name("", "message"), "message")

    def test_a_subject_keeps_its_words(self):
        self.assertEqual(clean_name("Invoice / November ../../", "message", title=True), "Invoice - November")
        self.assertEqual(clean_name("../../.ssh/x", "message", title=True), "ssh - x")

    def test_long_keeps_its_extension(self):
        name = clean_name("ä" * 300 + ".pdf")
        self.assertTrue(name.endswith(".pdf"))
        self.assertLessEqual(len(name.encode()), NAME_BYTES)


class Counter(http.server.BaseHTTPRequestHandler):
    hits = []

    def do_GET(self):
        Counter.hits.append(self.path)
        self.send_response(200)
        self.send_header("Content-Type", "image/png" if self.path.endswith(".png") else "text/css")
        self.end_headers()

    def log_message(self, *args):
        pass


def mail(html=None, text="Hello\nworld"):
    msg = email.message.EmailMessage(policy=email.policy.default)
    msg["From"], msg["To"], msg["Subject"] = "Stranger <s@example.com>", "me@example.com", "Your order <3"
    msg["Date"] = "Sat, 07 Nov 2026 10:00:00 +0200"
    msg.set_content(text)
    if html:
        msg.add_alternative(html, subtype="html")
    msg.add_attachment(b"%PDF-1.4", maintype="application", subtype="pdf", filename="receipt.pdf")
    return msg


class Document(unittest.TestCase):
    def test_headers_escaped(self):
        page = pdf.document(mail())
        self.assertIn("Your order &lt;3", page)
        self.assertIn("receipt.pdf", page)
        self.assertIn("Content-Security-Policy", page)
        self.assertIn("Hello\nworld", page)

    def test_no_bidi_tricks_in_headers(self):
        msg = mail()
        msg.replace_header("Subject", "Bill \u202egnp.exe")
        page = pdf.document(msg)
        self.assertNotIn("\u202e", page)
        self.assertIn("Bill gnp.exe", page)

    def test_sender_cannot_reach_out(self):
        page = pdf.document(mail('<html><head><meta http-equiv="refresh" content="0;url=http://x/">'
                                 '<link rel="stylesheet" href="http://x/s.css"><script>fetch("http://x/")</script>'
                                 '</head><body><iframe src="http://x/f"></iframe>Hi</body></html>'))
        for gone in ("refresh", "<link", "<script", "<iframe"):
            self.assertNotIn(gone, page)
        self.assertLess(page.index("Content-Security-Policy"), page.index("Hi"))


@unittest.skipUnless(any(shutil.which(c) for c in pdf.CHROMIUM), "needs Chromium")
class Render(unittest.TestCase):
    """Each of the two layers holds on its own: the page's policy, and Chromium's switches. The local server stands in
    for the sender's: a request to it is what tells a sender the mail was opened."""

    def setUp(self):
        self.server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Counter)
        threading.Thread(target=self.server.serve_forever, daemon=True).start()
        at = f"127.0.0.1:{self.server.server_address[1]}"
        self.html = (f'<html><head><style>@import url(http://{at}/import.css); '
                     f'@font-face {{ font-family: X; src: url(http://{at}/font.woff) }}</style></head>'
                     f'<body style="background: url(//{at}/bg.png)"><p>Dear customer</p>'
                     f'<img src="http://{at}/pixel.png" width=1 height=1>'
                     f'<img srcset="http://{at}/set.png 2x"><video poster="http://{at}/poster.png"></video>'
                     f'<a href="http://{at}/link">Track your order</a>'
                     f'<img src="x" onerror="new Image().src=\'http://{at}/onerror.png\'"></body></html>')
        Counter.hits.clear()
        self.offline = list(pdf.OFFLINE)

    def tearDown(self):
        pdf.OFFLINE[:] = self.offline
        self.server.shutdown()
        self.server.server_close()

    def without_network_rules(self):
        pdf.OFFLINE[:] = [f for f in self.offline if not f.startswith(("--host-resolver-rules", "--proxy-server"))]

    def test_nothing_remote_is_loaded(self):
        data = pdf.render(pdf.document(mail(self.html)))
        self.assertTrue(data.startswith(b"%PDF"))
        self.assertEqual(Counter.hits, [])

    def test_the_policy_alone_holds(self):
        self.without_network_rules()
        pdf.render(pdf.document(mail(self.html)))
        self.assertEqual(Counter.hits, [])

    def test_the_switches_alone_hold(self):
        pdf.render(self.html)   # the sender's page as it came: no policy, nothing taken out
        self.assertEqual(Counter.hits, [])

    def test_a_leak_would_show(self):
        """Without either, the server sees the requests: the tests above can fail."""
        self.without_network_rules()
        pdf.render(self.html)
        self.assertIn("/pixel.png", Counter.hits)


if __name__ == "__main__":
    unittest.main()
