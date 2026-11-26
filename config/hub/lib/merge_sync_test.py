"""A task edited on two devices, merged through a Hub field by field (#3397: Tasks' merge.py, bases.py, sync.settle):
devices as in sync_test, against the Hub in memory and, when its checkout is there, the real one (e2e_test.start).

    python3 config/hub/lib/merge_sync_test.py
"""
import os
import shutil
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import e2e_test  # noqa: E402  (first: it finds the Hub's checkout in the real home)

HOME = tempfile.mkdtemp(prefix="hub-merge-")
# Before Tasks' store is imported (by tasks_rule): it reads where its folder is once. The in-process device lives here.
os.environ.update(HOME=HOME, XDG_DATA_HOME=os.path.join(HOME, "data"), XDG_STATE_HOME=os.path.join(HOME, "state"),
                  XDG_CONFIG_HOME=os.path.join(HOME, "config"), NIGHTDRIVE_HUB_NO_TIMER="1")
os.environ.pop("NIGHTDRIVE_TASKS_DIR", None)

import apps  # noqa: E402
import client as hubclient  # noqa: E402
import devices  # noqa: E402
import sync  # noqa: E402
import tasks_rule  # noqa: E402
import testhub  # noqa: E402

EARLY, LATE = "LAST-MODIFIED:20261123T100000Z\r\n", "LAST-MODIFIED:20261123T110000Z\r\n"


def summary_of(text):
    return text.split("SUMMARY:", 1)[1].split("\r\n", 1)[0]


class Scenarios:
    def setUp(self):
        self.url, self.stop_hub = self.start_hub()
        self.a, self.b = devices.Device("a"), devices.Device("b")
        self.t = self.a.add("home", "Buy milk")
        self.uid = self.t[5:-4]
        self.a.run("join", self.url)
        self.b.run("join", self.url)

    def tearDown(self):
        self.a.close()
        self.b.close()
        self.stop_hub()

    def settle_both(self):
        self.a.sync()
        rep = self.b.sync()["collections"]["tasks"]
        self.a.sync()
        self.assertEqual(self.a.files(), self.b.files())
        return rep

    def test_different_fields_merge_into_one_task(self):
        self.a.write(self.t, devices.vtodo(self.uid, "Buy oat milk", EARLY))
        self.b.write(self.t, devices.vtodo(self.uid, "Buy milk", LATE + "DUE;VALUE=DATE:20261205\r\n"))
        rep = self.settle_both()
        self.assertEqual((rep["merged"], rep["kept_both"]), ([self.t], []))
        text = self.b.read(self.t)
        self.assertEqual(summary_of(text), "Buy oat milk")
        self.assertIn("DUE;VALUE=DATE:20261205", text)
        self.assertNotIn("DESCRIPTION", text)                  # nothing lost, no note
        self.assertEqual(len([k for k in self.a.files() if k.endswith(".ics")]), 1)

    def test_same_field_newer_wins_and_the_other_is_in_the_notes(self):
        self.a.write(self.t, devices.vtodo(self.uid, "Buy milk today", LATE))
        self.b.write(self.t, devices.vtodo(self.uid, "Buy milk and bread", EARLY))
        rep = self.settle_both()
        self.assertEqual(rep["merged"], [self.t])
        text = self.a.read(self.t)
        self.assertEqual(summary_of(text), "Buy milk today")
        notes = tasks_rule.ics.Task(text).get("DESCRIPTION")
        self.assertIn("Title: Buy milk and bread", notes)
        self.assertIn("(%s, " % apps.host(), notes)     # named by the losing side's host

    def test_no_agreed_version_keeps_both(self):
        # b's copy of the agreed versions is gone (a computer that synced before them, cleared state): as before #3397
        shutil.rmtree(os.path.join(self.b.home, ".local/state/nightdrive/hub/base"))
        self.a.write(self.t, devices.vtodo(self.uid, "Buy milk today"))
        self.b.write(self.t, devices.vtodo(self.uid, "Buy milk and bread"))
        rep = self.settle_both()
        self.assertEqual((rep["merged"], rep["kept_both"]), ([], [self.t]))
        self.assertEqual(len([k for k in self.b.files() if k.endswith(".ics")]), 2)

    def test_base_follows_each_agreement(self):
        # Two rounds: the second merge starts from what the first agreed on, not from the very first version
        self.a.write(self.t, devices.vtodo(self.uid, "Round one", EARLY))
        self.settle_both()
        self.b.sync()
        self.a.write(self.t, devices.vtodo(self.uid, "Round one", LATE + "PRIORITY:1\r\n"))
        self.b.write(self.t, devices.vtodo(self.uid, "Round two", LATE))
        rep = self.settle_both()
        self.assertEqual(rep["merged"], [self.t])
        text = self.a.read(self.t)
        self.assertEqual(summary_of(text), "Round two")
        self.assertIn("PRIORITY:1", text)
        self.assertNotIn("DESCRIPTION", text)


class MemoryHubTest(Scenarios, unittest.TestCase):
    def start_hub(self):
        self.hub = testhub.TestHub()
        return self.hub.url, self.hub.stop


@unittest.skipUnless(e2e_test.HAVE, "needs the Hub's checkout (%s or NIGHTDRIVE_HUB_SRC)" % e2e_test.SRC)
class RealHubTest(Scenarios, unittest.TestCase):
    def start_hub(self):
        return e2e_test.start()


class Racing(hubclient.Client):
    """A client whose first write is beaten by another device's: `before_put` runs just before it, so the Hub answers
    409 and the merge happens in the push, not the pull."""

    def __init__(self, url, before_put):
        super().__init__(url)
        self.before_put = before_put

    def put(self, *args):
        if self.before_put:
            run, self.before_put = self.before_put, None
            run()
        return super().put(*args)


class PushConflictTest(unittest.TestCase):
    """This process is device b (HOME above), a is a device of its own."""

    def setUp(self):
        self.hub = testhub.TestHub()
        self.a = devices.Device("a")
        self.t = self.a.add("home", "Buy milk")
        self.uid = self.t[5:-4]
        self.a.run("join", self.hub.url)
        self.rule = tasks_rule.TasksRule()

    def tearDown(self):
        self.a.close()
        self.hub.stop()
        shutil.rmtree(HOME, ignore_errors=True)

    def sync_b(self, before_put=None):
        hub = Racing(self.hub.url, before_put)
        try:
            server = hub.info()["server"]
            hub.server = server
            return sync.Sync(hub, self.rule).run(server)
        finally:
            hub.close()

    def test_conflict_on_write_merges_and_sends_the_merge(self):
        self.sync_b()
        mine = os.path.join(self.rule.root(), self.t)
        with open(mine, "w", newline="") as f:
            f.write(devices.vtodo(self.uid, "Buy oat milk", EARLY))
        self.a.write(self.t, devices.vtodo(self.uid, "Buy milk", LATE + "PRIORITY:1\r\n"))
        rep = self.sync_b(before_put=self.a.sync)
        self.assertEqual((rep.merged, rep.kept_both), ([self.t], []))
        with open(mine, newline="") as f:
            text = f.read()
        self.assertEqual(summary_of(text), "Buy oat milk")
        self.assertIn("PRIORITY:1", text)
        self.assertEqual(self.hub.live()[self.t], text.encode())  # the merge went to the Hub in the same sync
        self.a.sync()
        self.assertEqual(self.a.read(self.t), text)


if __name__ == "__main__":
    try:
        unittest.main()
    finally:
        shutil.rmtree(HOME, ignore_errors=True)
