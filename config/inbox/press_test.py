#!/usr/bin/env python3
"""Tests for the window's side of nightdrive inbox (#3178): list's senders, --from and --search (query.py), and press
(press.py): a run button only with --yes, in its folder, its output in a log; a task without task_url copied."""
import json
import os
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
CLI = HERE / "cli.py"
SID = "4ff6a8b3-7364-4eef-8dc2-9dcbb23180a7"


class PressTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.home = Path(self.tmp.name).resolve()
        self.project = self.home / "Projects" / "coldstart"
        self.project.mkdir(parents=True)
        sessions = self.home / ".claude" / "sessions"
        sessions.mkdir(parents=True)
        (sessions / "1.json").write_text(json.dumps({"sessionId": SID, "cwd": str(self.project), "name": "#77 Shots"}))
        # Stand-ins for xdg-open and wl-copy: they write down what they were given
        self.bin = self.home / "bin"
        self.bin.mkdir()
        for name in ("xdg-open", "wl-copy"):
            tool = self.bin / name
            tool.write_text(f'#!/bin/sh\necho "$@" > "{self.home}/{name}.out"\n')
            tool.chmod(0o755)

    def tearDown(self):
        self.tmp.cleanup()

    def jcli(self, *args, session=SID, ok=True):
        env = {"HOME": str(self.home), "PATH": f"{self.bin}:/usr/bin:/bin"}
        if session:
            env["CLAUDE_CODE_SESSION_ID"] = session
        p = subprocess.run([sys.executable, "-I", str(CLI), *args, "--json"], capture_output=True, text=True,
                           env=env, cwd=self.project)
        self.assertEqual(p.returncode == 0, ok, p.stderr)
        return json.loads(p.stdout) if ok else p.stderr

    def wait_for(self, path):
        for _ in range(50):
            if path.exists() and path.read_text().strip():
                return path.read_text().strip()
            time.sleep(0.05)
        self.fail(f"{path} never came")

    def test_senders_from_and_search(self):
        a = self.jcli("post", "Shots ready", "--body", "The **bridge** level")["id"]
        b = self.jcli("post", "Transcribed", "--app", "Recorder", session=None)["id"]
        listed = self.jcli("list")
        keys = {g["key"]: g for g in listed["senders"]}
        self.assertEqual(set(keys), {"project:coldstart", "app:Recorder"})
        self.assertEqual((keys["project:coldstart"]["label"], keys["project:coldstart"]["unread"]), ("coldstart", 1))
        row = next(m for m in listed["messages"] if m["id"] == a)
        self.assertEqual(row["sender"]["short"], "#77 Shots")
        self.assertEqual(row["sender"]["session"], "session:" + SID)
        self.assertEqual([m["id"] for m in self.jcli("list", "--from", "app:Recorder")["messages"]], [b])
        self.assertEqual([m["id"] for m in self.jcli("list", "--from", "session:" + SID)["messages"]], [a])
        found = self.jcli("list", "--search", "BRIDGE level")
        self.assertEqual(([m["id"] for m in found["messages"]], len(found["senders"])), ([a], 2))
        self.assertEqual(self.jcli("list", "--search", "#77")["total"], 1)
        self.assertEqual(self.jcli("list", "--search", "nowhere")["total"], 0)

    def test_run_needs_yes_and_runs_in_its_folder(self):
        mid = self.jcli("post", "Build", "--action", "run", "Where", "sh -c 'pwd > where.txt'")["id"]
        err = self.jcli("press", mid, "0", ok=False)
        self.assertIn("--yes", err)
        self.assertFalse((self.project / "where.txt").exists(), "nothing ran without --yes")
        done = self.jcli("press", mid, "0", "--yes")
        self.assertEqual(done["dir"], str(self.project))
        self.assertEqual(self.wait_for(self.project / "where.txt"), str(self.project))
        self.assertTrue(Path(done["log"]).parent.is_dir())

    def test_open_url_and_the_senders_task(self):
        mid = self.jcli("post", "Site", "--action", "url", "Open it", "https://example.com")["id"]
        self.assertEqual(self.jcli("press", mid, "0")["opened"], "https://example.com")
        self.assertEqual(self.wait_for(self.home / "xdg-open.out"), "https://example.com")
        self.assertEqual(self.jcli("press", mid, "task")["copied"], "#77", "no task_url: the number copied")
        conf = self.home / ".config" / "nightdrive"
        conf.mkdir(parents=True)
        (conf / "inbox.json").write_text(json.dumps({"task_url": "https://tasks.example/t/{n}"}))
        self.assertEqual(self.jcli("press", mid, "task")["opened"], "https://tasks.example/t/77")
        self.assertIn("no button 3", self.jcli("press", mid, "3", ok=False))
        other = self.jcli("post", "Plain", session=None)["id"]
        self.assertIn("isn't from a Claude session", self.jcli("press", other, "session", ok=False))


if __name__ == "__main__":
    unittest.main()
