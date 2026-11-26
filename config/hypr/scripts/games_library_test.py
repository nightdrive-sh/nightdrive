#!/usr/bin/env python3
"""The games list (#3530): `python3 config/hypr/scripts/games_library_test.py`. .desktop games without Steam and its
shortcuts, Steam's library without its tools, a download's progress, and a Steam game running under its reaper."""

import os
import sys
import tempfile
import unittest
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import games_library as gl  # noqa: E402


def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)


def desktop(name, exe, categories="Game;", extra=""):
    return f"[Desktop Entry]\nType=Application\nName={name}\nExec={exe}\nCategories={categories}\n{extra}"


def manifest(appid, name, flags, total=0, done=0):
    return (f'"AppState"\n{{\n\t"appid"\t\t"{appid}"\n\t"name"\t\t"{name}"\n\t"StateFlags"\t\t"{flags}"\n'
            f'\t"BytesToDownload"\t\t"{total}"\n\t"BytesDownloaded"\t\t"{done}"\n}}\n')


class Library(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.home = self.tmp.name
        apps = os.path.join(self.home, ".local/share/applications")
        write(f"{apps}/cold-start-74.desktop", desktop("Cold Start '74", "/opt/cs/play"))
        write(f"{apps}/steam.desktop", desktop("Steam", "/usr/bin/steam %U", "Network;FileTransfer;Game;"))
        write(f"{apps}/Tape to Tape.desktop", desktop("Tape to Tape", "steam steam://rungameid/1566200"))
        write(f"{apps}/editor.desktop", desktop("Editor", "gedit", "Utility;"))
        write(f"{apps}/hidden.desktop", desktop("Hidden Game", "hg", extra="NoDisplay=true\n"))
        sa = os.path.join(self.home, ".local/share/Steam/steamapps")
        other = os.path.join(self.home, "games/steamapps")
        write(f"{sa}/libraryfolders.vdf", f'"libraryfolders"\n{{\n\t"0"\n\t{{\n\t\t"path"\t\t"{self.home}/.local/share/Steam"\n'
                                          f'\t}}\n\t"1"\n\t{{\n\t\t"path"\t\t"{self.home}/games"\n\t}}\n'
                                          f'\t"2"\n\t{{\n\t\t"path"\t\t"/media/gone"\n\t}}\n}}\n')
        write(f"{sa}/appmanifest_1566200.acf", manifest(1566200, "Tape to Tape", 1026, 1000, 160))
        write(f"{sa}/appmanifest_1493710.acf", manifest(1493710, "Proton Experimental", 4))
        write(f"{sa}/appmanifest_9999.acf", manifest(9999, "Proton 9.0", 4))
        write(f"{other}/appmanifest_620.acf", manifest(620, "Portal 2", 4))
        env = {"XDG_DATA_HOME": os.path.join(self.home, ".local/share"), "XDG_DATA_DIRS": os.path.join(self.home, "none")}
        self.patches = [mock.patch.dict(os.environ, env), mock.patch.object(gl, "HOME", self.home),
                        mock.patch.object(gl, "FLATPAK_SYSTEM", os.path.join(self.home, "none")),
                        mock.patch.object(gl, "STEAM_ROOTS", (os.path.join(self.home, ".local/share/Steam"),))]
        for p in self.patches:
            p.start()

    def tearDown(self):
        for p in self.patches:
            p.stop()
        self.tmp.cleanup()

    def names(self):
        return [g["name"] for g in gl.all_games()]

    def test_games_only_without_steam_or_its_tools(self):
        self.assertEqual(self.names(), ["Cold Start '74", "Portal 2", "Tape to Tape"])

    def test_steam_shortcut_comes_from_the_library_once(self):
        tape = [g for g in gl.all_games() if g["name"] == "Tape to Tape"]
        self.assertEqual(len(tape), 1)
        self.assertEqual(tape[0]["id"], "steam:1566200")

    def test_download_progress(self):
        tape = gl.find("steam:1566200")
        self.assertFalse(tape["installed"])
        self.assertEqual(tape["progress"], 16)
        portal = gl.find("steam:620")
        self.assertTrue(portal["installed"])
        self.assertIsNone(portal["progress"])

    def test_covers_new_and_old_cache(self):
        cache = os.path.join(self.home, ".local/share/Steam/appcache/librarycache")
        write(f"{cache}/1566200/abc123/library_capsule.jpg", "x")
        write(f"{cache}/620_library_600x900.jpg", "x")
        self.assertTrue(gl.find("steam:1566200")["cover"].endswith("abc123/library_capsule.jpg"))
        self.assertTrue(gl.find("steam:620")["cover"].endswith("620_library_600x900.jpg"))
        self.assertEqual(gl.find("desktop:cold-start-74")["cover"], "")

    def test_desktop_game_has_its_path(self):
        g = gl.find("desktop:cold-start-74")
        self.assertTrue(g["path"].endswith("cold-start-74.desktop"))

    def test_no_steam(self):
        with mock.patch.object(gl, "STEAM_ROOTS", (os.path.join(self.home, "nothing"),)):
            self.assertEqual(self.names(), ["Cold Start '74"])


class Vdf(unittest.TestCase):
    def test_nested_and_escaped(self):
        v = gl.parse_vdf('"a"\n{\n\t"b"\t\t"x \\"y\\""\n\t"c"\n\t{\n\t\t"d"\t"1"\n\t}\n}\n')
        self.assertEqual(v["a"]["c"]["d"], "1")
        self.assertEqual(v["a"]["b"], 'x \\"y\\"')


class Running(unittest.TestCase):
    def test_reaper_command_line(self):
        with tempfile.TemporaryDirectory() as proc:
            write(f"{proc}/12/cmdline", "bash\0-c\0true\0")
            write(f"{proc}/34/cmdline", "/steam/reaper\0SteamLaunch\0AppId=1566200\0--\0game.exe\0")
            write(f"{proc}/self/cmdline", "x\0")
            self.assertEqual(gl.steam_game_running(proc), "1566200")

    def test_none(self):
        with tempfile.TemporaryDirectory() as proc:
            write(f"{proc}/12/cmdline", "steam\0-silent\0")
            self.assertEqual(gl.steam_game_running(proc), "")


if __name__ == "__main__":
    unittest.main()
