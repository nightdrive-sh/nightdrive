"""A permission request whole before Companion's Allow (permission.py, sessions._permission; #3137): every key shown in
full, hidden characters written out, and Allow only for the request whose input was shown.

    python3 config/companion/lib/permission_test.py
"""
import json
import os
import sys
import tempfile
import unittest
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import permission  # noqa: E402
import sessions  # noqa: E402

EDIT = {"file_path": "/home/me/notes.md", "old_string": "a\n\tb", "new_string": "a\n\tb c", "replace_all": False}


class VisibleTest(unittest.TestCase):
    def test_hidden_characters_written_out(self):
        for ch, shown in (("‮", "⟨U+202E⟩"),      # right-to-left override: turns text around
                          ("​", "⟨U+200B⟩"),      # zero-width space
                          ("⁦", "⟨U+2066⟩"),      # bidi isolate
                          (" ", "⟨U+00A0⟩"),      # a space that isn't one
                          ("\x1b", "⟨U+001B⟩"),        # a terminal escape
                          ("\r", "⟨U+000D⟩"),
                          (" ", "⟨U+2028⟩")):
            self.assertEqual(permission.visible(f"x{ch}y"), (f"x{shown}y", 1), repr(ch))

    def test_what_shows_stays(self):
        text = "rm -rf ./build\n\tä ö 🙂 שלום"
        self.assertEqual(permission.visible(text), (text, 0))


class FieldsTest(unittest.TestCase):
    def test_every_key_in_order_nothing_cut(self):
        long = "x" * 100_000
        f = permission.fields({**EDIT, "new_string": long})
        self.assertEqual([x["key"] for x in f], ["file_path", "old_string", "new_string", "replace_all"])
        self.assertEqual(f[2]["text"], long)
        self.assertEqual(f[3]["text"], "false")

    def test_an_mcp_tools_input_as_json(self):
        f = permission.fields({"id": 42, "edits": [{"old": "a", "new": "b​"}]})
        self.assertEqual(f[0]["text"], "42")
        self.assertIn('"old": "a"', f[1]["text"])
        self.assertIn("⟨U+200B⟩", f[1]["text"])
        self.assertEqual(f[1]["hidden"], 1)

    def test_a_hidden_key(self):
        self.assertEqual(permission.fields({"a‮b": "x"})[0], {"key": "a⟨U+202E⟩b", "text": "x", "hidden": 1})


class RequestTest(unittest.TestCase):
    """What the hook leaves (<addr>.perm, <addr>.input) as the page gets it."""

    def setUp(self):
        self.state = tempfile.mkdtemp()
        patcher = mock.patch.object(sessions, "STATE", self.state)
        patcher.start()
        self.addCleanup(patcher.stop)

    def leave(self, perm, inp=None):
        with open(os.path.join(self.state, "0xa1.perm"), "w") as f:
            json.dump(perm, f)
        if inp is not None:
            with open(os.path.join(self.state, "0xa1.input"), "w") as f:
                json.dump(inp, f)

    def test_edit_offers_review(self):
        self.leave({"tool": "Edit", "what": EDIT["file_path"], "request": "R1", "allow": False, "whole": True},
                   {"request": "R1", "input": EDIT})
        p = sessions._permission("0xa1")
        self.assertEqual((p["allow"], p["review"]), (True, True))
        got = sessions.Sessions().request("0xa1")
        self.assertEqual(got["request"], "R1")
        self.assertEqual({f["key"]: f["text"] for f in got["fields"]}["new_string"], "a\n\tb c")

    def test_a_short_command_keeps_its_allow(self):
        self.leave({"tool": "Bash", "what": "ls", "request": "R1", "allow": True, "whole": True},
                   {"request": "R1", "input": {"command": "ls"}})
        p = sessions._permission("0xa1")
        self.assertEqual((p["allow"], p["review"]), (True, False))

    def test_no_allow_without_the_input(self):
        # too long for the hook to leave it (whole false), or an old hook: Deny only, and nothing to review
        for perm, inp in (({"tool": "Write", "request": "R1", "allow": False, "whole": False}, None),
                          ({"tool": "Write", "request": "R1", "allow": False}, None),
                          ({"tool": "Write", "request": "R1", "allow": False, "whole": True}, None)):
            for name in ("0xa1.perm", "0xa1.input"):
                if os.path.exists(os.path.join(self.state, name)):
                    os.remove(os.path.join(self.state, name))
            self.leave(perm, inp)
            self.assertEqual(sessions._permission("0xa1")["allow"], False, perm)
            with self.assertRaises(ValueError):
                sessions.Sessions().request("0xa1")

    def test_another_requests_input_is_not_shown(self):
        # the session asks something new: an input left for the last request isn't this one's
        self.leave({"tool": "Edit", "request": "R2", "allow": False, "whole": True}, {"request": "R1", "input": EDIT})
        self.assertFalse(sessions._permission("0xa1")["allow"])
        with self.assertRaises(ValueError):
            sessions.Sessions().request("0xa1")

    def test_bad_request_ids(self):
        for req in ("", "a b", "../x", "R" * 33):
            self.leave({"tool": "Edit", "request": req, "allow": False, "whole": True}, {"request": req, "input": EDIT})
            self.assertFalse(sessions._permission("0xa1")["allow"], req)

    def test_input_not_an_object(self):
        self.leave({"tool": "Edit", "request": "R1", "allow": False, "whole": True}, {"request": "R1", "input": "x"})
        self.assertFalse(sessions._permission("0xa1")["allow"])

    def test_no_request(self):
        with self.assertRaises(ValueError):
            sessions.Sessions().request("0xa1")


if __name__ == "__main__":
    unittest.main()
