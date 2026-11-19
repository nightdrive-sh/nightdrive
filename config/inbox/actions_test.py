#!/usr/bin/env python3
"""Tests for actions.py: the buttons a sender may give, and what is refused."""
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))
import actions  # noqa: E402
from store import InboxError  # noqa: E402

SID = "4ff6a8b3-7364-4eef-8dc2-9dcbb23180a7"


class ActionsTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = self.tmp.name
        open(os.path.join(self.dir, "game.x86_64"), "w").close()

    def tearDown(self):
        self.tmp.cleanup()

    def test_run_keeps_an_argv_and_its_folder(self):
        a = actions.check({"kind": "run", "label": "Start the game", "command": "godot --path 'my game'"}, self.dir)
        self.assertEqual(a, {"kind": "run", "label": "Start the game", "argv": ["godot", "--path", "my game"],
                             "dir": self.dir})

    def test_run_never_keeps_a_shell_line(self):
        a = actions.check({"kind": "run", "label": "x", "command": "make && rm -rf /"}, self.dir)
        self.assertEqual(a["argv"], ["make", "&&", "rm", "-rf", "/"], "&& is a word, not a shell's")

    def test_run_refuses_what_it_cannot_run(self):
        for bad in ({"command": ""}, {"argv": []}, {"argv": ["ok", ""]}, {"argv": "ls"}, {"command": "'open"},
                    {"command": "ls", "dir": "/no/such"}, {"command": "x" * 5000}):
            with self.subTest(bad=bad), self.assertRaises(InboxError):
                actions.check({"kind": "run", "label": "x", **bad}, self.dir)

    def test_open_takes_a_path_that_exists_relative_to_the_sender(self):
        a = actions.check({"kind": "open", "label": "Game", "path": "game.x86_64"}, self.dir)
        self.assertEqual(a["path"], os.path.join(self.dir, "game.x86_64"))
        with self.assertRaises(InboxError):
            actions.check({"kind": "open", "label": "Gone", "path": "missing"}, self.dir)

    def test_url_is_http_only(self):
        self.assertEqual(actions.check({"kind": "url", "label": "Site", "url": "https://x.fi/a"}, self.dir)["url"],
                         "https://x.fi/a")
        for url in ("file:///etc/passwd", "javascript:alert(1)", "https://a b"):
            with self.subTest(url=url), self.assertRaises(InboxError):
                actions.check({"kind": "url", "label": "x", "url": url}, self.dir)

    def test_session_and_task(self):
        self.assertEqual(actions.check({"kind": "session", "label": "Go", "session": SID}, self.dir)["session"], SID)
        self.assertEqual(actions.check({"kind": "task", "label": "Task", "task": "#3132"}, self.dir)["task"], 3132)
        for bad in ({"kind": "session", "session": "abc"}, {"kind": "task", "task": True},
                    {"kind": "task", "task": 0}, {"kind": "task", "task": "x"}):
            with self.subTest(bad=bad), self.assertRaises(InboxError):
                actions.check({"label": "x", **bad}, self.dir)

    def test_labels_and_kinds(self):
        for bad in ({"kind": "shell", "label": "x"}, {"kind": "url", "url": "https://x.fi"},
                    {"kind": "url", "label": "x" * 61, "url": "https://x.fi"}, "url"):
            with self.subTest(bad=bad), self.assertRaises(InboxError):
                actions.check(bad, self.dir)

    def test_at_most_so_many_buttons(self):
        one = {"kind": "url", "label": "x", "url": "https://x.fi"}
        self.assertEqual(len(actions.check_all([one] * actions.ACTIONS_MAX, self.dir)), actions.ACTIONS_MAX)
        with self.assertRaises(InboxError):
            actions.check_all([one] * 2, self.dir, already=actions.ACTIONS_MAX - 1)

    def test_from_cli(self):
        got = actions.from_cli([("run", "Build", "make all"), ("task", "Task", "3132")])
        self.assertEqual(got, [{"kind": "run", "label": "Build", "command": "make all"},
                               {"kind": "task", "label": "Task", "task": "3132"}])

    def test_describe_shows_the_whole_command(self):
        a = actions.check({"kind": "run", "label": "Go", "argv": ["echo", "a b"]}, self.dir)
        self.assertIn("echo 'a b'", actions.describe(a))
        self.assertIn(self.dir, actions.describe(a))


if __name__ == "__main__":
    unittest.main()
