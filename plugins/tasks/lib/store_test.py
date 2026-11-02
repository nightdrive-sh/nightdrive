#!/usr/bin/env python3
"""An undo stays in the tasks' folder (#1925): `python3 plugins/tasks/lib/store_test.py`. A snapshot in the state
folder names the files `tasks restore` puts back; one written by something else (a path out of the folder, a list
folder that is a link) is refused whole, changing nothing, while the undo of a real change works as before."""

import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
SECRET = "export PATH=$HOME/bin:$PATH\n"


class Restore(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.home = Path(self.tmp.name).resolve()
        self.data = self.home / "tasks"
        self.undo = self.home / "state/nightdrive/tasks/undo"
        self.victim = self.home / ".bashrc"
        self.victim.write_text(SECRET)
        (self.home / "elsewhere").mkdir()
        (self.home / "elsewhere/keep.txt").write_text("keep\n")
        self.env = {k: v for k, v in os.environ.items() if not k.startswith(("XDG_", "NIGHTDRIVE_"))}
        self.env.update(HOME=str(self.home), NIGHTDRIVE_TASKS_DIR=str(self.data),
                        XDG_STATE_HOME=str(self.home / "state"))

    def tearDown(self):
        self.tmp.cleanup()

    def tasks(self, *argv):
        return subprocess.run([sys.executable, str(HERE / "cli.py"), *argv], capture_output=True, text=True,
                              env=self.env, timeout=30)

    def add(self, title="Milk"):
        p = self.tasks("add", "--json", "--", title)
        self.assertEqual(p.returncode, 0, p.stderr)
        return json.loads(p.stdout)

    def forge(self, files):
        """A snapshot as restore() reads it, with the paths given"""
        sid = "abc123"
        (self.undo / f"{sid}.json").write_text(json.dumps({"files": files}))
        return sid

    def assert_refused(self, sid):
        p = self.tasks("restore", "--json", sid)
        self.assertNotEqual(p.returncode, 0, p.stdout)
        self.assertIn("nothing was changed", p.stdout + p.stderr)
        self.assertEqual(self.victim.read_text(), SECRET)
        self.assertEqual((self.home / "elsewhere/keep.txt").read_text(), "keep\n")
        self.assertTrue(self.data.is_dir())
        self.assertTrue((self.undo / f"{sid}.json").is_file(), "a refused undo stays to be seen")

    def test_paths_out_of_the_folder(self):
        self.add()
        for path in ("../.bashrc", "tasks/../../.bashrc", str(self.victim), "/etc/passwd", ".bashrc",
                     "tasks/sub/x.ics", "", "./displayname", "tasks/.."):
            for before in (None, "pwned\n"):
                with self.subTest(path=path, before=before):
                    self.assert_refused(self.forge([{"path": path, "before": before}]))

    def test_rmtree_of_the_folder_itself(self):
        # displayname with before None is a list the change made: its folder goes. Not the tasks' folder, or the home
        self.add()
        for path in ("displayname", "../displayname"):
            with self.subTest(path=path):
                self.assert_refused(self.forge([{"path": path, "before": None}]))

    def test_links_resolved(self):
        self.add()
        (self.data / "out").symlink_to(self.home / "elsewhere")      # a list folder leading out
        (self.data / "tasks/rc.ics").symlink_to(self.victim)         # a task file leading out
        (self.data / "loop").symlink_to(self.data)                   # a list folder that is the folder itself
        for path in ("out/keep.txt", "out/displayname", "tasks/rc.ics", "loop/displayname", "loop/tasks"):
            for before in (None, "pwned\n"):
                with self.subTest(path=path, before=before):
                    self.assert_refused(self.forge([{"path": path, "before": before}]))

    def test_one_bad_path_refuses_the_whole_undo(self):
        made = self.add()
        mine = next((self.data / "tasks").glob("*.ics"))
        sid = self.forge([{"path": str(mine.relative_to(self.data)), "before": None},
                          {"path": "../.bashrc", "before": "pwned\n"}])
        self.assert_refused(sid)
        self.assertTrue(mine.is_file(), made)

    def test_the_trash_side_too(self):
        # A path that is fine in the folder but leads out through a link in the trash: its unlink there is refused
        self.add()
        trash = self.home / "state/nightdrive/tasks/trash"
        trash.mkdir(parents=True)
        (trash / "tasks").symlink_to(self.home / "elsewhere")
        self.assert_refused(self.forge([{"path": "tasks/keep.txt", "before": "x\n"}]))

    def test_real_undos_still_work(self):
        made = self.add()
        p = self.tasks("restore", "--json", made["undo"])
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertEqual(list(self.data.iterdir()), [], "the list the add made goes with it")

        made = self.add("Bread")
        p = self.tasks("trash", "--json", "--", made["id"])
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertEqual(list(self.data.glob("*/*.ics")), [])
        p = self.tasks("restore", "--json", json.loads(p.stdout)["undo"])
        self.assertEqual(p.returncode, 0, p.stderr)
        listed = json.loads(self.tasks("list", "--json").stdout)["tasks"]
        self.assertEqual([t["title"] for t in listed], ["Bread"])
        self.assertEqual(list((self.home / "state/nightdrive/tasks/trash").glob("*/*.ics")), [])


if __name__ == "__main__":
    unittest.main()
