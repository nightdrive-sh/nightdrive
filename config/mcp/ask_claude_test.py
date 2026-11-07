#!/usr/bin/env python3
"""Ask Claude's background run (#1886, #2244): `python3 config/mcp/ask_claude_test.py`. The script runs against
stand-ins for claude, notify-send, systemd-run and the rest, in a home of its own: every notification's texts come after
--, so an answer or a request that begins with --app-name= or --icon= is shown as text instead of changing the
notification; the background session skips the user's settings files (hooks, plugins) but keeps the model they chose,
and it gets Claude Code's WebSearch and WebFetch only when Access › Web's Read is Allow (#2241), and web_download's
folder (#2242). A turn runs as a systemd user unit (setsid without a user manager) and writes its events to the
conversation's events.jsonl, which ends with how it ended; one runs at a time, and it can be cancelled."""

import json
import os
import socket
import stat
import subprocess
import tempfile
import time
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
SCRIPT = HERE.parent / "hypr/scripts/ask-claude"

# Each stand-in writes its arguments as one JSON line to $LOG; claude answers with $ANSWER as Claude Code's stream-json,
# after $SLEEP seconds (so the working notification is up first)
STUB = """#!/usr/bin/env python3
import json, os, sys, time
with open(os.environ["LOG"], "a") as f:
    f.write(json.dumps([os.path.basename(sys.argv[0])] + sys.argv[1:]) + "\\n")
name = os.path.basename(sys.argv[0])
if name == "claude":
    with open(os.environ["LOG"] + ".mcp", "w") as f:   # the server config, gone with the run's folder after
        f.write(open(sys.argv[sys.argv.index("--mcp-config") + 1]).read())
    print(json.dumps({"type": "system", "subtype": "init", "session_id": "x"}), flush=True)
    time.sleep(float(os.environ.get("SLEEP", "0.3")))
    print(json.dumps({"type": "result", "is_error": os.environ.get("FAIL") == "1", "result": os.environ["ANSWER"]}))
elif name == "notify-send" and "-p" in sys.argv:
    print(7)
elif name == "qs" and sys.argv[-1] == "shown":
    print(os.environ.get("QS_SHOWN", ""), end="")
"""
# setsid -f and systemd-run return at once whatever their command does; these wait for it, so the log is complete
SETSID = '#!/bin/bash\n[[ $1 == -f ]] && shift\nif [[ $SETSID_BG == 1 ]]; then "$@" & else "$@"; fi\nexit 0\n'
SYSTEMD_RUN = """#!/usr/bin/env python3
import json, os, subprocess, sys
with open(os.environ["LOG"], "a") as f:
    f.write(json.dumps(["systemd-run"] + sys.argv[1:]) + "\\n")
subprocess.run(sys.argv[sys.argv.index("--") + 1:], stdin=subprocess.DEVNULL, capture_output=True)
"""
SYSTEMCTL = '#!/bin/bash\n[[ $2 == is-active ]] && exit 3\nexit 0\n'


class AskClaude(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.home, self.bin = self.tmp / "home", self.tmp / "bin"
        (self.home / ".local/bin").mkdir(parents=True)
        (self.home / ".claude").mkdir()
        self.bin.mkdir()
        self.run_dir = self.tmp / "run"
        self.run_dir.mkdir(mode=0o700)
        self.log = self.tmp / "log"
        self.state = self.home / ".local/state/nightdrive/ask"
        for path, text in [(self.home / ".local/bin/claude", STUB), (self.bin / "notify-send", STUB),
                           (self.bin / "gdbus", STUB), (self.bin / "qs", STUB), (self.bin / "setsid", SETSID),
                           (self.bin / "systemd-run", SYSTEMD_RUN), (self.bin / "systemctl", SYSTEMCTL)]:
            path.write_text(text)
            path.chmod(path.stat().st_mode | stat.S_IXUSR)
        (self.home / ".claude.json").write_text(json.dumps(
            {"mcpServers": {"nightdrive": {"command": "/x/bin/nightdrive", "args": ["mcp"]}}}))
        self.settings({"model": "opus"})
        self.extra = {}

    def tearDown(self):
        subprocess.run(["rm", "-rf", str(self.tmp)])

    def settings(self, value):
        (self.home / ".claude/settings.json").write_text(json.dumps(value))

    def access(self, text):
        """Settings › Claude › Access's file in this home, as access.py reads it"""
        path = self.home / ".config/nightdrive/claude-access.json"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)

    def env(self, answer="Hi."):
        return {"HOME": str(self.home), "PATH": f"{self.bin}:{os.environ['PATH']}", "LOG": str(self.log),
                "ANSWER": answer, "XDG_RUNTIME_DIR": str(self.run_dir), **self.extra}

    def script(self, *args, answer="Hi.", check=True):
        return subprocess.run([str(SCRIPT), *args], env=self.env(answer), check=check, timeout=30,
                              capture_output=True, text=True)

    def calls(self):
        calls = [json.loads(line) for line in self.log.read_text().splitlines()] if self.log.exists() else []
        return [c[1:] for c in calls if c[0] == "claude"], [c[1:] for c in calls if c[0] == "notify-send"]

    def ask(self, prompt, answer):
        self.script("--", prompt, answer=answer)
        return self.calls()

    def events(self, id):
        return [json.loads(line) for line in (self.state / id / "events.jsonl").read_text().splitlines()]

    def web(self, args):
        """The built-in tools the session gets, and whether WebSearch and WebFetch are allowed or denied"""
        allowed = args[args.index("--allowedTools") + 1:args.index("--disallowedTools")]
        denied = args[args.index("--disallowedTools") + 1:args.index("--append-system-prompt")]
        return args[args.index("--tools") + 1], [t for t in allowed if t.startswith("Web")], \
            [t for t in denied if t.startswith("Web")]

    def texts(self, args):
        """What notify-send takes as its summary and body: what follows --, which must be there"""
        self.assertIn("--", args)
        return args[args.index("--") + 1:]

    # --- notify mode: `ask-claude PROMPT` ---

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
        old = self.state / "old-one"
        (old / "files").mkdir(parents=True)
        os.utime(old, (0, 0))
        claude, _ = self.ask("find an engine sound", "Here.")
        session = claude[0][claude[0].index("--session-id") + 1]
        files = self.state / session / "files"
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

    # --- toast mode: --start, events.jsonl ---

    def start(self, *args, answer="Hi."):
        out = self.script("--start", *args, answer=answer, check=False)
        return json.loads(out.stdout), out.returncode

    def test_turn_writes_its_events(self):
        r, rc = self.start("--name", "Find", "--", "find a sound", answer="Here.")
        self.assertEqual(rc, 0)
        ev = self.events(r["id"])
        self.assertEqual(ev[0]["type"], "nightdrive_turn")
        self.assertEqual(ev[0]["prompt"], "find a sound")
        self.assertEqual([e["type"] for e in ev[1:]], ["system", "result", "nightdrive_end"])
        self.assertEqual(ev[-1]["status"], "done")
        claude, _ = self.calls()
        self.assertIn("stream-json", claude[0])
        self.assertEqual(claude[0][claude[0].index("--session-id") + 1], r["id"])
        self.assertEqual(claude[0][claude[0].index("-n") + 1], "Find")
        self.assertFalse((self.state / r["id"] / "pid").exists())

    def test_resumed_turn_ends_on_its_own_result(self):
        r, _ = self.start("--", "first", answer="One.")
        self.extra = {"FAIL": "1"}
        self.start("--resume", r["id"], "--", "second", answer="Broken")
        claude, _ = self.calls()
        self.assertEqual(claude[1][claude[1].index("--resume") + 1], r["id"])
        ends = [e for e in self.events(r["id"]) if e["type"] == "nightdrive_end"]
        self.assertEqual([(e["status"], e["message"]) for e in ends], [("done", ""), ("error", "Broken")])

    def test_notification_only_when_the_toast_is_closed(self):
        self.extra = {"QS_SHOWN": "open"}
        self.start("--", "hello")
        self.assertEqual(self.calls()[1], [])
        self.extra = {"QS_SHOWN": "closed"}
        self.start("--", "hello", answer="Hi there.")
        note = self.calls()[1][-1]
        self.assertEqual(self.texts(note), ["Claude answered", "Hi there."])
        self.assertIn("default=Open", note)

    def test_one_turn_at_a_time(self):
        r, _ = self.start("--", "first")
        (self.state / r["id"] / "pid").write_text(f"{os.getpid()}\n")   # as if it still ran
        r2, rc = self.start("--", "second")
        self.assertEqual((r2, rc), ({"error": "busy"}, 4))

    def test_no_tools_says_so(self):
        (self.home / ".claude.json").write_text("{}")
        self.assertEqual(self.start("--", "hello"), ({"error": "notools"}, 3))

    def test_cancel_stops_the_turn(self):
        self.extra = {"SETSID_BG": "1", "SLEEP": "20"}
        r, _ = self.start("--", "take long")
        pid = self.state / r["id"] / "pid"
        for _ in range(50):
            if pid.exists():
                break
            time.sleep(0.1)
        self.script("--cancel")
        self.assertEqual(self.events(r["id"])[-1]["status"], "cancelled")
        self.assertEqual(json.loads(self.script("--current").stdout)["running"], False)

    def test_current_seals_a_turn_that_died(self):
        id = "0" * 8 + "-0000-0000-0000-" + "0" * 12
        (self.state / id).mkdir(parents=True)
        (self.state / "current").write_text(id + "\n")
        (self.state / id / "events.jsonl").write_text('{"type":"nightdrive_turn","prompt":"x","at":1}\n')
        cur = json.loads(self.script("--current").stdout)
        self.assertEqual((cur["id"], cur["running"]), (id, False))
        self.assertEqual(self.events(id)[-1]["status"], "error")
        self.assertEqual(json.loads(self.script("--current").stdout)["id"], id)   # sealed once
        self.assertEqual(len(self.events(id)), 2)

    def test_list_newest_first(self):
        a, _ = self.start("--", "first one\nmore")
        time.sleep(0.01)
        b, _ = self.start("--", "second one")
        (self.state / b["id"] / "results.json").write_text('{"version": 1, "cards": [{}, {}]}')
        rows = json.loads(self.script("list", "--json").stdout)
        self.assertEqual([(x["id"], x["title"], x["status"]) for x in rows],
                         [(b["id"], "second one", "done"), (a["id"], "first one", "done")])
        self.assertEqual(rows[0]["results"], 2)

    def test_unit_with_a_user_manager(self):
        (self.run_dir / "systemd").mkdir()
        sock = socket.socket(socket.AF_UNIX)
        sock.bind(str(self.run_dir / "systemd/private"))
        try:
            r, rc = self.start("--", "hello")
        finally:
            sock.close()
        self.assertEqual(rc, 0)
        unit = [json.loads(line) for line in self.log.read_text().splitlines() if line.startswith('["systemd-run", "--user", "--unit"')]
        args = unit[0]
        self.assertEqual(args[args.index("--unit") + 1], "nightdrive-ask")
        self.assertIn("RuntimeMaxSec=960", args)
        self.assertIn("KillMode=mixed", args)
        self.assertEqual(args[args.index("--") + 1:args.index("--") + 4], [str(SCRIPT), "--run", r["id"]])
        self.assertEqual(self.events(r["id"])[-1]["status"], "done")


if __name__ == "__main__":
    unittest.main()
