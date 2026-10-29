#!/usr/bin/env python3
"""Undo that keeps to what the user allows (#1860): `python3 config/mcp/undo_test.py`. An undo that does what an act
tool does asks on the card, from Claude and from the notification; an undo that refuses can be tried again; open's
undo closes only the window it opened and not while the user types; Deck's unqueue takes off only what Claude queued;
Tasks' restore doesn't write over an edit made since. A log written by something else runs nothing its tool wouldn't,
undo_change without an id takes only its own server's change, and a deletion's Undo isn't pushed out of the log while
it is on screen (#1881). Nothing here runs a real command or shows a card: the log is a file of its own, and the card,
the commands and the desktop are stand-ins."""

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

import changes  # noqa: E402
import confirm  # noqa: E402
import registry  # noqa: E402
import run  # noqa: E402
import undo  # noqa: E402
from run import ToolError  # noqa: E402


def load(name, path):
    loader = SourceFileLoader(name, str(path))
    module = module_from_spec(spec_from_loader(name, loader))
    loader.exec_module(module)
    return module


class Matching(unittest.TestCase):
    def test_same_command(self):
        on = ["nightdrive", "notifications", "dnd", "on", "--json"]
        self.assertTrue(undo.same_command(on, ["nightdrive", "notifications", "dnd", "on"]))
        self.assertFalse(undo.same_command(on, ["nightdrive", "notifications", "dnd", "off"]))
        self.assertFalse(undo.same_command(on, ["nightdrive", "notifications", "dnd", "on", "now"]))
        send = ["ferry", "text", "--to", "{to}", "{text}"]
        self.assertTrue(undo.same_command(send, ["ferry", "text", "--to", "phone", "hi"]))
        self.assertFalse(undo.same_command(send, ["ferry", "list", "--to", "phone", "hi"]))
        grouped = ["x", ["--limit", "{n}"], "--opt={v}", "{paths}"]
        self.assertTrue(undo.same_command(grouped, ["x", "--opt=1", "a", "b"]))
        self.assertTrue(undo.same_command(grouped, ["x", "--limit", "5", "--opt=", "a"]))
        self.assertFalse(undo.same_command(grouped, ["x", "--other=1", "a"]))

    def test_only_dnd_off_acts(self):
        """Of the tools as shipped, only dnd_off's undo turning Do Not Disturb on is an act tool's command."""
        tools, _ = registry.Registry(active="/nonexistent").load()
        for t in tools.values():
            if t.cls != "change":
                continue
            argv = run.expand(t.spec["undo"], {p: "on" for p in run.placeholders(t.spec["undo"])})
            act = undo.acts_like({"tool": t.name, "dir": str(t.dir)}, argv)
            self.assertEqual(getattr(act, "name", act), "notifications_dnd_on" if t.name == "notifications_dnd_off"
                             else None, t.name)


class Log(unittest.TestCase):
    """A log of its own, the card and the commands as stand-ins"""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        patches = [mock.patch.object(changes, "FILE", Path(self.tmp.name) / "claude-changes.jsonl"),
                   mock.patch.object(confirm, "ask", side_effect=self.card),
                   mock.patch.object(run, "execute", side_effect=self.execute),
                   mock.patch.object(undo, "notify", side_effect=self.notify)]
        for p in patches:
            p.start()
            self.addCleanup(p.stop)
        self.cards, self.ran, self.rows, self.wheres = [], [], [], []
        self.answer, self.status, self.pressed = True, [0], []

    def tearDown(self):
        self.tmp.cleanup()

    def card(self, tool, arguments):
        self.cards.append((tool.spec["title"], arguments))
        return self.answer() if callable(self.answer) else self.answer

    def execute(self, where, argv, stdin, timeout):
        self.ran.append(argv)
        self.wheres.append((where, timeout))
        return "", "refused for now", self.status.pop(0) if len(self.status) > 1 else self.status[0]

    def notify(self, entry_id, summary, body="", button=None):
        self.rows.append((summary, button))
        return self.pressed.pop(0) if self.pressed else None

    def entry(self, tool, undo_argv, notice="A change", do=("true",), **more):
        # This test's own server, as undo_change's parent is the server that logged the change
        return changes.add({"tool": tool, "notice": notice, "arguments": {}, "before": {}, "do": list(do),
                            "stdin": None, "undo": undo_argv, "remake": undo_argv, "dir": str(HERE),
                            "timeout": 5, "area": "notifications", "options_from": [],
                            "server": undo.server_id(os.getppid()), **more})

    def dnd(self):
        return self.entry("notifications_dnd_off", ["nightdrive", "notifications", "dnd", "on"],
                          "Turned Do Not Disturb off", do=["nightdrive", "notifications", "dnd", "off", "--json"])

    def test_denied_on_the_card(self):
        e = self.dnd()
        self.answer = False
        with self.assertRaises(ToolError) as said:
            undo.undo_change({"id": e["id"]})
        self.assertIn("didn't allow", str(said.exception))
        self.assertEqual(self.ran, [])
        self.assertEqual(changes.get(e["id"])["state"], "done")
        title, args = self.cards[0]
        self.assertEqual(title, "Undo: Turned Do Not Disturb off")
        self.assertEqual(args, {"does": "Turn Do Not Disturb on"})

    def test_allowed_on_the_card(self):
        e = self.dnd()
        undo.undo_change({})
        self.assertEqual(self.ran, [["nightdrive", "notifications", "dnd", "on"]])
        self.assertEqual(changes.get(e["id"])["state"], "undone")

    def test_from_the_notification_too(self):
        e = self.dnd()
        self.answer, self.pressed = False, ["undo", None]
        undo.notice(e["id"], "undo")
        self.assertEqual(len(self.cards), 1)
        self.assertEqual(self.ran, [])

    def test_changed_while_the_card_was_up(self):
        e = self.dnd()

        def meanwhile():
            with changes.editing() as entries:
                entries[-1]["undo"] = ["nightdrive", "notifications", "dnd", "on", "--other"]
            return True
        self.answer = meanwhile
        with self.assertRaises(ToolError):
            undo.perform(e["id"], "undo")
        self.assertEqual(self.ran, [])

    def test_undone_while_the_card_was_up(self):
        e = self.dnd()

        def meanwhile():
            changes.mark(e["id"], "undone")
            return True
        self.answer = meanwhile
        with self.assertRaises(ToolError):
            undo.perform(e["id"], "undo")
        self.assertEqual(self.ran, [])

    def test_a_plain_undo_asks_nothing(self):
        e = self.entry("appearance_wallpaper", ["nightdrive", "wallpaper", "set", "/x.png"])
        undo.perform(e["id"], "undo")
        self.assertEqual(self.cards, [])
        self.assertEqual(len(self.ran), 1)

    def test_a_redo_asks_nothing(self):
        e = self.dnd()
        undo.perform(e["id"], "undo")
        undo.perform(e["id"], "redo")
        self.assertEqual(len(self.cards), 1)

    def test_undo_asks(self):
        e = self.entry("x_set", ["x", "set", "1"])
        fake = SimpleNamespace(cls="change", spec={"undo_asks": True, "command": ["x"], "undo": ["x", "set", "{n}"]},
                               name="x_set", dir=HERE, area="notifications")
        with mock.patch.object(registry.Registry, "load", return_value=({"x_set": fake}, [])):
            undo.perform(e["id"], "undo")
        self.assertEqual(self.cards[0][1], {"does": "x set 1"})

    def test_tools_unreadable_asks(self):
        e = self.entry("x_set", ["x", "set", "1"])
        with mock.patch.object(registry.Registry, "load", side_effect=OSError("gone")):
            self.answer = False
            with self.assertRaises(ToolError):
                undo.perform(e["id"], "undo")
        self.assertEqual(self.ran, [])

    def test_try_again(self):
        """An undo that refused (the user typing) offers Try again, which runs it again"""
        e = self.entry("windows_focus", ["nightdrive", "windows", "focus", "0x1", "--unless-typing"])
        self.status = [1, 0]
        self.pressed = ["undo", "undo", None]
        undo.notice(e["id"], "undo")
        self.assertEqual(len(self.ran), 2)
        self.assertEqual(self.rows[1][1], ("undo", "Try again"))
        self.assertEqual(changes.get(e["id"])["state"], "undone")

    def test_try_again_not_pressed(self):
        e = self.entry("windows_focus", ["nightdrive", "windows", "focus", "0x1", "--unless-typing"])
        self.status, self.pressed = [1], ["undo", None]
        undo.notice(e["id"], "undo")
        self.assertEqual(len(self.ran), 1)
        self.assertEqual(changes.get(e["id"])["state"], "done")


class Forged(Log):
    """A log written by something other than the server (#1881): Undo and Redo run only what its tool would"""

    WALL = ["nightdrive", "wallpaper", "set", "/x.png"]

    def refused(self, e, action="undo"):
        with self.assertRaises(ToolError) as said:
            undo.perform(e["id"], action)
        self.assertEqual(self.ran, [])
        self.assertEqual(changes.get(e["id"])["state"], "done" if action == "undo" else "undone")
        return str(said.exception)

    def test_a_command_its_tool_has_not(self):
        for argv in (["bash", "-c", "touch /tmp/owned"], ["nightdrive", "update"], ["nightdrive", "wallpaper"],
                     self.WALL + ["--more"], ["nightdrive", "wallpaper", "set", "--evil"],
                     ["nightdrive", "wallpaper", "set", "/x.png", "/y.png"][:3] + ["-x", "/y.png"]):
            with self.subTest(argv=argv):
                self.assertIn("isn't one appearance_wallpaper would run",
                              self.refused(self.entry("appearance_wallpaper", argv)))

    def test_a_tool_that_is_not_there_or_not_a_change(self):
        for name in ("evil_tool", "notifications_dnd_on", "undo_change", "recent_changes"):
            with self.subTest(name=name):
                self.assertIn("isn't a change tool", self.refused(self.entry(name, self.WALL)))

    def test_folder_and_timeout_are_the_tools_own(self):
        e = self.entry("appearance_wallpaper", self.WALL, dir="/tmp/evil", timeout=100000)
        undo.perform(e["id"], "undo")
        where, timeout = self.wheres[0]
        self.assertEqual(where.dir, HERE)
        self.assertEqual(timeout, run.TIMEOUT)

    def test_an_empty_list_at_the_end(self):
        undo.perform(self.entry("deck_queue_song", ["python3", "lib/playback.py", "unqueue", "0"])["id"], "undo")
        self.assertEqual(len(self.ran), 1)

    def test_an_option_only_after_dashes(self):
        undo.perform(self.entry("files_trash", ["nightdrive", "files", "restore", "--", "-odd name", "x"])["id"], "undo")
        self.assertEqual(len(self.ran), 1)

    def test_redo_runs_the_tools_command_with_its_arguments(self):
        e = self.dnd()
        changes.mark(e["id"], "undone", do=["bash", "-c", "true"])
        self.assertIn("isn't one notifications_dnd_off would run", self.refused(e, "redo"))
        e = self.entry("appearance_wallpaper", self.WALL, do=["nightdrive", "wallpaper", "set", "/y.png", "--json"],
                       arguments={"path": "/y.png", "extra": 1})
        changes.mark(e["id"], "undone")
        self.refused(e, "redo")    # an argument its schema doesn't take
        e = self.entry("appearance_wallpaper", self.WALL, do=["nightdrive", "wallpaper", "set", "/y.png", "--json"],
                       arguments={"path": "/y.png"})
        changes.mark(e["id"], "undone")
        undo.perform(e["id"], "redo")
        self.assertEqual(self.ran, [["nightdrive", "wallpaper", "set", "/y.png", "--json"]])

    def test_a_redos_undo_is_built_by_the_tools_template(self):
        e = self.entry("appearance_wallpaper", self.WALL, do=["nightdrive", "wallpaper", "set", "/y.png", "--json"],
                       arguments={"path": "/y.png"}, before={"path": "/old.png"}, remake=["bash", "-c", "{path}"])
        changes.mark(e["id"], "undone")
        undo.perform(e["id"], "redo")
        self.assertEqual(changes.get(e["id"])["undo"], ["nightdrive", "wallpaper", "set", "/old.png"])


class Newest(Log):
    """undo_change without an id: only this server's own newest change (#1881)"""

    def test_another_servers_newest_needs_its_id(self):
        mine = self.entry("appearance_wallpaper", Forged.WALL)
        other = self.entry("appearance_wallpaper", Forged.WALL, server="1:1")
        with self.assertRaises(ToolError) as said:
            undo.undo_change({})
        self.assertIn(f"{other['id']}, wasn't made in this conversation", str(said.exception))
        self.assertNotIn("A change", str(said.exception))
        self.assertEqual(self.ran, [])
        undo.undo_change({"id": other["id"]})
        undo.undo_change({})     # now its own is the newest in place
        self.assertEqual(changes.get(mine["id"])["state"], "undone")

    def test_an_entry_without_a_server(self):
        e = self.entry("appearance_wallpaper", Forged.WALL)
        changes.mark(e["id"], "done", server=None)
        with self.assertRaises(ToolError):
            undo.undo_change({})

    def test_server_id(self):
        self.assertEqual(undo.server_id(os.getpid()), undo.server_id(os.getpid()))
        self.assertTrue(undo.server_id(os.getpid()).startswith(f"{os.getpid()}:"))
        self.assertIsNone(undo.server_id(2 ** 31))


class Calendar(unittest.TestCase):
    def test_an_added_events_undo_asks(self):
        """calendar_add's undo deletes the event, as calendar_delete does (its --check only checks the card)"""
        tools = {t.name: t for t in registry.read_file(REPO / "plugins/calendar/mcp.json", REPO / "plugins/calendar",
                                                        "calendar")[0]}
        argv = run.expand(tools["calendar_add"].spec["undo"], {"calendar": "home", "uid": "abc"})
        with mock.patch.object(registry.Registry, "load", return_value=(tools, [])):
            self.assertEqual(undo.acts_like({"tool": "calendar_add"}, argv).name, "calendar_delete")


class Kept(unittest.TestCase):
    """A deletion's Undo stays in the log while its notification offers it (#1881)"""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        p = mock.patch.object(changes, "FILE", Path(self.tmp.name) / "claude-changes.jsonl")
        p.start()
        self.addCleanup(p.stop)

    def test_a_flood_does_not_push_it_out(self):
        trashed = changes.add({"tool": "files_trash", "notice": "Trashed", "deletes": True})
        undone = changes.add({"tool": "files_trash", "notice": "Trashed, undone", "deletes": True})
        changes.mark(undone["id"], "undone")
        old = changes.add({"tool": "files_trash", "notice": "Trashed long ago", "deletes": True})
        changes.mark(old["id"], "done", time="2020-01-01T00:00:00+0000")
        for _ in range(changes.KEEP + 20):
            changes.add({"tool": "notes_create", "notice": "A note"})
        ids = [e["id"] for e in changes.read()]
        self.assertIn(trashed["id"], ids)
        self.assertNotIn(undone["id"], ids)
        self.assertNotIn(old["id"], ids)
        self.assertEqual(len(ids), changes.KEEP + 1)

    def test_held_ones_have_a_limit(self):
        with mock.patch.object(changes, "HOLD_MAX", 3), mock.patch.object(changes, "KEEP", 5):
            for _ in range(20):
                changes.add({"tool": "files_trash", "notice": "Trashed", "deletes": True})
            self.assertEqual(len(changes.read()), 8)


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
        with mock.patch.object(self.w, "key_age", return_value=0), \
                mock.patch.object(self.w, "clients", return_value=[self.window("0x2", "x"), self.window("0x1", "y")]), \
                mock.patch.object(self.w, "dispatch") as dispatch, mock.patch("sys.stderr"):
            with self.assertRaises(SystemExit):
                self.w.cmd_close(a)
            dispatch.assert_not_called()
        with mock.patch.object(self.w, "key_age", return_value=9), \
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


class Notice(unittest.TestCase):
    """The notification names what changed in words: a draft's recipients, not a JSON list of them (#1878)."""

    def test_lists_of_texts(self):
        tool = SimpleNamespace(name="mail_draft", spec={"notice": "Wrote a draft in Mail to {to}: {subject}"})
        text = undo.notice_text(tool, {"to": ["Attacker <x@evil.example>", "b@c.d"], "subject": "Re: Reset"})
        self.assertEqual(text, "Wrote a draft in Mail to Attacker <x@evil.example>, b@c.d: Re: Reset")
        self.assertEqual(undo.notice_text(tool, {"to": [1, 2], "subject": "S"}), "Wrote a draft in Mail to [1, 2]: S")


if __name__ == "__main__":
    unittest.main()
