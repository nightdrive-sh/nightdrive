#!/usr/bin/env python3
"""Claude's Inbox tools (config/mcp/tools/inbox.json, #3132) as the server runs them: inbox_post leaves a message
through `nightdrive inbox post --stdin-json` with the session named by itself, its undo deletes it, inbox_update's
undo reverts it; and `notify: false` logs such a change without the notification a change otherwise shows."""
import json
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import registry  # noqa: E402
import run  # noqa: E402
import undo  # noqa: E402

SID = "4ff6a8b3-7364-4eef-8dc2-9dcbb23180a7"


def tools():
    found, problems = registry.read_file(HERE / "tools/inbox.json", HERE, None)
    assert not problems, problems
    return {t.name: t for t in found}


class InboxToolsTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        home = Path(self.tmp.name).resolve()
        self.project = home / "Projects" / "game"
        self.project.mkdir(parents=True)
        (self.project / "shot.png").write_bytes(b"\x89PNG")
        env = {"HOME": str(home), "CLAUDE_CODE_SESSION_ID": SID,
               "XDG_DATA_HOME": str(home / ".local/share")}
        self.env = mock.patch.dict(os.environ, env)
        self.env.start()
        self.cwd = os.getcwd()
        os.chdir(self.project)   # the server runs in the session's folder
        self.tools = tools()

    def tearDown(self):
        os.chdir(self.cwd)
        self.env.stop()
        self.tmp.cleanup()

    def call(self, name, arguments):
        tool = self.tools[name]
        run.check(tool, arguments)
        return tool, run.run(tool, arguments)

    def inbox(self, *args):
        tool = self.tools["inbox_list"]
        out, err, status = run.execute(tool, ["nightdrive", "inbox", *args, "--json"], None, 30)
        self.assertEqual(status, 0, err)
        return json.loads(out)

    def test_post_names_the_session_and_its_undo_deletes_it(self):
        args = {"title": "Have a look", "body": "**New** menus", "attachments": ["shot.png"],
                "actions": [{"kind": "run", "label": "Start", "command": "godot --path ."}]}
        tool, answer = self.call("inbox_post", args)
        msg = answer["structuredContent"]
        self.assertEqual((msg["from"]["kind"], msg["from"]["session"]), ("claude", SID))
        self.assertEqual((msg["attachments"], msg["actions"]), (1, 1))
        shown = self.inbox("show", msg["id"])
        self.assertEqual(shown["actions"][0]["dir"], str(self.project), "a run button runs in the session's folder")
        argv = run.undo_argv(tool, args, answer)
        out, err, status = run.execute(tool, argv, None, 30)
        self.assertEqual(status, 0, err)
        self.assertEqual(self.inbox("count"), {"unread": 0, "total": 0})

    def test_update_and_its_undo(self):
        _, posted = self.call("inbox_post", {"title": "Build"})
        mid = posted["structuredContent"]["id"]
        args = {"id": mid, "append": "Ready", "actions": [{"kind": "open", "label": "Shot", "path": "shot.png"}]}
        tool, answer = self.call("inbox_update", args)
        self.assertEqual(answer["structuredContent"]["rev"], 1)
        self.assertEqual(self.inbox("show", mid)["body"], "Ready")
        run.execute(tool, run.undo_argv(tool, args, answer), None, 30)
        back = self.inbox("show", mid)
        self.assertEqual((back["body"], back["actions"]), ("", []))

    def test_list_mine(self):
        self.call("inbox_post", {"title": "Mine"})
        _, answer = self.call("inbox_list", {"mine": True})
        self.assertEqual([m["title"] for m in answer["structuredContent"]["messages"]], ["Mine"])

    def test_a_bad_request_is_an_error_claude_reads(self):
        with self.assertRaises(run.ToolError) as e:
            self.call("inbox_post", {"title": "x", "attachments": ["/etc/hostname"]})
        self.assertIn("home folder or /tmp", str(e.exception))


class NotifyTest(unittest.TestCase):
    def spec(self, **more):
        return {"name": "t", "description": "d", "command": ["true"], "class": "change", "undo": ["true"],
                "area": "inbox", "inputSchema": {"type": "object", "properties": {}}, **more}

    def test_registry_takes_notify_only_on_a_change_tool(self):
        self.assertIsNone(registry.problem(self.spec(notify=False), None))
        self.assertIn("notify", registry.problem(self.spec(notify="no"), None))
        self.assertIn("notify", registry.problem(self.spec(notify=False, **{"class": "read"}), None))

    def offer(self, spec):
        tool = registry.Tool(spec, HERE, "test")
        answer = {"content": [], "structuredContent": {}}
        with mock.patch.object(undo.changes, "add", return_value={"id": 9}), \
                mock.patch.object(undo, "show") as show:
            undo.offer(tool, {}, answer)
        return show, answer["content"][-1]["text"]

    def test_notify_false_logs_without_a_notification(self):
        show, said = self.offer(self.spec(notify=False))
        show.assert_not_called()
        self.assertIn("undo_change", said)
        show, said = self.offer(self.spec())
        show.assert_called_once_with(9, "undo")
        self.assertIn("notification", said)


if __name__ == "__main__":
    unittest.main()
