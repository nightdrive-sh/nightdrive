#!/usr/bin/env python3
"""Mail watches (#3735): `python3 plugins/mail/lib/watch_test.py`. A throwaway notmuch database, and a stand-in for
`nightdrive schedule` that records its calls: what wakes a watch and what doesn't, its time-out, cancel and restore."""

import email.utils
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path
from unittest import mock

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import watch  # noqa: E402
import watch_check  # noqa: E402

# Answers as `nightdrive schedule` does: a dry run's row, an added row's id, nothing for a cancel
FAKE = r"""#!/usr/bin/env python3
import json, os, sys, time
args = sys.argv[2:]
with open(os.environ["FAKE_LOG"], "a") as f:
    f.write(json.dumps({"args": args, "mcp": os.environ.get("NIGHTDRIVE_MCP")}) + "\n")
if args[0] == "cancel":
    sys.exit(0)
to = args[args.index("--to") + 1] if "--to" in args else None
if to == "nobody":
    print("No session named nobody (nightdrive sessions)", file=sys.stderr)
    sys.exit(2)
at = int(args[0][1:]) if args[0].startswith("@") else int(time.time()) + 7200
print(json.dumps({"id": None if "--dry-run" in args else "row%d" % len(open(os.environ["FAKE_LOG"]).readlines()),
                  "to": to, "at_unix": at}))
"""


def mail(mid, subject, sender="Maija <maija@b.c>", reply_to=None, date=None):
    extra = f"In-Reply-To: <{reply_to}>\n" if reply_to else ""
    date = email.utils.formatdate(date or time.time(), localtime=True)
    return f"From: {sender}\nTo: Me <me@x.y>\nSubject: {subject}\nMessage-ID: <{mid}>\n{extra}Date: {date}\n\nHi\n"


@unittest.skipUnless(shutil.which("notmuch"), "needs notmuch")
class Watches(unittest.TestCase):
    def setUp(self):
        self.dir = Path(tempfile.mkdtemp(prefix="nightmail-watch-"))
        self.addCleanup(shutil.rmtree, self.dir)
        self.root = self.dir / "mail"
        for sub in ("cur", "new", "tmp"):
            (self.root / "acc" / "INBOX" / sub).mkdir(parents=True)
        (self.dir / "notmuch").write_text(f"[database]\npath={self.root}\n[new]\ntags=inbox;unread;\n"
                                          "[search]\nexclude_tags=deleted;spam;\n")
        fake = self.dir / "nightdrive"
        fake.write_text(FAKE)
        fake.chmod(0o755)
        self.log = self.dir / "calls"
        self.log.touch()
        env = {"NOTMUCH_CONFIG": str(self.dir / "notmuch"), "FAKE_LOG": str(self.log),
               "CLAUDE_CODE_SESSION_ID": "11111111-2222-3333-4444-555555555555", "NIGHTDRIVE_MCP": "1",
               "NIGHTDRIVE_MCP_OPTIONS": json.dumps({"blocked": ["bank.fi"]})}
        for p in (mock.patch.dict(os.environ, env), mock.patch.object(watch, "STATE", str(self.dir / "watch.json")),
                  mock.patch.object(watch, "NIGHTDRIVE", fake)):
            p.start()
            self.addCleanup(p.stop)
        os.environ.pop("NOTMUCH_PROFILE", None)
        self.n = 0
        self.deliver(mail("m1@b.c", "Offer"))
        self.deliver(mail("o1@b.c", "Other"))

    def deliver(self, text, folder="INBOX"):
        self.n += 1
        (self.root / "acc" / folder / "new" / f"{self.n}.msg").write_text(text)
        subprocess.run(["notmuch", "new", "--quiet"], check=True, env=os.environ)

    def calls(self):
        return [json.loads(line) for line in self.log.read_text().splitlines()]

    def wakes(self):
        return [c for c in self.calls() if c["args"][0].startswith("@") and "--dry-run" not in c["args"]]

    def thread(self, mid):
        return watch.notmuch("search", "--output=threads", f"id:{mid}").strip()

    def test_a_reply_in_the_thread_wakes_this_session_once(self):
        w = watch.add(self.thread("m1@b.c"), "Answer the offer")
        self.assertEqual(w["to"], os.environ["CLAUDE_CODE_SESSION_ID"])
        watch_check.check()
        self.assertEqual(self.wakes(), [], "what was there before woke it")
        self.deliver(mail("o2@b.c", "Unrelated"))
        watch_check.check()
        self.assertEqual(self.wakes(), [])
        self.deliver(mail("m2@b.c", "Re: Offer", reply_to="m1@b.c"))
        watch_check.check()
        wake = self.wakes()
        self.assertEqual(len(wake), 1)
        self.assertEqual(wake[0]["mcp"], "1", "a wake isn't marked as Claude's in schedule's list")
        args = wake[0]["args"]
        self.assertEqual(args[args.index("--to") + 1], os.environ["CLAUDE_CODE_SESSION_ID"])
        self.assertIn("id:m2@b.c", args[-1])
        self.assertTrue(args[-1].endswith("Answer the offer"))
        self.assertEqual(watch.main(["list", "--json"]), 0)
        self.deliver(mail("m3@b.c", "Re: Offer", reply_to="m1@b.c"))
        watch_check.check()
        self.assertEqual(len(self.wakes()), 1, "a watch woke twice")

    def test_your_own_mail_a_draft_and_blocked_mail_dont_wake(self):
        watch.add("subject:Offer", "Go on", to="Nightdrive Project Manager")
        self.deliver(mail("s1@x.y", "Re: Offer", sender="Me <me@x.y>"))
        watch.notmuch("tag", "+sent", "-inbox", "--", "id:s1@x.y")
        self.deliver(mail("d1@x.y", "Offer draft"))
        watch.notmuch("tag", "+draft", "--", "id:d1@x.y")
        self.deliver(mail("b1@bank.fi", "Offer", sender="Bank <info@bank.fi>"))
        watch_check.check()
        self.assertEqual(self.wakes(), [])
        # Retagging old mail changes its lastmod: still not new
        watch.notmuch("tag", "+flagged", "--", "id:m1@b.c")
        watch_check.check()
        self.assertEqual(self.wakes(), [])
        self.deliver(mail("x1@c.d", "Offer accepted", sender="Liisa <liisa@c.d>"))
        watch_check.check()
        args = self.wakes()[0]["args"]
        self.assertEqual(args[args.index("--to") + 1], "Nightdrive Project Manager")
        self.assertIn("Liisa", args[-1])

    def test_time_out_row_and_its_end(self):
        w = watch.add("from:liisa@c.d", "Wake anyway", timeout="2h")
        self.assertTrue(w["timeout_row"])
        row = [c for c in self.calls() if c["args"][-1].startswith("Mail watch")][0]
        self.assertIn("time-out", row["args"][-1])
        self.assertEqual(row["mcp"], "1")
        self.deliver(mail("x1@c.d", "Hi", sender="Liisa <liisa@c.d>"))
        watch_check.check()
        self.assertIn(["cancel", w["timeout_row"]], [c["args"] for c in self.calls()], "the time-out still waits")
        # Past its time-out a watch is over: its row woke the session
        w = watch.add("from:pekka@c.d", "Later", timeout="2h")
        with watch.store() as data:
            data["watches"][-1]["deadline"] = int(time.time()) - 1
        self.deliver(mail("p1@c.d", "Hi", sender="Pekka <pekka@c.d>"))
        before = len(self.wakes())
        watch_check.check()
        self.assertEqual(len(self.wakes()), before)

    def test_cancel_and_restore(self):
        w = watch.add("from:liisa@c.d", "Go on", timeout="90m")
        watch.cancel(w["id"])
        self.deliver(mail("x1@c.d", "Hi", sender="Liisa <liisa@c.d>"))
        watch_check.check()
        self.assertFalse(any("id:x1@c.d" in c["args"][-1] for c in self.wakes()), "a cancelled watch woke")
        self.assertIn(["cancel", w["timeout_row"]], [c["args"] for c in self.calls()])
        back = watch.restore(w["id"])
        self.assertNotEqual(back["timeout_row"], w["timeout_row"])
        watch_check.check()   # mail that came while it was cancelled wakes it now
        self.assertTrue(any("id:x1@c.d" in c["args"][-1] for c in self.wakes()))

    def test_refusals(self):
        with self.assertRaises(ValueError):
            watch.add("from:a", "")
        with self.assertRaises(ValueError):
            watch.add("from:a", "x", to="nobody")
        with self.assertRaises(ValueError):
            watch.cancel("deadbeef")
        self.assertFalse(os.path.exists(watch.STATE) and watch.main(["list", "--json"]))

    def test_check_without_watches_reads_nothing(self):
        with mock.patch.object(watch, "notmuch", side_effect=AssertionError("ran notmuch")):
            self.assertEqual(watch_check.check(), 0)


if __name__ == "__main__":
    unittest.main()
