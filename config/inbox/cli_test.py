#!/usr/bin/env python3
"""Tests for cli.py (nightdrive inbox), run as the command is: post from a Claude session and from an app, the JSON
Claude's tools send, update only by the sender, list, show, read, archive, count."""
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
CLI = HERE / "cli.py"
SID = "4ff6a8b3-7364-4eef-8dc2-9dcbb23180a7"
OTHER = "11111111-2222-3333-4444-555555555555"


class CliTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.home = Path(self.tmp.name).resolve()
        self.project = self.home / "Projects" / "coldstart"
        self.project.mkdir(parents=True)
        (self.project / "shot.png").write_bytes(b"\x89PNG")
        sessions = self.home / ".claude" / "sessions"
        sessions.mkdir(parents=True)
        (sessions / "123.json").write_text(json.dumps(
            {"pid": 123, "sessionId": SID, "cwd": str(self.project), "name": "#3132 Cold Start shots"}))

    def tearDown(self):
        self.tmp.cleanup()

    def run_cli(self, *args, session=SID, stdin=None, ok=True):
        env = {"HOME": str(self.home), "PATH": os.environ.get("PATH", "/usr/bin"), "PWD": str(self.project)}
        if session:
            env["CLAUDE_CODE_SESSION_ID"] = session
        p = subprocess.run([sys.executable, "-I", str(CLI), *args], capture_output=True, text=True, env=env,
                           cwd=self.project, input=stdin)
        if ok:
            self.assertEqual(p.returncode, 0, p.stderr)
        return p

    def jcli(self, *args, **kw):
        return json.loads(self.run_cli(*args, "--json", **kw).stdout)

    def test_a_session_posts_and_is_named_by_itself(self):
        msg = self.jcli("post", "Shots are ready", "--body", "Look at **these**", "--attach", "shot.png",
                        "--action", "run", "Start the game", "godot --path .")
        self.assertEqual(msg["from"]["kind"], "claude")
        self.assertEqual(msg["from"]["session"], SID)
        self.assertEqual(msg["from"]["name"], "#3132 Cold Start shots")
        self.assertEqual(msg["from"]["project"], "coldstart")
        self.assertEqual(msg["from"]["account"], "default")
        self.assertEqual(msg["task"], 3132, "the task comes from the session's name")
        self.assertEqual((msg["attachments"], msg["actions"]), (1, 1))
        full = self.jcli("show", msg["id"])
        self.assertEqual(full["actions"][0]["argv"], ["godot", "--path", "."])
        self.assertEqual(full["actions"][0]["dir"], str(self.project))
        self.assertEqual(Path(full["attachments"][0]["path"]).read_bytes(), b"\x89PNG")
        self.assertIsNone(full["read"], "show alone doesn't mark it read: Claude may read it")

    def test_relative_paths_start_where_it_was_sent_from(self):
        sub = self.project / "sub"
        sub.mkdir()
        (sub / "b.png").write_bytes(b"x")
        env_dir = self.run_cli("post", "Here", "--attach", "b.png", "--dir", str(sub), "--json")
        self.assertEqual(json.loads(env_dir.stdout)["attachments"], 1)
        p = self.run_cli("post", "There", "--attach", "b.png", ok=False)
        self.assertIn("doesn't exist", p.stderr, "without --dir: the current folder, not sub/")

    def test_the_tools_json_on_stdin(self):
        req = {"title": "From the tool", "body": "Text", "attachments": [str(self.project / "shot.png")],
               "actions": [{"kind": "url", "label": "Site", "url": "https://example.com"}], "task": "#42"}
        msg = self.jcli("post", "--stdin-json", stdin=json.dumps(req))
        self.assertEqual((msg["title"], msg["task"], msg["attachments"], msg["actions"]), ("From the tool", 42, 1, 1))

    def test_an_app_and_a_plain_command(self):
        app = self.jcli("post", "Transcribed", "--app", "Recorder", session=None)
        self.assertEqual(app["from"], {"kind": "app", "app": "Recorder"})
        other = self.jcli("post", "From a script", session=None)
        self.assertEqual(other["from"]["kind"], "other")
        self.assertIsNone(other["task"])

    def test_refusals_leave_nothing(self):
        for args in (["post", ""], ["post", "x", "--attach", "/etc/hostname"],
                     ["post", "x", "--action", "url", "Bad", "file:///etc/passwd"]):
            with self.subTest(args=args):
                p = self.run_cli(*args, ok=False)
                self.assertEqual(p.returncode, 1)
                self.assertTrue(p.stderr.startswith("inbox: "), p.stderr)
        self.assertEqual(self.jcli("count")["total"], 0)

    def test_only_the_sender_updates_and_an_update_can_be_undone(self):
        mid = self.jcli("post", "Build", "--body", "Started")["id"]
        self.run_cli("read", mid)
        p = self.run_cli("update", mid, "--append", "Hijack", session=OTHER, ok=False)
        self.assertIn("only its sender", p.stderr)
        up = self.jcli("update", mid, "--append", "Done", "--action", "open", "Shot", "shot.png")
        self.assertEqual((up["rev"], up["read"], up["actions"]), (1, None, 1))
        self.assertEqual(self.jcli("show", mid)["body"], "Started\n\nDone")
        self.jcli("revert", mid, "1")
        back = self.jcli("show", mid)
        self.assertEqual((back["body"], back["actions"]), ("Started", []))
        p = self.run_cli("update", mid, ok=False)
        self.assertIn("nothing to change", p.stderr)

    def test_list_read_archive_count(self):
        a = self.jcli("post", "First")["id"]
        b = self.jcli("post", "Second", "--app", "Tasks")["id"]
        listed = self.jcli("list")
        self.assertEqual(({m["id"] for m in listed["messages"]}, listed["unread"]), ({a, b}, 2))
        self.assertEqual([m["id"] for m in self.jcli("list", "--mine")["messages"]], [a])
        self.jcli("read", a)
        self.assertEqual([m["id"] for m in self.jcli("list", "--unread")["messages"]], [b])
        self.assertEqual(self.jcli("count"), {"unread": 1, "total": 2, "claude": 0})
        self.jcli("archive", b[-4:])
        self.assertEqual(self.jcli("count")["unread"], 0)
        self.assertEqual([m["id"] for m in self.jcli("list", "--archived")["messages"]], [b])
        self.jcli("archive", b, "--undo")
        self.jcli("read", "--all")
        self.assertEqual(self.jcli("count")["unread"], 0)
        self.assertTrue(self.jcli("show", b, "--mark-read")["read"])
        self.jcli("delete", a)
        self.assertEqual(self.jcli("count")["total"], 1)

    def test_the_sessions_count_and_key(self):
        a = self.jcli("post", "Mine")["id"]
        self.jcli("post", "Theirs", session=OTHER)
        self.jcli("post", "Theirs too", session=OTHER)
        self.jcli("post", "An app's", "--app", "Tasks")
        self.assertEqual(self.jcli("count"), {"unread": 4, "total": 4, "claude": 3})
        self.jcli("read", a)
        self.assertEqual(self.jcli("count")["claude"], 2)
        self.assertEqual(len(self.jcli("list", "--from", "claude")["messages"]), 3)

    def test_text_output(self):
        mid = self.jcli("post", "Readable", "--action", "run", "Go", "echo 'a b'")["id"]
        self.assertIn("Readable", self.run_cli("list").stdout)
        shown = self.run_cli("show", mid).stdout
        self.assertIn("echo 'a b'", shown)
        self.assertIn("#3132 Cold Start shots · coldstart", shown)


if __name__ == "__main__":
    unittest.main()
