#!/usr/bin/env python3
"""claude-accounts (#3035): which Claude Code config dirs are accounts, their names and order, and claude-usage's answer
per account without a sign-in: `python3 config/topbar/scripts/claude_accounts_test.py`. Everything runs in a throwaway
home; nothing reaches Anthropic (no account here has a token)."""

import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
ACCOUNTS = str(HERE / "claude-accounts")
USAGE = str(HERE / "claude-usage")


@unittest.skipUnless(shutil.which("jq"), "needs jq")
class Accounts(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.home = Path(self.tmp.name)
        self.env = dict(os.environ, HOME=str(self.home), XDG_RUNTIME_DIR=str(self.home / "run"))

    def tearDown(self):
        self.tmp.cleanup()

    def signed_in(self, d, plan="max"):
        d = self.home / d
        d.mkdir(parents=True, exist_ok=True)
        (d / ".credentials.json").write_text(json.dumps({"claudeAiOauth": {"subscriptionType": plan}}))
        return d

    def listing(self, *args):
        r = subprocess.run([ACCOUNTS, *args], env=self.env, capture_output=True, text=True)
        return r.returncode, r.stdout.strip()

    def accounts(self):
        return json.loads(self.listing("--json")[1])

    def test_default_alone(self):
        # No ~/.claude at all: still the one account, as before (claude-usage then says to sign in)
        self.assertEqual([(a["name"], a["default"], a["signedIn"]) for a in self.accounts()], [("default", True, False)])

    def test_found_with_a_sign_in_only(self):
        self.signed_in(".claude", "team")
        self.signed_in(".claude-work")
        (self.home / ".claude-backup").mkdir()          # no sign-in in it: not an account
        got = self.accounts()
        self.assertEqual([(a["name"], a["plan"]) for a in got], [("default", "team"), ("work", "max")])
        self.assertEqual(got[1]["dir"], str(self.home / ".claude-work"))

    def test_file_names_and_adds(self):
        self.signed_in(".claude-work")
        cfg = self.home / ".config/nightdrive"
        cfg.mkdir(parents=True)
        (cfg / "claude-accounts").write_text("# mine\n~/.claude  me\n~/elsewhere/conf/ side  # a comment\n~/.claude-work/ job\n")
        self.assertEqual([a["name"] for a in self.accounts()], ["me", "side", "job"])
        self.assertEqual(self.listing("dir", "side"), (0, str(self.home / "elsewhere/conf")))
        self.assertEqual(self.listing("name", str(self.home / ".claude-work") + "/"), (0, "job"))
        self.assertEqual(self.listing("dir", "nope")[0], 1)
        self.assertEqual(self.listing("name", "/nowhere")[0], 1)

    def test_names_stay_apart(self):
        cfg = self.home / ".config/nightdrive"
        cfg.mkdir(parents=True)
        (cfg / "claude-accounts").write_text("~/a work\n~/b work\n~/c my/odd name\n")
        self.assertEqual([a["name"] for a in self.accounts()], ["default", "work", "work-2", "my-odd-name"])

    def test_usage_per_account(self):
        self.signed_in(".claude-work")
        (self.home / ".claude-work/.credentials.json").write_text("{}")   # signed out since: no token
        r = subprocess.run([USAGE, "--all"], env=self.env, capture_output=True, text=True)
        got = json.loads(r.stdout)
        self.assertEqual([(u["account"], u["error"]) for u in got],
                         [("default", "Not signed in to Claude Code"), ("work", "Not signed in to Claude Code")])
        one = json.loads(subprocess.run([USAGE, "--account", "nope"], env=self.env, capture_output=True, text=True).stdout)
        self.assertEqual(one, {"account": "nope", "error": "No such Claude account"})


if __name__ == "__main__":
    unittest.main()
