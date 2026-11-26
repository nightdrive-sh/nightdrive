#!/usr/bin/env python3
"""default-apps (#3273): a file opens in the same app whichever way it is opened. `python3 config/hypr/scripts/default_apps_test.py`.

Under Hyprland xdg-open knows no desktop: it reads a file's type with xdg-mime (mimetype, from perl-File-MimeInfo) and
its app from mimeapps.list, while Files and gio open ask GIO. Nothing is opened here: the types and apps are only
asked for, in a throwaway home."""

import os
import shutil
import subprocess
import tempfile
import unittest
from importlib.machinery import SourceFileLoader
from importlib.util import module_from_spec, spec_from_loader
from pathlib import Path
from unittest import mock

HERE = Path(__file__).resolve().parent
loader = SourceFileLoader("default_apps", str(HERE / "default-apps"))
da = module_from_spec(spec_from_loader("default_apps", loader))
loader.exec_module(da)

SAMPLES = {"notes.md": "# Notes\n", "table.csv": "a,b\n1,2\n", "data.json": '{"a": 1}\n'}
TOOLS = ("xdg-mime", "mimetype", "gio")


@unittest.skipUnless(all(shutil.which(t) for t in TOOLS), "needs xdg-utils, perl-File-MimeInfo and gio")
class SameType(unittest.TestCase):
    """xdg-open's type (xdg-mime query filetype, as its generic path asks) is GIO's, read from the name: without
    mimetype it asked file(1), which calls a .md or .csv text/plain."""

    def test_types(self):
        with tempfile.TemporaryDirectory() as d:
            # No desktop: xdg-mime's generic path, as under Hyprland
            env = {k: v for k, v in os.environ.items() if k not in ("XDG_CURRENT_DESKTOP", "DESKTOP_SESSION",
                                                                     "KDE_FULL_SESSION", "GNOME_DESKTOP_SESSION_ID")}
            for name, text in SAMPLES.items():
                path = Path(d) / name
                path.write_text(text)
                xdg = subprocess.run(["xdg-mime", "query", "filetype", str(path)], capture_output=True, text=True,
                                     env=env).stdout.strip().split(";")[0]
                gio = subprocess.run(["gio", "info", "-a", "standard::content-type", str(path)], capture_output=True,
                                     text=True, env=env).stdout.split("standard::content-type:")[-1].strip()
                self.assertEqual(xdg, gio, name)
                self.assertNotEqual(xdg, "text/plain", name)


class Follow(unittest.TestCase):
    """Source code types with no app of their own get text/plain's app written down, so xdg-open's lookup (the type's
    own line in mimeapps.list) finds what GIO finds through the parents; a choice of the user's stays."""

    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.mimeapps = os.path.join(self.dir.name, "mimeapps.list")
        self.followed = os.path.join(self.dir.name, "state", "code-follows-text")
        self.patches = [mock.patch.object(da, "MIMEAPPS", self.mimeapps),
                        mock.patch.object(da, "FOLLOWED", self.followed),
                        mock.patch.object(da, "CODE", ["application/json", "text/x-python", "text/x-rust"])]
        for p in self.patches: p.start()
        self.gio = {}   # what GIO answers for a type with no line of its own

    def tearDown(self):
        for p in self.patches: p.stop()
        self.dir.cleanup()

    def current(self, mime):
        return da.defaults(da.read_mimeapps()).get(mime) or self.gio.get(mime, "")

    def follow(self):
        with mock.patch.object(da, "current", self.current):
            da.follow()
        return da.defaults(da.read_mimeapps())

    def test_written_and_moved(self):
        # json and python reach text/plain's app through their parents; rust has an app of its own
        self.gio = {"text/plain": "writer.desktop", "application/json": "writer.desktop",
                    "text/x-python": "writer.desktop", "text/x-rust": "rustide.desktop"}
        own = self.follow()
        self.assertEqual(own["application/json"], "writer.desktop")
        self.assertEqual(own["text/x-python"], "writer.desktop")
        self.assertNotIn("text/x-rust", own)
        self.assertIn("application/json=writer.desktop;", Path(self.mimeapps).read_text())   # Added Associations too
        # A text editor chosen: the types written for the old one follow it
        Path(self.mimeapps).write_text(Path(self.mimeapps).read_text().replace(
            "[Default Applications]\n", "[Default Applications]\ntext/plain=editor.desktop\n"))
        own = self.follow()
        self.assertEqual(own["application/json"], "editor.desktop")
        self.assertEqual(own["text/x-python"], "editor.desktop")
        self.assertNotIn("text/x-rust", own)

    def test_choice_kept(self):
        self.gio = {"text/plain": "writer.desktop", "application/json": "writer.desktop",
                    "text/x-python": "writer.desktop"}
        Path(self.mimeapps).write_text("[Default Applications]\napplication/json=code.desktop\n")
        own = self.follow()
        self.assertEqual(own["application/json"], "code.desktop")
        self.assertEqual(own["text/x-python"], "writer.desktop")

    def test_no_text_app(self):
        self.follow()
        self.assertFalse(os.path.exists(self.mimeapps))

    def set_text_if_unset(self):
        apps = {"nightdrive-text.desktop": {"Name": "Text"}, "writer.desktop": {"Name": "Writer"}}
        with mock.patch.object(da, "entries", lambda: apps), mock.patch.object(da, "current", self.current):
            da.set_default("text", "nightdrive-text.desktop", if_unset=True)
        return da.defaults(da.read_mimeapps())

    def test_text_editor_installed(self):
        # #3414: nothing chosen, text/plain fell to the last app registering it (Writer), and the code types followed it
        self.gio = {"text/plain": "writer.desktop", "application/json": "writer.desktop"}
        self.follow()
        own = self.set_text_if_unset()
        for t in ("text/plain", "text/csv", "application/json"):
            self.assertEqual(own[t], "nightdrive-text.desktop", t)

    def test_text_editor_chosen_stays(self):
        # A text editor the user chose (Settings › Apps › Default apps) is left alone by an install or an update
        Path(self.mimeapps).write_text("[Default Applications]\ntext/plain=writer.desktop\n")
        own = self.set_text_if_unset()
        self.assertEqual(own["text/plain"], "writer.desktop")
        self.assertNotIn("text/csv", own)


if __name__ == "__main__":
    unittest.main()
