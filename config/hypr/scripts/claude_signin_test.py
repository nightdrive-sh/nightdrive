#!/usr/bin/env python3
"""Claude Code's sign-in warning as a notification (#3664): `python3 config/hypr/scripts/claude_signin_test.py`.
Claude Code's own wordings (made up dates, as claude -p prints them on stderr), the notification's text, and
`claude-signin warn` in a throwaway home with notify-send and claude-accounts stubbed: once a day per account."""

import json
import os
import subprocess
import sys
import tempfile
import time
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.dont_write_bytecode = True
import claude_signin as cs  # noqa: E402

CMD = os.path.join(HERE, "claude-signin")
ENDS = ("Warning: this sign-in ends between Dec 2 and Dec 5 (in 5 days at the earliest). Renewing it does not move "
        "those dates. Run claude auth login before then, or use claude setup-token for unattended jobs.")
SOON = ("Warning: this sign-in can end at any time from now until Dec 5. Renewing it does not move that date. Run "
        "claude auth login now, or use claude setup-token for unattended jobs.")
ENDED = ("Warning: this sign-in may have ended between Dec 2 and Dec 5. If requests are refused, run claude auth login, "
         "or use claude setup-token for unattended jobs.")


class Rules(unittest.TestCase):
    def test_finds_each_wording_among_other_lines(self):
        for line in (ENDS, SOON, ENDED):
            self.assertEqual(cs.find("some notice\n" + line + "\nmore\n"), line)
        self.assertIsNone(cs.find("Error: rate limited\n"))
        self.assertIsNone(cs.find(""))

    def test_message_says_when_and_what_to_do(self):
        title, body = cs.message(ENDS)
        self.assertEqual(title, "Claude Code's sign-in ends soon")
        self.assertIn("between Dec 2 and Dec 5", body)
        self.assertIn("claude auth login in a terminal", body)
        self.assertNotIn("setup-token", body)
        self.assertNotIn("Renewing it does not move those dates. Run", body)

    def test_ended_has_its_own_title(self):
        title, body = cs.message(ENDED)
        self.assertEqual(title, "Claude Code's sign-in may have ended")
        self.assertNotIn("If requests are refused", body)

    def test_account_named_only_when_there_are_several(self):
        self.assertNotIn("work account", "".join(cs.message(SOON, "work", False)))
        self.assertNotIn("(work)", "".join(cs.message(SOON, "work", False)))
        title, body = cs.message(SOON, "work", True)
        self.assertIn("(work)", title)
        self.assertIn("again on the work account", body)


class Command(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.home = self.tmp.name
        self.bin = os.path.join(self.home, "bin")
        self.sent = os.path.join(self.home, "sent")
        os.makedirs(self.bin)
        self.stub("notify-send", f'#!/bin/bash\nprintf "%s\\n" "$@" >>"{self.sent}"; echo ---- >>"{self.sent}"\n')
        accounts = os.path.join(self.home, ".config/topbar/scripts/claude-accounts")
        os.makedirs(os.path.dirname(accounts))
        rows = [{"name": "default", "dir": f"{self.home}/.claude"}, {"name": "work", "dir": f"{self.home}/.claude-work"}]
        self.stub(accounts, f"#!/bin/bash\necho '{json.dumps(rows)}'\n")
        self.env = {"HOME": self.home, "PATH": self.bin + ":/usr/bin:/bin"}

    def tearDown(self):
        self.tmp.cleanup()

    def stub(self, name, text):
        path = name if os.path.isabs(name) else os.path.join(self.bin, name)
        with open(path, "w") as f:
            f.write(text)
        os.chmod(path, 0o755)

    def warn(self, stderr, *args, env=None):
        run = subprocess.run([CMD, "warn", "--json", *args], input=stderr, capture_output=True, text=True,
                             env={**self.env, **(env or {})}, timeout=20)
        self.assertEqual(run.returncode, 0, run.stderr)
        return json.loads(run.stdout)

    def notifications(self):
        # The notification is sent in the background: give it a moment
        for _ in range(50):
            if os.path.exists(self.sent):
                break
            time.sleep(0.05)
        time.sleep(0.2)
        try:
            with open(self.sent) as f:
                return f.read().split("----\n")[:-1]
        except OSError:
            return []

    def test_once_a_day_per_account(self):
        first = self.warn("x\n" + ENDS + "\n")
        self.assertTrue(first["found"] and first["shown"])
        self.assertEqual(first["account"], "default")
        again = self.warn(ENDS + "\n")
        self.assertFalse(again["shown"])
        other = self.warn(ENDS + "\n", env={"CLAUDE_CONFIG_DIR": f"{self.home}/.claude-work"})
        self.assertTrue(other["shown"])
        self.assertEqual(other["account"], "work")
        sent = self.notifications()
        self.assertEqual(len(sent), 2, sent)
        self.assertIn("login=Sign in", sent[0])
        self.assertIn("on the default account", sent[0])
        self.assertIn("(work)", sent[1])

    def test_nothing_without_a_warning(self):
        out = self.warn("Error: something else\n")
        self.assertFalse(out["found"] or out["shown"])
        self.assertEqual(self.notifications(), [])
        self.assertFalse(os.path.exists(os.path.join(self.home, ".local/state/nightdrive/claude-signin.json")))

    def test_dry_run_neither_notifies_nor_marks(self):
        self.assertTrue(self.warn(SOON, "--dry-run")["shown"])
        self.assertEqual(self.notifications(), [])
        self.assertTrue(self.warn(SOON, "--dry-run")["shown"])

    def test_a_new_day_tells_again(self):
        self.warn(ENDS)
        state = os.path.join(self.home, ".local/state/nightdrive/claude-signin.json")
        with open(state) as f:
            days = json.load(f)
        with open(state, "w") as f:
            json.dump({d: "2000-01-01" for d in days}, f)
        self.assertTrue(self.warn(ENDS)["shown"])

    def test_reads_a_file(self):
        path = os.path.join(self.home, "stderr")
        with open(path, "w") as f:
            f.write(ENDED + "\n")
        run = subprocess.run([CMD, "warn", path, "--json", "--dry-run"], capture_output=True, text=True,
                             env=self.env, stdin=subprocess.DEVNULL, timeout=20)
        out = json.loads(run.stdout)
        self.assertTrue(out["found"] and out["ended"])


if __name__ == "__main__":
    unittest.main()
