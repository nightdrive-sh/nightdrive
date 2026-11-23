#!/usr/bin/env python3
"""Files' Open with (apps.py): the type's default comes first and says so, then the apps of the type and, for a text
file, the editors by their category, then every other app; Files itself and hidden apps stay out; open hands the files
to gtk-launch, and --default writes the type's default to mimeapps.list first. Runs apps.py in a throwaway XDG home
whose only apps are the test's own (the system's MIME database is linked in, so a .txt file is text/plain)."""
import json, os, subprocess, sys, tempfile, unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
APPS = HERE / "apps.py"

try:
    import gi
    gi.require_version("Gio", "2.0")
    from gi.repository import Gio  # noqa: F401
    HAVE_GIO = True
except (ImportError, ValueError):
    HAVE_GIO = False
MIME = Path("/usr/share/mime")


def entry(name, mime="", cats="", extra=""):
    return f"[Desktop Entry]\nType=Application\nName={name}\nExec=true %F\nIcon=x-{name.lower()}\n" \
           f"MimeType={mime}\nCategories={cats}\n{extra}"


@unittest.skipUnless(HAVE_GIO and MIME.is_dir(), "needs GIO (python3-gobject) and shared-mime-info")
class OpenWith(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        t = Path(self.tmp.name)
        apps = t / "data/applications"
        apps.mkdir(parents=True)
        (t / "data/mime").symlink_to(MIME)
        (t / "config").mkdir()
        (t / "bin").mkdir()
        for fid, text in {
            "pad.desktop": entry("Pad", "text/plain;"),
            "writer.desktop": entry("Writer", "text/plain;"),
            "code.desktop": entry("Code", "", "Development;IDE;"),           # an editor by its category alone
            "paint.desktop": entry("Paint", "image/png;"),
            "hidden.desktop": entry("Hidden", "text/plain;", extra="NoDisplay=true\n"),
            "nightdrive-files.desktop": entry("Files", "text/plain;inode/directory;"),
        }.items():
            (apps / fid).write_text(text)
        # What update-desktop-database writes: GIO finds a type's apps through it
        (apps / "mimeinfo.cache").write_text("[MIME Cache]\ntext/plain=pad.desktop;writer.desktop;hidden.desktop;"
                                             "nightdrive-files.desktop;\nimage/png=paint.desktop;\n"
                                             "inode/directory=nightdrive-files.desktop;\n")
        (t / "config/mimeapps.list").write_text("[Default Applications]\ntext/plain=writer.desktop\n")
        # gtk-launch stand-in: writes what it was given
        launch = t / "bin/gtk-launch"
        launch.write_text(f"#!/bin/sh\nprintf '%s\\n' \"$@\" > {t}/launched\n")
        launch.chmod(0o755)
        self.file = t / "notes.txt"
        self.file.write_text("hello\n")
        self.t = t
        self.env = {"HOME": str(t), "XDG_DATA_HOME": str(t / "data"), "XDG_DATA_DIRS": str(t / "data"),
                    "XDG_CONFIG_HOME": str(t / "config"), "XDG_CONFIG_DIRS": str(t / "config"),
                    "PATH": f"{t}/bin:/usr/bin:/bin"}

    def tearDown(self):
        self.tmp.cleanup()

    def run_apps(self, *args):
        return subprocess.run([sys.executable, "-I", str(APPS), *args], env=self.env, capture_output=True, text=True,
                              check=True).stdout

    def test_list_order(self):
        d = json.loads(self.run_apps("list", str(self.file)))
        self.assertEqual(d["type"], "text/plain")
        self.assertEqual(d["default"], "writer.desktop")
        ids = [a["id"] for a in d["apps"]]
        self.assertEqual(ids[0], "writer.desktop")
        self.assertTrue(d["apps"][0]["default"])
        self.assertFalse(any(a["default"] for a in d["apps"][1:]))
        kinds = {a["id"]: a["kind"] for a in d["apps"]}
        self.assertEqual(kinds["pad.desktop"], "type")
        self.assertEqual(kinds["code.desktop"], "type")
        self.assertEqual(kinds["paint.desktop"], "other")
        # The type's apps all come before the others
        self.assertEqual(ids.index("paint.desktop"), len(ids) - 1)
        self.assertNotIn("hidden.desktop", ids)
        self.assertNotIn("nightdrive-files.desktop", ids)
        self.assertEqual(d["apps"][0]["icon"], "x-writer")

    def test_folder_has_no_text_editors(self):
        d = json.loads(self.run_apps("list", str(self.t)))
        self.assertEqual(d["type"], "inode/directory")
        self.assertEqual({a["kind"] for a in d["apps"]}, {"other"})

    def test_open_once(self):
        self.run_apps("open", "pad.desktop", str(self.file))
        self.assertEqual((self.t / "launched").read_text().split("\n")[:2], ["pad.desktop", str(self.file)])
        self.assertIn("text/plain=writer.desktop", (self.t / "config/mimeapps.list").read_text())

    def test_open_and_make_default(self):
        self.run_apps("open", "pad.desktop", "--default", str(self.file))
        self.assertIn("pad.desktop", (self.t / "launched").read_text())
        d = json.loads(self.run_apps("list", str(self.file)))
        self.assertEqual(d["default"], "pad.desktop")
        self.assertEqual(d["apps"][0]["id"], "pad.desktop")

    def test_unknown_app(self):
        r = subprocess.run([sys.executable, "-I", str(APPS), "open", "nope.desktop", str(self.file)], env=self.env,
                           capture_output=True, text=True)
        self.assertNotEqual(r.returncode, 0)
        self.assertFalse((self.t / "launched").exists())


if __name__ == "__main__":
    unittest.main()
