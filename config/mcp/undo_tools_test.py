#!/usr/bin/env python3
"""The undos of particular tools (#1860): `python3 config/mcp/undo_tools_test.py`. calendar_add's undo asks on the card
as calendar_delete does; open's undo closes only the window it opened and not while the user types; Deck's unqueue
takes off only what Claude queued; Tasks' restore doesn't write over an edit made since. How Undo itself runs, asks
and keeps to Access is undo_test.py's."""

import json
import os
import subprocess
import sys
import tempfile
import unittest
from importlib.machinery import SourceFileLoader
from importlib.util import module_from_spec, spec_from_loader
from pathlib import Path
from types import SimpleNamespace
from unittest import mock

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
sys.path.insert(0, str(HERE))
sys.dont_write_bytecode = True

import registry  # noqa: E402
import run  # noqa: E402
import undo  # noqa: E402


def load(name, path):
    loader = SourceFileLoader(name, str(path))
    module = module_from_spec(spec_from_loader(name, loader))
    loader.exec_module(module)
    return module


class Calendar(unittest.TestCase):
    def test_an_added_events_undo_asks(self):
        """calendar_add's undo deletes the event, as calendar_delete does (its --check only checks the card)"""
        tools = {t.name: t for t in registry.read_file(REPO / "plugins/calendar/mcp.json", REPO / "plugins/calendar",
                                                        "calendar")[0]}
        argv = run.expand(tools["calendar_add"].spec["undo"], {"calendar": "home", "uid": "abc"})
        with mock.patch.object(registry.Registry, "load", return_value=(tools, [])):
            self.assertEqual(undo.acts_like({"tool": "calendar_add"}, argv).name, "calendar_delete")


class Windows(unittest.TestCase):
    def setUp(self):
        self.w = load("windows_under_test", HERE.parent / "hypr/scripts/windows")
        self.w.WAIT, self.w.POLL, self.w.QUIET_WAIT = 0.3, 0.01, 0.05
        self.app = ("org.gnome.TextEditor", {"name": "Text Editor", "wmclass": "", "hidden": False})

    def window(self, address, cls):
        return {"address": address, "class": cls, "initialClass": cls, "title": "", "workspace": {"name": "1"}}

    def test_another_apps_window_isnt_new(self):
        mine = self.window("0x2", "org.gnome.TextEditor")
        later = [[self.window("0x9", "kitty")]] * 3 + [[self.window("0x9", "kitty"), mine]]
        with mock.patch.object(self.w, "clients", side_effect=later + [later[-1]] * 50):
            self.assertEqual(self.w.wait_new(set(), self.app), mine)
        with mock.patch.object(self.w, "clients", return_value=[self.window("0x9", "kitty")]):
            self.assertIsNone(self.w.wait_new(set(), self.app))

    def test_unknown_app_waits_for_nothing(self):
        with mock.patch.object(self.w, "clients", return_value=[self.window("0x9", "kitty")]) as clients:
            self.assertIsNone(self.w.wait_new(set(), None))
            clients.assert_not_called()

    def test_close_waits_while_typing(self):
        a = SimpleNamespace(address="0x2", focus="0x1", unless_typing=True)
        with mock.patch.object(self.w, "typing", return_value=True), \
                mock.patch.object(self.w, "clients", return_value=[self.window("0x2", "x"), self.window("0x1", "y")]), \
                mock.patch.object(self.w, "dispatch") as dispatch, mock.patch("sys.stderr"):
            with self.assertRaises(SystemExit):
                self.w.cmd_close(a)
            dispatch.assert_not_called()
        with mock.patch.object(self.w, "typing", return_value=False), \
                mock.patch.object(self.w, "clients", return_value=[self.window("0x2", "x"), self.window("0x1", "y")]), \
                mock.patch.object(self.w, "dispatch") as dispatch:
            self.w.cmd_close(a)
            self.assertEqual(dispatch.call_count, 2)

    def test_undo_templates_wait_while_typing(self):
        tools = {t.name: t for t in registry.read_file(HERE / "tools/apps-files.json", HERE, None)[0]}
        for name in ("windows_focus", "apps_open", "files_open"):
            self.assertIn("--unless-typing", tools[name].spec["undo"], name)


class Deck(unittest.TestCase):
    def setUp(self):
        self.p = load("playback_under_test", REPO / "plugins/deck/lib/playback.py")
        self.removed = []

    def unqueue(self, queue, length, queued):
        self.queue = list(queue)

        def ctl(*args):
            self.assertEqual(args[0], "unqueue")
            self.removed.append(self.queue.pop(int(args[1])))
        with mock.patch.object(self.p, "status", side_effect=lambda: {"queue": [{"uri": u} for u in self.queue]}), \
                mock.patch.object(self.p, "ctl", side_effect=ctl):
            return self.p.unqueue(str(length), *queued)

    def test_users_later_tracks_stay(self):
        self.unqueue(["u1", "c1", "c2", "u2"], 1, ["c1", "c2"])
        self.assertEqual(self.queue, ["u1", "u2"])

    def test_queue_played_on(self):
        self.unqueue(["c1", "c2", "u2"], 2, ["c1", "c2"])        # u0 and u1 have played
        self.assertEqual(self.queue, ["u2"])
        self.unqueue(["c2", "u2"], 1, ["c1", "c2"])              # c1 has played too
        self.assertEqual(self.queue, ["u2"])

    def test_the_same_album_queued_again_by_the_user(self):
        self.unqueue(["c1", "c2", "c1", "c2"], 0, ["c1", "c2"])
        self.assertEqual(self.removed, ["c1", "c2"])
        self.assertEqual(self.queue, ["c1", "c2"])

    def test_gone_takes_nothing(self):
        with self.assertRaises(self.p.Failed):
            self.unqueue(["u1", "u2"], 0, ["c1"])
        with self.assertRaises(self.p.Failed):
            self.unqueue(["u1"], 1, [])                           # an undo logged before the uris
        self.assertEqual(self.removed, [])


class Tasks(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        d = Path(self.tmp.name)
        self.env = {**os.environ, "NIGHTDRIVE_TASKS_DIR": str(d / "data"), "XDG_STATE_HOME": str(d / "state")}

    def tearDown(self):
        self.tmp.cleanup()

    def tasks(self, *argv):
        p = subprocess.run([sys.executable, str(REPO / "plugins/tasks/lib/cli.py"), *argv], capture_output=True,
                           text=True, env=self.env)
        return p.returncode, json.loads(p.stdout) if p.returncode == 0 and argv[0] != "restore" else p.stderr

    def file(self, task):
        return next(Path(self.env["NIGHTDRIVE_TASKS_DIR"]).rglob(f"*{task['id'][:8]}*.ics"))

    def test_an_edit_since_stays(self):
        _, task = self.tasks("add", "--json", "--", "Buy milk")
        _, done = self.tasks("done", "--json", "--", task["id"])
        f = self.file(task)
        f.write_text(f.read_text().replace("Buy milk", "Buy oat milk"))       # the user, an hour later
        status, said = self.tasks("restore", "--json", done["undo"])
        self.assertEqual(status, 1)
        self.assertIn("changed since", said)
        self.assertIn("Buy oat milk", f.read_text())

    def test_an_add_edited_since_isnt_removed(self):
        _, task = self.tasks("add", "--json", "--", "Call Anna")
        f = self.file(task)
        f.write_text(f.read_text().replace("Call Anna", "Call Anna at 5"))
        self.assertEqual(self.tasks("restore", "--json", task["undo"])[0], 1)
        self.assertTrue(f.exists())

    def test_a_trashed_task_made_again_stays(self):
        _, task = self.tasks("add", "--json", "--", "Plan")
        f = self.file(task)
        text = f.read_text()
        _, trashed = self.tasks("trash", "--json", "--", task["id"])
        f.write_text(text + "\n")                                             # back, as a sync brought it
        self.assertEqual(self.tasks("restore", "--json", trashed["undo"])[0], 1)

    def test_unchanged_undoes(self):
        _, task = self.tasks("add", "--json", "--", "Water plants")
        _, done = self.tasks("done", "--json", "--", task["id"])
        self.assertEqual(self.tasks("restore", "--json", done["undo"])[0], 0)
        self.assertNotIn("COMPLETED", self.file(task).read_text())
        self.assertEqual(self.tasks("restore", "--json", task["undo"])[0], 0)
        self.assertEqual(list(Path(self.env["NIGHTDRIVE_TASKS_DIR"]).rglob("*.ics")), [])


if __name__ == "__main__":
    unittest.main()
