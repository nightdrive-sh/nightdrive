#!/usr/bin/env python3
"""no-app and fitting_app.py (#3715): a document whose type only an archive's app claims gets no-app's entry as its
default, which steps aside once an app opens the type; a real zip, and the user's own choice, stay as they are."""
import json, os, shutil, subprocess, sys, tempfile, time, unittest, zipfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
NO_APP = HERE / "no-app"
MIME = Path("/usr/share/mime")
XLSX = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
ID = "nightdrive-no-app.desktop"
try:
    import gi
    gi.require_version("Gio", "2.0")
    HAVE_GIO = True
except (ImportError, ValueError):
    HAVE_GIO = False


@unittest.skipUnless(HAVE_GIO and MIME.is_dir() and shutil.which("update-desktop-database"),
                     "needs GIO (python3-gobject), shared-mime-info and desktop-file-utils")
class NoApp(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        t = self.t = Path(self.tmp.name)
        (t / "data/applications").mkdir(parents=True)
        (t / "data/mime").symlink_to(MIME)
        (t / "config").mkdir()
        (t / "bin").mkdir()
        # gtk-launch and notify-send stand-ins: what they were asked
        for tool in ("gtk-launch", "notify-send"):
            p = t / "bin" / tool
            p.write_text(f"#!/bin/sh\nprintf '%s\\n' \"$@\" > {t}/{tool}\n")
            p.chmod(0o755)
        self.app("org.gnome.Nautilus", "inode/directory;application/zip;")
        self.env = {"HOME": str(t), "XDG_DATA_HOME": str(t / "data"), "XDG_DATA_DIRS": str(t / "data"),
                    "XDG_CONFIG_HOME": str(t / "config"), "XDG_CONFIG_DIRS": str(t / "config"),
                    "XDG_STATE_HOME": str(t / "state"), "PATH": f"{t}/bin:/usr/bin:/bin"}

    def tearDown(self):
        self.tmp.cleanup()

    def app(self, name, types):
        (self.t / f"data/applications/{name}.desktop").write_text(
            f"[Desktop Entry]\nType=Application\nName={name}\nExec=true %F\nMimeType={types}\n")
        subprocess.run(["update-desktop-database", str(self.t / "data/applications")], check=True)

    def run_no_app(self, *args):
        r = subprocess.run([sys.executable, "-I", str(NO_APP), *args], env=self.env, capture_output=True, text=True)
        self.assertEqual(r.returncode, 0, r.stderr)
        return r.stdout

    def mimeapps(self):
        p = self.t / "config/mimeapps.list"
        return p.read_text() if p.exists() else ""

    def wait_for(self, name):
        p = self.t / name
        for _ in range(100):
            if p.exists() and p.read_text():
                return p.read_text()
            time.sleep(0.05)
        self.fail(f"{name} never came")

    def test_guard_stands_in_for_documents_only(self):
        r = json.loads(self.run_no_app("guard", "--json"))
        self.assertIn(XLSX, r["added"])
        self.assertIn("application/epub+zip", r["added"])
        self.assertNotIn("application/zip", r["added"])       # a real zip stays the file manager's
        text = self.mimeapps()
        self.assertIn(f"{XLSX}={ID}\n", text)
        self.assertIn(f"{XLSX}={ID};\n", text)                 # [Added Associations]: GIO's default needs it
        # Again: nothing more to do
        self.assertEqual(json.loads(self.run_no_app("guard", "--json")), {"added": [], "dropped": []})

    def test_guard_steps_aside_for_a_new_app(self):
        self.run_no_app("guard")
        self.app("calc", f"{XLSX};")
        r = json.loads(self.run_no_app("guard", "--json"))
        self.assertEqual(r["dropped"], [XLSX])
        self.assertNotIn(f"{XLSX}={ID}", self.mimeapps())
        self.assertIn(f"application/epub+zip={ID}", self.mimeapps())

    def test_guard_leaves_the_users_choice(self):
        (self.t / "config/mimeapps.list").write_text(
            "[Default Applications]\napplication/java-archive=org.gnome.Nautilus.desktop\n")
        r = json.loads(self.run_no_app("guard", "--json"))
        self.assertNotIn("application/java-archive", r["added"])
        self.assertIn("application/java-archive=org.gnome.Nautilus.desktop", self.mimeapps())

    def test_a_file_whose_app_came_opens_there(self):
        self.run_no_app("guard")
        self.app("calc", f"{XLSX};")
        f = self.t / "sheet.xlsx"
        with zipfile.ZipFile(f, "w") as z:
            z.writestr("content.xml", "<x/>")
        self.run_no_app(str(f))
        self.assertEqual(self.wait_for("gtk-launch").split(), ["calc.desktop", str(f)])
        self.assertNotIn(f"{XLSX}={ID}", self.mimeapps())

    def test_without_files_a_notification_says_so(self):
        f = self.t / "book.epub"
        with zipfile.ZipFile(f, "w") as z:
            z.writestr("mimetype", "application/epub+zip")
        self.run_no_app(str(f))
        said = self.wait_for("notify-send")
        self.assertIn("No app opens book.epub", said)
        self.assertIn("Foliate", said)
        self.assertFalse((self.t / "gtk-launch").exists())


if __name__ == "__main__":
    unittest.main()
