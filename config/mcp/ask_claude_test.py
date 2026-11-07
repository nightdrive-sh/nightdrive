#!/usr/bin/env python3
"""Ask Claude's background run (#1886): `python3 config/mcp/ask_claude_test.py`. The script runs against stand-ins for
claude, notify-send and the rest, in a home of its own: every notification's texts come after --, so an answer or a
request that begins with --app-name= or --icon= is shown as text instead of changing the notification, the
background session skips the user's settings files (hooks, plugins) but keeps the model they chose, and it gets
Claude Code's WebSearch and WebFetch only when Access › Web's Read is Allow (#2241), and web_download's folder
(#2242)."""

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
    with open(os.environ["LOG"] + ".mcp", "w") as f:   # the server config, gone with the run's folder after
        f.write(open(sys.argv[sys.argv.index("--mcp-config") + 1]).read())
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

    def access(self, text):
        """Settings › Claude › Access's file in this home, as access.py reads it"""
        path = self.home / ".config/nightdrive/claude-access.json"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)

    def web(self, args):
        """The built-in tools the session gets, and whether WebSearch and WebFetch are allowed or denied"""
        allowed = args[args.index("--allowedTools") + 1:args.index("--disallowedTools")]
        denied = args[args.index("--disallowedTools") + 1:args.index("--append-system-prompt")]
        return args[args.index("--tools") + 1], [t for t in allowed if t.startswith("Web")], \
            [t for t in denied if t.startswith("Web")]

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
        self.access('{"version": 2, "level": "strict"}')
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

    def test_web_on_normal(self):
        # Normal allows the web (log 4035): no file before any install is Normal
        claude, _ = self.ask("find an engine sound", "Here.")
        self.assertEqual(self.web(claude[0]), ("WebSearch,WebFetch", ["WebSearch", "WebFetch"], []))
        system = claude[0][claude[0].index("--append-system-prompt") + 1]
        self.assertIn("web search and reading web pages", system)
        self.assertNotIn("no web pages", system)

    def test_no_web_on_strict_or_when_set_no(self):
        for text in ('{"version": 2, "level": "strict"}',
                     '{"version": 2, "level": "open", "areas": {"web": {"read": "no"}}}'):
            self.access(text)
            self.log.unlink(missing_ok=True)
            claude, _ = self.ask("find an engine sound", "I can't.")
            self.assertEqual(self.web(claude[0]), ("", [], ["WebFetch", "WebSearch"]))
            self.assertIn("no web pages", claude[0][claude[0].index("--append-system-prompt") + 1])

    def test_no_web_when_access_is_broken_or_asks(self):
        # A file that can't be read is Strict; Ask, which nothing could answer here, is No
        for text in ("{ not json", '{"version": 2, "level": "normal", "areas": {"web": {"read": "ask"}}}'):
            self.access(text)
            self.log.unlink(missing_ok=True)
            claude, _ = self.ask("find an engine sound", "I can't.")
            self.assertEqual(self.web(claude[0])[0], "")

    def test_downloads_folder_reaches_the_server(self):
        # #2242: web_download's folder is the conversation's, given to the server on its command line; an old
        # conversation's folder goes
        old = self.home / ".local/state/nightdrive/ask/old-one"
        (old / "files").mkdir(parents=True)
        os.utime(old, (0, 0))
        claude, _ = self.ask("find an engine sound", "Here.")
        session = claude[0][claude[0].index("--session-id") + 1]
        files = self.home / f".local/state/nightdrive/ask/{session}/files"
        server = json.loads(Path(f"{self.log}.mcp").read_text())["mcpServers"]["nightdrive"]
        self.assertEqual(server, {"type": "stdio", "command": "/usr/bin/env",
                                  "args": [f"NIGHTDRIVE_ASK_FILES={files}", "/x/bin/nightdrive", "mcp"]})
        self.assertTrue(files.is_dir())
        self.assertEqual(files.stat().st_mode & 0o777, 0o700)
        self.assertFalse(old.exists())

    def test_unreadable_settings_leave_the_model_out(self):
        (self.home / ".claude/settings.json").write_text("{ not json")
        claude, _ = self.ask("hello", "Hi.")
        self.assertNotIn("--model", claude[0])


if __name__ == "__main__":
    unittest.main()
