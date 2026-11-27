"""archive_default.py: the extract entry becomes the default of the archive types the user hasn't chosen, and goes away
again without touching anything else in mimeapps.list (#3719)."""
import os, sys, tempfile, unittest
from importlib.machinery import SourceFileLoader
from importlib.util import module_from_spec, spec_from_loader

HERE = os.path.dirname(os.path.realpath(__file__))
sys.dont_write_bytecode = True


def load(home):
    """The module with its paths in a throwaway home (they are read when it loads)."""
    os.environ["HOME"] = home
    os.environ["XDG_CONFIG_HOME"] = os.path.join(home, ".config")
    os.environ["XDG_DATA_HOME"] = os.path.join(home, ".local", "share")
    loader = SourceFileLoader("archive_default", os.path.join(HERE, "archive_default.py"))
    mod = module_from_spec(spec_from_loader("archive_default", loader))
    loader.exec_module(mod)
    return mod


class ArchiveDefault(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.home = self.tmp.name
        self.mod = load(self.home)
        self.mimeapps = os.path.join(self.home, ".config", "mimeapps.list")

    def tearDown(self):
        self.tmp.cleanup()

    def write(self, text):
        os.makedirs(os.path.dirname(self.mimeapps), exist_ok=True)
        open(self.mimeapps, "w").write(text)

    def read(self):
        return open(self.mimeapps).read()

    def test_on_sets_unchosen_types_and_keeps_the_users(self):
        self.write("[Default Applications]\napplication/x-tar=org.gnome.FileRoller.desktop\ntext/plain=gedit.desktop\n")
        r = self.mod.on()
        self.assertNotIn("application/x-tar", r["added"])
        self.assertIn("application/zip", r["added"])
        d = self.mod.defaults.defaults(self.read().splitlines())
        self.assertEqual(d["application/zip"], self.mod.ID)
        self.assertEqual(d["application/x-tar"], "org.gnome.FileRoller.desktop")
        self.assertEqual(d["text/plain"], "gedit.desktop")
        a = self.mod.defaults.associations(self.read().splitlines())
        self.assertTrue(a["application/zip"].startswith(self.mod.ID))
        entry = open(self.mod.entry_path()).read()
        self.assertIn("extract %F", entry)
        self.assertIn("NoDisplay=true", entry)

    def test_on_twice_adds_nothing_more(self):
        self.mod.on()
        before = self.read()
        self.assertEqual(self.mod.on()["added"], [])
        self.assertEqual(self.read(), before)

    def test_off_takes_only_its_own_lines(self):
        self.write("[Default Applications]\napplication/x-tar=org.gnome.FileRoller.desktop\n"
                   "[Added Associations]\napplication/zip=org.gnome.Nautilus.desktop;\n")
        self.mod.on()
        r = self.mod.off()
        self.assertIn("application/zip", r["dropped"])
        text = self.read()
        self.assertNotIn(self.mod.ID, text)
        self.assertIn("application/x-tar=org.gnome.FileRoller.desktop", text)
        self.assertIn("application/zip=org.gnome.Nautilus.desktop;", text)
        self.assertFalse(os.path.exists(self.mod.entry_path()))

    def test_sync_follows_files(self):
        self.mod.main(["sync"])
        self.assertFalse(os.path.exists(self.mimeapps))         # Files isn't installed: nothing written
        apps = os.path.join(self.home, ".local", "share", "applications")
        os.makedirs(apps, exist_ok=True)
        open(os.path.join(apps, self.mod.FILES_ID), "w").write("[Desktop Entry]\n")
        self.mod.main(["sync"])
        self.assertIn(self.mod.ID, self.read())
        os.remove(os.path.join(apps, self.mod.FILES_ID))
        self.mod.main(["sync"])
        self.assertNotIn(self.mod.ID, self.read())


if __name__ == "__main__":
    unittest.main()
