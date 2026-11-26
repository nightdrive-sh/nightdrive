#!/usr/bin/env python3
"""claude-history's rules (#3120): `python3 config/topbar/scripts/claude-history_test.py`. A transcript's name, folder,
last prompt and account read from its ends, a shared projects/ folder listed once, the cache trusted only while the file
is the same, and the search. Made-up transcripts in a throwaway folder; claude-sessions is never run."""

import importlib.machinery
import importlib.util
import json
import os
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
loader = importlib.machinery.SourceFileLoader("claude_history", os.path.join(HERE, "claude-history"))
ch = importlib.util.module_from_spec(importlib.util.spec_from_loader("claude_history", loader))
loader.exec_module(ch)

SID1 = "11111111-1111-4111-8111-111111111111"
SID2 = "22222222-2222-4222-8222-222222222222"
SID3 = "33333333-3333-4333-8333-333333333333"


def line(**kw):
    return json.dumps(kw, separators=(",", ":"))


class Base(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = self.tmp.name
        ch.CACHE = os.path.join(self.root, "cache", "claude-history.json")
        self.acct = {"name": "default", "dir": os.path.join(self.root, "claude"), "default": True, "uuid": "u-default"}
        self.work = {"name": "work", "dir": os.path.join(self.root, "claude-work"), "default": False, "uuid": "u-work"}
        os.makedirs(os.path.join(self.acct["dir"], "projects"))
        # the second account's projects/ is a link to the first's, as on a machine that shares them
        os.makedirs(self.work["dir"])
        os.symlink(os.path.join(self.acct["dir"], "projects"), os.path.join(self.work["dir"], "projects"))

    def tearDown(self):
        self.tmp.cleanup()

    def transcript(self, sid, lines, folder="-home-me-proj", mtime=None):
        d = os.path.join(self.acct["dir"], "projects", folder)
        os.makedirs(d, exist_ok=True)
        path = os.path.join(d, sid + ".jsonl")
        with open(path, "w") as f:
            f.write("\n".join(lines) + "\n")
        if mtime:
            os.utime(path, (mtime, mtime))
        return path

    def listing(self):
        return ch.closed_and_open([self.acct, self.work])


class Reading(Base):
    def test_name_folder_prompt_account(self):
        self.transcript(SID1, [
            line(type="custom-title", customTitle="#3120 Launcher Sessions", sessionId=SID1),
            line(type="session-owner", accountUuid="u-work", sessionId=SID1),
            line(type="user", cwd="/home/me/proj", sessionId=SID1, message={"content": "hi"}),
            line(type="user", cwd="/home/me/proj/sub", sessionId=SID1, message={"content": "cd sub"}),
            line(type="last-prompt", lastPrompt="first", sessionId=SID1),
            line(type="custom-title", customTitle="#3120 Renamed", sessionId=SID1),
            line(type="last-prompt", lastPrompt="the latest", sessionId=SID1),
        ])
        [s] = self.listing()
        self.assertEqual(s["id"], SID1)
        self.assertEqual(s["name"], "#3120 Renamed")            # the latest name
        self.assertEqual(s["dir"], "/home/me/proj")             # where it started: --resume finds it there
        self.assertEqual(s["prompt"], "the latest")
        self.assertEqual(s["task"], 3120)
        self.assertEqual((s["account"], s["accountDefault"]), ("work", False))   # by its owner, not by the folder

    def test_quoted_lines_are_not_its_own(self):
        # a message that quotes a transcript (a tool's output) has its quotes escaped: never taken for the name
        quoted = '{"type":"custom-title","customTitle":"Fake"}'
        self.transcript(SID1, [
            line(type="agent-name", agentName="Agent name", sessionId=SID1),
            line(type="user", cwd="/p", sessionId=SID1, message={"content": quoted}),
            line(type="assistant", cwd="/p", message={"content": "x\n" + quoted}),
        ])
        [s] = self.listing()
        self.assertEqual(s["name"], "Agent name")
        self.assertIsNone(s["task"])

    def test_long_transcript_read_at_both_ends(self):
        big = "x" * (ch.TAIL + ch.HEAD)
        self.transcript(SID1, [
            line(type="custom-title", customTitle="Early name", sessionId=SID1),
            line(type="user", cwd="/start", sessionId=SID1, message={"content": "a"}),
            line(type="assistant", message={"content": big}),
            line(type="last-prompt", lastPrompt="late", sessionId=SID1),
        ])
        [s] = self.listing()
        self.assertEqual((s["name"], s["dir"], s["prompt"]), ("Early name", "/start", "late"))

    def test_empty_session_and_others_left_out(self):
        self.transcript(SID1, [line(type="mode", mode="normal", sessionId=SID1)])   # no message: nothing to resume
        d = os.path.join(self.acct["dir"], "projects", "-home-me-proj", SID2, "subagents")
        os.makedirs(d)
        with open(os.path.join(d, "agent-a1.jsonl"), "w") as f:
            f.write(line(type="user", cwd="/p") + "\n")
        with open(os.path.join(self.acct["dir"], "projects", "-home-me-proj", "notes.jsonl"), "w") as f:
            f.write(line(type="user", cwd="/p") + "\n")
        self.assertEqual(self.listing(), [])

    def test_shared_projects_listed_once_newest_first(self):
        self.transcript(SID1, [line(type="user", cwd="/a", sessionId=SID1)], mtime=1000)
        self.transcript(SID2, [line(type="user", cwd="/b", sessionId=SID2)], folder="-b", mtime=3000)
        self.transcript(SID3, [line(type="user", cwd="/c", sessionId=SID3)], folder="-c", mtime=2000)
        self.assertEqual([s["id"] for s in self.listing()], [SID2, SID3, SID1])
        # without an owner line: the account whose projects/ it was found in first, the default
        self.assertTrue(all(s["account"] == "default" for s in self.listing()))


class Cache(Base):
    def test_unchanged_file_not_read_again(self):
        path = self.transcript(SID1, [line(type="user", cwd="/a", sessionId=SID1)], mtime=1000)
        self.listing()
        calls = []
        real = ch.read_transcript
        ch.read_transcript = lambda p, n: calls.append(p) or real(p, n)
        try:
            self.listing()
            self.assertEqual(calls, [])
            with open(path, "a") as f:   # a new turn: the file grows
                f.write(line(type="custom-title", customTitle="Now named", sessionId=SID1) + "\n")
            [s] = self.listing()
            self.assertEqual((calls, s["name"]), ([path], "Now named"))
        finally:
            ch.read_transcript = real

    def test_gone_file_forgotten_and_bad_cache_ignored(self):
        path = self.transcript(SID1, [line(type="user", cwd="/a", sessionId=SID1)])
        self.listing()
        os.unlink(path)
        self.assertEqual(self.listing(), [])
        self.assertEqual(ch.load_cache(), {})
        with open(ch.CACHE, "w") as f:
            f.write("not json")
        self.transcript(SID2, [line(type="user", cwd="/b", sessionId=SID2)])
        self.assertEqual([s["id"] for s in self.listing()], [SID2])


class Search(unittest.TestCase):
    S = {"name": "#3120 Launcher Sessions", "dir": "/home/me/dotfiles", "task": 3120}

    def test_words(self):
        for q, hit in [("launcher", True), ("sess dotfiles", True), ("#3120", True), ("3120", True),
                       ("#312", True), ("remind", False), ("launcher remind", False), ("#3118", False)]:
            self.assertEqual(ch.matches(self.S, q.lower().split()), hit, q)

    def test_no_task(self):
        self.assertFalse(ch.matches({"name": "PM", "dir": "/x", "task": None}, ["#1"]))


if __name__ == "__main__":
    unittest.main()
