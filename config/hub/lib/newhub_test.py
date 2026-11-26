"""A Hub lost and set up again, or put back from a backup, at the same address (#3398): the devices fill it again
("seed") and nothing is deleted on any of them, identical files make no conflict, and an edit is never rolled back to
an older copy (fresh.py). Each scenario runs against the Hub in memory and, when its checkout is there, the real one.

    python3 config/hub/lib/newhub_test.py
"""
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import devices  # noqa: E402
import testhub  # noqa: E402

SRC = os.environ.get("NIGHTDRIVE_HUB_SRC") or os.path.expanduser("~/Projects/nightdrive-hub")
HAVE = os.path.isfile(os.path.join(SRC, "hub", "main.py"))


class RealHub:
    """The real Hub (its checkout) on one port for the whole test, its data in a throwaway folder: replace() and
    restore() stop it, change the data and start it again on the same port, as a person would on the same machine."""

    def __init__(self):
        self.dir = tempfile.mkdtemp(prefix="hub-new-")
        self.data = os.path.join(self.dir, "hub")
        self.port, self.proc, self.snaps = 0, None, 0
        self.start()
        self.url = "http://127.0.0.1:%d" % self.port

    def hub(self, *args):
        env = {k: v for k, v in os.environ.items() if k != "PYTHONPATH"}
        return [sys.executable, "-m", "hub"] + list(args), env

    def start(self):
        cmd, env = self.hub("serve", "--data", self.data, "--port", str(self.port))
        for _ in range(50):     # the port of the Hub just stopped may take a moment to be free
            self.proc = subprocess.Popen(cmd, cwd=SRC, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                         text=True)
            line = self.proc.stdout.readline()
            m = re.search(r"http://127\.0\.0\.1:(\d+)", line)
            if m:
                self.port = int(m.group(1))
                return
            self.proc.wait(10)
            self.proc.stdout.close()
            time.sleep(0.1)
        raise RuntimeError("The Hub didn't start: %r" % line)

    def halt(self):
        if self.proc:
            self.proc.terminate()
            self.proc.wait(10)
            self.proc.stdout.close()
            self.proc = None

    def replace(self):
        self.halt()
        shutil.rmtree(self.data)
        self.start()

    def snapshot(self):
        """A copy taken by `hub backup` while the Hub serves, as the nightly job takes it."""
        self.snaps += 1
        snap = os.path.join(self.dir, "snap%d" % self.snaps)
        cmd, env = self.hub("backup", "--data", self.data, snap)
        subprocess.run(cmd, cwd=SRC, env=env, check=True, capture_output=True)
        return snap

    def restore(self, snap, same_id=False):
        """The data folder put back from `snap`: by `hub restore` (a new id), or by hand (same_id: the copy's hub.db
        and history/ put in place; the Hub makes files/ again on start)."""
        self.halt()
        shutil.rmtree(self.data)
        if same_id:
            shutil.copytree(snap, self.data)
        else:
            cmd, env = self.hub("restore", snap, "--data", self.data)
            subprocess.run(cmd, cwd=SRC, env=env, check=True, capture_output=True)
        self.start()

    def stop(self):
        self.halt()
        shutil.rmtree(self.dir, ignore_errors=True)


class Scenarios:
    def setUp(self):
        self.hub = self.make_hub()
        self.a, self.b = devices.Device("a"), devices.Device("b")

    def tearDown(self):
        self.a.close()
        self.b.close()
        self.hub.stop()

    def tasks(self, d):
        return sorted(k for k in d.files() if k.endswith(".ics"))

    def quiet(self, rep):
        """No conflict was made: nothing kept twice, merged or brought back."""
        self.assertEqual((rep["kept_both"], rep.get("merged", []), rep["revived"]), ([], [], []))

    def test_a_new_hub_deletes_nothing_anywhere(self):
        t = [self.a.add("home", "Task %d" % i) for i in range(5)]
        self.a.run("join", self.hub.url)
        self.b.run("join", self.hub.url)
        self.a.remove(t[0])         # deletions made while the Hub is lost: a fresh start must not spread them
        self.b.remove(t[1])
        self.b.write(t[2], devices.vtodo(t[2][5:-4], "Task 2, edited"))
        self.hub.replace()
        for d in (self.a, self.b, self.a):
            rep = d.sync()["collections"]["tasks"]
            self.quiet(rep)
            self.assertEqual((rep["deleted_here"], rep["deleted_there"]), (0, 0))
        for d in (self.a, self.b):
            self.assertEqual(self.tasks(d), sorted(t))
            self.assertIn("Task 2, edited", d.read(t[2]))
            self.assertEqual(d.trashed(), [])
        self.assertEqual(self.a.files(), self.b.files())

    def test_seeding_one_after_another_takes_the_newer_side(self):
        t1 = self.a.add("home", "One")
        t2 = self.a.add("home", "Two")
        self.a.run("join", self.hub.url)
        self.b.run("join", self.hub.url)
        self.a.write(t1, devices.vtodo(t1[5:-4], "One, edited on a"))
        self.a.sync()                       # b never got this edit: it is behind on t1
        self.b.write(t2, devices.vtodo(t2[5:-4], "Two, edited on b"))     # and never sent this one
        self.hub.replace()
        rep = self.b.sync()["collections"]["tasks"]     # b seeds the new Hub with its old t1
        self.assertTrue(rep["fresh"])
        rep = self.a.sync()["collections"]["tasks"]
        self.assertTrue(rep["fresh"])
        self.quiet(rep)
        self.assertEqual((rep["sent"], rep["fetched"]), (1, 1))     # its t1 over b's old one, b's t2 over its own
        self.quiet(self.b.sync()["collections"]["tasks"])
        for d in (self.a, self.b):
            self.assertIn("One, edited on a", d.read(t1))
            self.assertIn("Two, edited on b", d.read(t2))
            self.assertEqual(len(self.tasks(d)), 2)

    def test_same_task_edited_on_both_while_lost_loses_neither(self):
        t = self.a.add("home", "Task")
        self.a.run("join", self.hub.url)
        self.b.run("join", self.hub.url)
        self.a.write(t, devices.vtodo(t[5:-4], "Task, a's way"))
        self.b.write(t, devices.vtodo(t[5:-4], "Task, b's way"))
        self.hub.replace()
        for d in (self.a, self.b, self.a):
            d.sync()
        self.assertEqual(self.a.files(), self.b.files())
        text = "".join(self.a.files().values())
        self.assertIn("a's way", text)      # merged into one task or kept as two: either way, both are there
        self.assertIn("b's way", text)

    def test_a_hub_restored_from_a_backup_rolls_nothing_back(self):
        t1 = self.a.add("home", "One")
        t2 = self.a.add("home", "Two")
        self.a.run("join", self.hub.url)
        self.b.run("join", self.hub.url)
        snap = self.hub.snapshot()
        self.a.write(t1, devices.vtodo(t1[5:-4], "One, after the backup"))
        t3 = self.a.add("home", "Three, after the backup")
        self.a.sync()
        self.b.sync()
        self.b.write(t2, devices.vtodo(t2[5:-4], "Two, edited on b"))    # not sent before the Hub was lost
        self.hub.restore(snap)
        for d in (self.b, self.a, self.b):
            self.quiet(d.sync()["collections"]["tasks"])
        for d in (self.a, self.b):
            self.assertIn("One, after the backup", d.read(t1))
            self.assertIn("Two, edited on b", d.read(t2))
            self.assertEqual(self.tasks(d), sorted([t1, t2, t3]))

    def test_a_hub_put_back_by_hand_is_noticed(self):
        """The same id, older versions: a device whose cursor is past the Hub's newest version starts fresh."""
        t = self.a.add("home", "Task")
        self.a.run("join", self.hub.url)
        snap = self.hub.snapshot()
        self.a.write(t, devices.vtodo(t[5:-4], "Task, after the backup"))
        self.a.sync()
        self.hub.restore(snap, same_id=True)
        rep = self.a.sync()["collections"]["tasks"]
        self.assertTrue(rep["fresh"])
        self.quiet(rep)
        self.assertEqual(rep["sent"], 1)
        self.assertIn("after the backup", self.a.read(t))


class MemoryHubTest(Scenarios, unittest.TestCase):
    def make_hub(self):
        return testhub.TestHub()


@unittest.skipUnless(HAVE, "needs the Hub's checkout (%s or NIGHTDRIVE_HUB_SRC)" % SRC)
class RealHubTest(Scenarios, unittest.TestCase):
    def make_hub(self):
        return RealHub()


if __name__ == "__main__":
    unittest.main()
