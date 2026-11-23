"""The tasks' folder watcher (watch.py) the window reads: one line per burst of changes, lists made later watched too,
a folder made after it started, and nothing for another app's files beside it.

    python3 plugins/tasks/lib/watch_test.py
"""
import os
import select
import shutil
import subprocess
import sys
import tempfile
import time
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))


class WatchTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="tasks-watch-")
        self.root = os.path.join(self.tmp, "share", "nightdrive", "tasks")

    def tearDown(self):
        self.proc.terminate()
        self.proc.wait(5)
        self.proc.stdout.close()
        shutil.rmtree(self.tmp, ignore_errors=True)

    def start(self):
        env = dict(os.environ, NIGHTDRIVE_TASKS_DIR=self.root, HOME=self.tmp)
        self.proc = subprocess.Popen([sys.executable, "-I", os.path.join(HERE, "watch.py")], env=env,
                                     stdout=subprocess.PIPE, text=True)
        time.sleep(0.3)     # its watches in place

    def lines(self, wait=1.0):
        """Lines printed within `wait` seconds of quiet."""
        out = []
        while select.select([self.proc.stdout], [], [], wait)[0]:
            line = self.proc.stdout.readline()
            if not line:
                break
            out.append(line.strip())
        return out

    def write(self, rel, text="x"):
        """As Tasks' store.write does: a hidden temporary, then a rename into place."""
        p = os.path.join(self.root, rel)
        os.makedirs(os.path.dirname(p), exist_ok=True)
        tmp = os.path.join(os.path.dirname(p), ".%s.tmp" % os.path.basename(p))
        with open(tmp, "w") as f:
            f.write(text)
        os.replace(tmp, p)

    def test_a_burst_is_one_line_and_new_lists_are_watched(self):
        os.makedirs(self.root)
        self.start()
        self.assertEqual(self.lines(), [])
        for i in range(20):
            self.write("home/%d.ics" % i)
        self.assertEqual(self.lines(), ["changed"])
        self.write("home/0.ics", "edited")      # in the list made after the start
        self.assertEqual(self.lines(), ["changed"])
        os.unlink(os.path.join(self.root, "home", "1.ics"))
        self.assertEqual(self.lines(), ["changed"])

    def test_folder_made_after_the_start(self):
        os.makedirs(os.path.join(self.tmp, "share"))
        self.start()
        with open(os.path.join(self.tmp, "share", "other-app.txt"), "w") as f:
            f.write("not ours")
        self.assertEqual(self.lines(), [])
        self.write("home/a.ics")
        self.assertEqual(self.lines(), ["changed"])
        self.write("home/b.ics")
        self.assertEqual(self.lines(), ["changed"])


if __name__ == "__main__":
    unittest.main()
