#!/usr/bin/env python3
"""Ask Claude's background run (#1886): `python3 config/mcp/ask_claude_test.py`. The script runs against stand-ins for
claude, notify-send and the rest, in a home of its own: every notification's texts come after --, so an answer or a
request that begins with --app-name= or --icon= is shown as text instead of changing the notification, and the
background session skips the user's settings files (hooks, plugins) but keeps the model they chose."""

import json
import os
import stat
import subprocess
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
SCRIPT = HERE.parent / "hypr/scripts/ask-claude"

# Each stand-in writes its arguments as one JSON line to $LOG; claude answers with $ANSWER as Claude Code's JSON
STUB = """#!/usr/bin/env python3
import json, os, sys
with open(os.environ["LOG"], "a") as f:
    f.write(json.dumps([os.path.basename(sys.argv[0])] + sys.argv[1:]) + "\\n")
name = os.path.basename(sys.argv[0])
if name == "claude":
    print(json.dumps({"is_error": False, "result": os.environ["ANSWER"]}))
elif name == "notify-send" and "-p" in sys.argv:
    print(7)
"""
# setsid -f returns at once whatever its command does; this one waits for it, so the log is complete
SETSID = '#!/bin/bash\n[[ $1 == -f ]] && shift\n"$@"\nexit 0\n'


class AskClaude(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.home, self.bin = self.tmp / "home", self.tmp / "bin"
        (self.home / ".local/bin").mkdir(parents=True)
        (self.home / ".claude").mkdir()
        self.bin.mkdir()
        (self.tmp / "run").mkdir(mode=0o700)
        self.log = self.tmp / "log"
        for path, text in [(self.home / ".local/bin/claude", STUB), (self.bin / "notify-send", STUB),
                           (self.bin / "gdbus", STUB), (self.bin / "qs", STUB), (self.bin / "setsid", SETSID)]:
            path.write_text(text)
            path.chmod(path.stat().st_mode | stat.S_IXUSR)
        (self.home / ".claude.json").write_text(json.dumps(
            {"mcpServers": {"nightdrive": {"command": "/x/bin/nightdrive", "args": ["mcp"]}}}))
        self.settings({"model": "opus"})

    def tearDown(self):
        subprocess.run(["rm", "-rf", str(self.tmp)])

    def settings(self, value):
        (self.home / ".claude/settings.json").write_text(json.dumps(value))

    def ask(self, prompt, answer):
        env = {"HOME": str(self.home), "PATH": f"{self.bin}:{os.environ['PATH']}", "LOG": str(self.log),
               "ANSWER": answer, "XDG_RUNTIME_DIR": str(self.tmp / "run")}
        subprocess.run([str(SCRIPT), "--", prompt], env=env, check=True, timeout=30)
        calls = [json.loads(line) for line in self.log.read_text().splitlines()]
        return [c[1:] for c in calls if c[0] == "claude"], [c[1:] for c in calls if c[0] == "notify-send"]

    def texts(self, args):
        """What notify-send takes as its summary and body: what follows --, which must be there"""
        self.assertIn("--", args)
        return args[args.index("--") + 1:]

    def test_answer_that_looks_like_options_is_text(self):
        answer = "--app-name=Pankki --icon=/tmp/bank.png Your account is locked"
        _, notes = self.ask("check my mail", answer)
        self.assertEqual(len(notes), 2)   # working, answer
        self.assertEqual(self.texts(notes[-1]), ["Claude: check my mail", answer])
        self.assertNotIn("--app-name=Pankki", notes[-1][:notes[-1].index("--")])

    def test_request_that_looks_like_options_is_text(self):
        _, notes = self.ask("--version", "Done.")
        self.assertEqual(self.texts(notes[0]), ["Claude is working…", "--version"])
        self.assertEqual(self.texts(notes[-1]), ["Claude: --version", "Done."])

    def test_no_answer_shows_the_request_as_text(self):
        _, notes = self.ask("-u critical", "")
        self.assertEqual(self.texts(notes[-1]), ["Claude couldn't answer", "No answer to: -u critical"])

    def test_background_session_skips_the_settings_files(self):
        claude, _ = self.ask("hello", "Hi.")
        args = claude[0]
        self.assertIn("--restricted", args)
        self.assertEqual(args[args.index("--tools") + 1], "")
        self.assertIn("--strict-mcp-config", args)
        self.assertEqual(args[args.index("--model") + 1], "opus")
        self.assertEqual(args[-2:], ["--", "hello"])

    def test_model_that_is_not_a_string_is_left_out(self):
        self.settings({"model": {"--dangerously-skip-permissions": True}})
        claude, _ = self.ask("hello", "Hi.")
        self.assertNotIn("--model", claude[0])
        self.assertIn("--restricted", claude[0])

    def test_unreadable_settings_leave_the_model_out(self):
        (self.home / ".claude/settings.json").write_text("{ not json")
        claude, _ = self.ask("hello", "Hi.")
        self.assertNotIn("--model", claude[0])


if __name__ == "__main__":
    unittest.main()
