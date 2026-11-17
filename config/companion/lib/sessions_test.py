"""Companion's view of the sessions (sessions.py): which windows it may type into, and a permission request's id.

    python3 config/companion/lib/sessions_test.py
"""
import json
import os
import sys
import tempfile
import unittest
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import sessions  # noqa: E402


class WindowTest(unittest.TestCase):
    def look(self, found, clients):
        s = sessions.Sessions()
        runs = {sessions.SESSIONS: found, "clients": clients, "activewindow": {}}
        with mock.patch.object(sessions, "_run_json", lambda argv, d: runs.get(argv[0], runs.get(argv[-1], d))), \
                mock.patch.object(sessions.transcript, "last", return_value=""), \
                mock.patch.object(sessions, "STATE", tempfile.mkdtemp()):
            s.look()
        return s

    def test_only_a_listed_session(self):
        s = self.look([{"address": "0xa1", "dir": "/p"}], [{"address": "0xa1", "title": "✳ x"}, {"address": "0xb2"}])
        self.assertEqual(s.window("0xa1"), "0xa1")
        for other in ("0xb2", "0xa1/../x", ""):       # another window (a root terminal), or not a window at all
            with self.assertRaises(ValueError):
                s.window(other)

    def test_a_session_whose_window_is_gone(self):
        s = self.look([{"address": "0xa1", "dir": "/p"}], [])
        with self.assertRaises(ValueError):
            s.window("0xa1")


class PermissionTest(unittest.TestCase):
    def setUp(self):
        self.state = tempfile.mkdtemp()
        patcher = mock.patch.object(sessions, "STATE", self.state)
        patcher.start()
        self.addCleanup(patcher.stop)

    def perm(self, data):
        with open(os.path.join(self.state, "0xa1.perm"), "w") as f:
            f.write(data if isinstance(data, str) else json.dumps(data))
        return sessions._permission("0xa1")

    def test_request_id(self):
        p = self.perm({"tool": "Bash", "what": "ls", "request": "aB3dE9", "allow": True})
        self.assertEqual((p["request"], p["allow"]), ("aB3dE9", True))

    def test_old_hook_gets_deny_only(self):
        # an old claude-notify only touches the file: no id, so no Allow
        self.assertFalse(self.perm("")["allow"])
        self.assertFalse(self.perm({"tool": "Bash", "what": "ls", "allow": True})["allow"])

    def test_answer_names_its_request(self):
        sessions.Sessions().answer("0xa1", "allow", "aB3dE9")
        with open(os.path.join(self.state, "0xa1.answer")) as f:
            self.assertEqual(f.read(), "allow aB3dE9\n")

    def test_answer_without_a_good_id_is_refused(self):
        for bad in ("", "a b", "x\nallow y"):
            with self.assertRaises(ValueError):
                sessions.Sessions().answer("0xa1", "deny", bad)
        self.assertFalse(os.path.exists(os.path.join(self.state, "0xa1.answer")))


if __name__ == "__main__":
    unittest.main()
