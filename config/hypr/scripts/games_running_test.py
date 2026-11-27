#!/usr/bin/env python3
"""Running games and their windows (#3632): `python3 config/hypr/scripts/games_running_test.py`. A window is found by
its class whole (spaces and all) or by the launch's environment up its process tree; another game's isn't taken."""

import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import games_running as gr  # noqa: E402


def write(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(data.encode() if isinstance(data, str) else data)


class Running(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.proc = os.path.join(self.tmp.name, "proc")
        self.cold = os.path.join(self.tmp.name, "cold-start-74.desktop")
        write(self.cold, "[Desktop Entry]\nType=Application\nName=Cold Start '74\nExec=/opt/cs/play\n"
                         "Categories=Game;\nStartupWMClass=Cold Start '74\n")
        self.godot = os.path.join(self.tmp.name, "godot-game.desktop")
        write(self.godot, "[Desktop Entry]\nType=Application\nName=Night Run\nExec=/opt/nr/play\nCategories=Game;\n")

    def tearDown(self):
        self.tmp.cleanup()

    def process(self, pid, ppid, env=None, comm="game"):
        # The command name holds a space and a bracket, as stat's parsing must survive
        write(f"{self.proc}/{pid}/stat", f"{pid} ({comm} ) x) S {ppid} 1 1 0")
        write(f"{self.proc}/{pid}/environ", b"\0".join(f"{k}={v}".encode() for k, v in (env or {}).items()) + b"\0")

    def game(self, gid, path=""):
        return {"id": gid, "source": gid.split(":")[0], "path": path, "name": gid}

    def test_class_with_spaces_whole(self):
        clients = [{"address": "0xa", "class": "kitty", "pid": 0},
                   {"address": "0xb", "class": "Cold Start '74", "pid": 0, "focusHistoryID": 3}]
        self.assertEqual(gr.window_of(self.game("desktop:cold-start-74", self.cold), clients, self.proc)["address"], "0xb")
        # A word of it is not the class
        self.assertIsNone(gr.window_of(self.game("desktop:cold-start-74", self.cold),
                                       [{"address": "0xc", "class": "Cold", "pid": 0}], self.proc))

    def test_launch_environment_from_a_parent(self):
        # gio launch → play script → the game, whose window says only "Godot"
        self.process(100, 1, {"GIO_LAUNCHED_DESKTOP_FILE": self.godot})
        self.process(101, 100, {"GIO_LAUNCHED_DESKTOP_FILE": "x"}, comm="godot")   # its own env changed: parent's counts
        self.process(102, 101, {}, comm="godot")
        clients = [{"address": "0xd", "class": "Godot", "pid": 102}]
        game = self.game("desktop:godot-game", self.godot)
        self.assertEqual(gr.window_of(game, clients, self.proc)["address"], "0xd")
        self.assertIsNone(gr.window_of(self.game("desktop:cold-start-74", self.cold), clients, self.proc))

    def test_steam_by_class_and_by_appid(self):
        self.assertEqual(gr.window_of(self.game("steam:1566200"),
                                      [{"address": "0xe", "class": "steam_app_1566200", "pid": 0}], self.proc)["address"],
                         "0xe")
        self.process(200, 1, {"SteamAppId": "1649950"})
        self.process(201, 200)
        clients = [{"address": "0xf", "class": "NewsTower.x86_64", "pid": 201}]
        self.assertEqual(gr.window_of(self.game("steam:1649950"), clients, self.proc)["address"], "0xf")
        self.assertIsNone(gr.window_of(self.game("steam:1566200"), clients, self.proc))

    def test_most_recent_window_first(self):
        clients = [{"address": "0x1", "class": "steam_app_5", "focusHistoryID": 4},
                   {"address": "0x2", "class": "steam_app_5", "focusHistoryID": 1}]
        self.assertEqual(gr.window_of(self.game("steam:5"), clients, self.proc)["address"], "0x2")

    def test_mark_running(self):
        games = [self.game("steam:5"), self.game("desktop:cold-start-74", self.cold)]
        gr.mark_running(games, [{"address": "0x1", "class": "steam_app_5"}], self.proc)
        self.assertEqual([g["running"] for g in games], [True, False])
        # No windows (no Hyprland): nothing runs
        self.assertFalse(gr.mark_running([self.game("steam:5")], [], self.proc)[0]["running"])

    def test_gone_process(self):
        self.assertEqual(gr.lineage(999, self.proc), [{}])   # its own, unreadable: no parents after it
        self.assertEqual(gr.parent(999, self.proc), 0)


if __name__ == "__main__":
    unittest.main()
