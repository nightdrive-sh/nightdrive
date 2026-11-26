#!/usr/bin/env python3
"""Undo that keeps to what the user allows (#1860): `python3 config/mcp/undo_test.py`. An undo that does what an act
tool does asks on the card, from Claude and from the notification; an undo that refuses can be tried again. A log
written by something else runs nothing its tool wouldn't, undo_change without an id takes only its own server's change,
and a deletion's Undo isn't pushed out of the log while it is on screen (#1881). undo_change keeps to the area's Access
as it is now, and a redo asks again when its asks_if says so (#1924), as does Claude's undo that is the tool's own
command (#1945). Nothing here runs a real command or shows a card: the log is a file of its own, and the card, the
commands and the desktop are stand-ins. The tools' own undos (a window, Deck's queue, Tasks) are undo_tools_test.py's."""

import json
import os
import sys
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest import mock

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
sys.dont_write_bytecode = True

import changes  # noqa: E402
import confirm  # noqa: E402
import registry  # noqa: E402
import run  # noqa: E402
import undo  # noqa: E402
from run import ToolError  # noqa: E402


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

    def test_as_call(self):
        """An undo read as its tool's own call (#1945): the values that give its argv word for word, or None"""
        out = ["nightdrive", "sound", "output", "{output}"]
        self.assertEqual(undo.as_call(out, ["nightdrive", "sound", "output", "AirPlay"]), {"output": "AirPlay"})
        self.assertIsNone(undo.as_call(out, ["nightdrive", "sound", "output", "a", "b"]))
        light = ["home-assistant", "brightness", "{entity}", "{brightness}"]
        self.assertEqual(undo.as_call(light, ["home-assistant", "brightness", "light.desk", "40"]),
                         {"entity": "light.desk", "brightness": "40"})
        volume = ["nightdrive", "sound", "volume", ["{volume}"], ["--mute", "{mute}"]]
        self.assertEqual(undo.as_call(volume, ["nightdrive", "sound", "volume", "40", "--mute", "false"]),
                         {"volume": "40", "mute": "false"})
        self.assertEqual(undo.as_call(["x", "--to={dest}.txt"], ["x", "--to=a=b.txt"]), {"dest": "a=b"})
        self.assertIsNone(undo.as_call(["x", "{a}", "{a}"], ["x", "1", "2"]))   # one name, one value
        # calendar_add's undo deletes: not its call (calendar_delete's card asks for that one)
        self.assertIsNone(undo.as_call(["calendar", "add", "--json"], ["calendar", "delete", "Family", "uid-1"]))

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
                   mock.patch.object(undo, "notify", side_effect=self.notify),
                   # Access as Normal has it, not the user's own file: each test sets what it needs in own
                   mock.patch.object(undo.access, "load", side_effect=lambda *a: self.rules)]
        for p in patches:
            p.start()
            self.addCleanup(p.stop)
        self.cards, self.ran, self.rows, self.wheres = [], [], [], []
        self.answer, self.status, self.pressed = True, [0], []
        self.rules = undo.access.Access("normal")

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

    def setUp(self):
        super().setUp()
        # Deck installed and on, as the tests of its queue need, from a list of its own: not the machine's
        # ~/.local/state list, which CI and a fresh home don't have
        active = Path(self.tmp.name) / "active"
        active.write_text(f"deck\t{HERE.parents[1] / 'plugins/deck'}\n")

        class Installed(registry.Registry):
            def __init__(self, *a, active=str(active), **kw):
                super().__init__(*a, active=active, **kw)

        p = mock.patch.object(registry, "Registry", Installed)
        p.start()
        self.addCleanup(p.stop)

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


class Gated(Log):
    """Claude's undo keeps to Access as the tool's own call would now, and a redo asks again when its call would have
    (#1924). The notification's buttons are the user's: Access doesn't stop them."""

    SPEAKER = ["nightdrive", "sound", "output", "AirPlay"]

    def setUp(self):
        super().setUp()
        self.remote, self.asked = "no", []

    def execute(self, where, argv, stdin, timeout):
        if argv[:3] == ["nightdrive", "sound", "remote"]:   # sound_output's asks_if
            self.asked.append(argv)
            return self.remote + "\n", "", 0
        return super().execute(where, argv, stdin, timeout)

    def wall(self):
        # The log's area isn't the one that counts: the tool's own is (a log can be written by anything, #1881)
        return self.entry("appearance_wallpaper", Forged.WALL, area="notifications")

    def speaker(self):
        e = self.entry("sound_output", ["nightdrive", "sound", "output", "Speakers"], "Switched the sound to AirPlay",
                       do=self.SPEAKER, arguments={"output": "AirPlay"}, area="sound-display")
        changes.mark(e["id"], "undone")
        return e

    def test_modify_no_refuses_claude(self):
        e = self.wall()
        self.rules.own = {"appearance": {"modify": "no"}}
        with self.assertRaises(ToolError) as said:
            undo.undo_change({"id": e["id"]})
        self.assertIn("Modify: No", str(said.exception))
        self.assertNotIn("A change", str(said.exception))   # what it was is the area's
        self.assertEqual((self.ran, self.cards), ([], []))
        self.assertEqual(changes.get(e["id"])["state"], "done")
        self.pressed = ["undo", None]      # the user's own Undo still works
        undo.notice(e["id"], "undo")
        self.assertEqual(self.ran, [Forged.WALL])
        self.assertEqual(changes.get(e["id"])["state"], "undone")

    def test_modify_ask_shows_the_card(self):
        e = self.wall()
        self.rules.own = {"appearance": {"modify": "ask"}}
        self.answer = False
        with self.assertRaises(ToolError) as said:
            undo.undo_change({"id": e["id"]})
        self.assertIn("didn't allow", str(said.exception))
        self.assertEqual(self.ran, [])
        self.assertEqual(self.cards, [("Undo: A change", {"does": "nightdrive wallpaper set /x.png"})])
        self.answer = True
        undo.undo_change({"id": e["id"]})
        self.assertEqual(self.ran, [Forged.WALL])

    def test_ask_and_an_act_are_one_card(self):
        e = self.dnd()
        self.rules.own = {"notifications": {"modify": "ask"}}
        undo.undo_change({"id": e["id"]})
        self.assertEqual(self.cards, [("Undo: Turned Do Not Disturb off", {"does": "Turn Do Not Disturb on"})])

    def test_a_deletions_undo_is_a_change(self):
        """Putting back what was trashed deletes nothing: Delete No doesn't stop it, Modify No does"""
        e = self.entry("files_trash", ["nightdrive", "files", "restore", "--", "x"])
        self.rules.own = {"apps-files": {"delete": "no"}}
        undo.undo_change({"id": e["id"]})
        self.assertEqual((len(self.ran), self.cards), (1, []))
        e = self.entry("files_trash", ["nightdrive", "files", "restore", "--", "y"])
        self.rules.own = {"apps-files": {"modify": "no"}}
        with self.assertRaises(ToolError):
            undo.undo_change({"id": e["id"]})
        self.assertEqual(len(self.ran), 1)

    def test_access_unreadable_refuses(self):
        e = self.wall()
        with mock.patch.object(undo.access, "load", side_effect=ValueError("broken")):
            with self.assertRaises(ToolError):
                undo.undo_change({"id": e["id"]})
        self.assertEqual(self.ran, [])

    def test_a_redo_asks_when_its_call_would(self):
        e = self.speaker()
        undo.perform(e["id"], "redo")       # asks_if says no: no card, as the call had none
        self.assertEqual((self.asked, self.cards), ([["nightdrive", "sound", "remote", "AirPlay"]], []))
        self.assertEqual(self.ran, [self.SPEAKER])
        changes.mark(e["id"], "undone")
        self.ran, self.remote, self.answer = [], "yes", False
        with self.assertRaises(ToolError) as said:
            undo.perform(e["id"], "redo")
        self.assertIn("didn't allow redoing", str(said.exception))
        self.assertEqual(self.cards, [("Switch the sound output", {"output": "AirPlay"})])
        self.assertEqual(self.ran, [])
        self.pressed = ["redo", None]       # the notification's Redo asks too, and offers Try again
        undo.notice(e["id"], "redo")
        self.assertEqual((len(self.cards), self.ran), (2, []))
        self.assertEqual(self.rows[-1][1], ("redo", "Try again"))
        self.answer = True
        undo.perform(e["id"], "redo")
        self.assertEqual(self.ran, [self.SPEAKER])
        self.assertEqual(changes.get(e["id"])["state"], "done")

    def test_claudes_undo_asks_when_its_call_would(self):
        """An undo that puts the sound back on a speaker on the network is that call: Claude's asks as it would
        (#1945), the notification's Undo is the user's and doesn't"""
        e = self.entry("sound_output", self.SPEAKER, "Switched the sound to Speakers", area="sound-display",
                       do=["nightdrive", "sound", "output", "Speakers"], arguments={"output": "Speakers"})
        self.remote, self.answer = "yes", False
        with self.assertRaises(ToolError) as said:
            undo.undo_change({"id": e["id"]})
        self.assertIn("didn't allow undoing", str(said.exception))
        self.assertIn("wasn't undone", str(said.exception))
        self.assertEqual(self.asked, [["nightdrive", "sound", "remote", "AirPlay"]])
        self.assertEqual((self.cards, self.ran), ([("Switch the sound output", {"output": "AirPlay"})], []))
        self.answer = True
        undo.undo_change({"id": e["id"]})
        self.assertEqual((len(self.cards), self.ran), (2, [self.SPEAKER]))
        changes.mark(e["id"], "done")
        self.ran, self.asked, self.pressed = [], [], ["undo", None]
        undo.notice(e["id"], "undo")
        self.assertEqual((len(self.cards), self.asked, self.ran), (2, [], [self.SPEAKER]))

    def test_claudes_undo_asks_nothing_when_its_call_wouldnt(self):
        e = self.entry("sound_output", ["nightdrive", "sound", "output", "Speakers"], area="sound-display",
                       do=self.SPEAKER, arguments={"output": "AirPlay"})
        undo.undo_change({"id": e["id"]})
        self.assertEqual(self.asked, [["nightdrive", "sound", "remote", "Speakers"]])
        self.assertEqual((self.cards, len(self.ran)), ([], 1))

    def test_an_undo_asks_if_cant_read_shows_the_card(self):
        """A tool with asks_if whose undo isn't its command: asks_if can't speak for it, so the undo's card asks"""
        e = self.entry("sound_output", self.SPEAKER, area="sound-display")
        with mock.patch.object(undo, "as_call", return_value=None):
            undo.undo_change({"id": e["id"]})
        self.assertEqual(self.asked, [])
        self.assertEqual(self.cards, [("Undo: A change", {"does": " ".join(self.SPEAKER)})])
        self.assertEqual(self.ran, [self.SPEAKER])

    def test_claudes_redo_keeps_to_access(self):
        e = self.speaker()
        self.rules.own = {"sound-display": {"modify": "no"}}
        with self.assertRaises(ToolError):
            undo.perform(e["id"], "redo", claude=True)
        self.assertEqual((self.ran, self.asked), ([], []))
        self.rules.own = {"sound-display": {"modify": "ask"}}
        undo.perform(e["id"], "redo", claude=True)   # Ask: the card, without asking asks_if first
        self.assertEqual((len(self.cards), self.asked, self.ran), (1, [], [self.SPEAKER]))


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


class Notice(unittest.TestCase):
    """The notification names what changed in words: a draft's recipients, not a JSON list of them (#1878)."""

    def test_lists_of_texts(self):
        tool = SimpleNamespace(name="mail_draft", spec={"notice": "Wrote a draft in Mail to {to}: {subject}"})
        text = undo.notice_text(tool, {"to": ["Attacker <x@evil.example>", "b@c.d"], "subject": "Re: Reset"})
        self.assertEqual(text, "Wrote a draft in Mail to Attacker <x@evil.example>, b@c.d: Re: Reset")
        self.assertEqual(undo.notice_text(tool, {"to": [1, 2], "subject": "S"}), "Wrote a draft in Mail to [1, 2]: S")


class Recent(unittest.TestCase):
    """recent_changes gives what changes were made with only for an area Claude may read now (#1884): mail set to No
    after a draft doesn't hand the draft's text back through the Nightdrive row, which is read even on Strict."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        p = mock.patch.object(changes, "FILE", Path(self.tmp.name) / "claude-changes.jsonl")
        p.start()
        self.addCleanup(p.stop)
        for tool, area, args, notice in (
                ("mail_draft", "mail", {"to": ["a@b.c"], "body": "Door code: 4829, card 4242 4242 4242 4242"},
                 "Wrote a draft in Mail to a@b.c: Code 482913"),
                ("tasks_add", "tasks", {"title": "PIN 4829", "note": "Password: Tr0ub4dor&3"}, "Added the task PIN 4829"),
                ("appearance_theme", "appearance", {"theme": "nord"}, "Changed the theme to nord"),
                ("old_tool", None, {"text": "secret plans"}, "Something")):
            changes.add({"tool": tool, "notice": notice, "arguments": args, "before": {}, "do": ["true"],
                         "stdin": None, "undo": ["true"], "remake": ["true"], "dir": str(HERE), "timeout": 5,
                         **({"area": area} if area else {}), "options_from": []})

    def rows(self, own=None, options=None):
        rules = undo.access.Access("normal", own=own or {}, own_options=options or {})
        with mock.patch.object(undo.access, "load", lambda: rules):
            return {r["tool"]: r for r in undo.recent_changes({"limit": 10})["changes"]}

    def test_read_no_or_ask(self):
        for value in ("no", "ask"):
            rows = self.rows(own={"mail": {"read": value}})
            self.assertNotIn("arguments", rows["mail_draft"])
            self.assertNotIn("482913", json.dumps(rows["mail_draft"]))
            self.assertEqual(rows["mail_draft"]["notice"], "A change made with mail_draft")
            self.assertEqual(rows["appearance_theme"]["arguments"], {"theme": "nord"})

    def test_masked_as_the_area_reads(self):
        rows = self.rows(own={"mail": {"read": "allow"}})
        self.assertEqual(rows["mail_draft"]["arguments"]["body"], "Door code: [code hidden], card •••• 4242")
        self.assertEqual(rows["mail_draft"]["notice"], "Wrote a draft in Mail to a@b.c: Code [code hidden]")
        self.assertEqual(rows["tasks_add"]["arguments"], {"title": "PIN [code hidden]", "note": "Password: [password hidden]"})
        rows = self.rows(own={"mail": {"read": "allow"}}, options={"mail": {"secrets": True}})
        self.assertIn("4829", rows["mail_draft"]["arguments"]["body"])

    def test_no_area_or_no_access(self):
        self.assertNotIn("arguments", self.rows()["old_tool"])
        with mock.patch.object(undo.access, "load", side_effect=ValueError("broken")):
            rows = undo.recent_changes({})["changes"]
        self.assertTrue(all("arguments" not in r for r in rows))


if __name__ == "__main__":
    unittest.main()
