"""Tasks between two devices through a Hub (sync.py): each device a throwaway home, the Hub in memory (testhub.py).
The same scenarios run against the real Hub in e2e_test.py.

    python3 config/hub/lib/sync_test.py
"""
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import devices  # noqa: E402
import testhub  # noqa: E402


class Scenarios:
    """The scenarios, for any Hub: a subclass gives start_hub() -> (url, stop, replace)."""

    def setUp(self):
        self.url, self.stop_hub = self.start_hub()
        self.a, self.b = devices.Device("a"), devices.Device("b")

    def tearDown(self):
        self.a.close()
        self.b.close()
        self.stop_hub()

    def join_both(self):
        self.a.run("join", self.url)
        self.b.run("join", self.url)

    def test_first_device_seeds_and_second_gets_everything(self):
        t1 = self.a.add("home", "Buy milk")
        t2 = self.a.add("work", "Write report")
        self.join_both()
        self.assertEqual(self.b.files(), self.a.files())
        self.assertIn(t1, self.b.files())
        self.assertIn(t2, self.b.files())
        self.assertEqual(self.b.read("home/displayname"), "Home\n")

    def test_edits_and_new_tasks_both_ways(self):
        t = self.a.add("home", "Buy milk")
        self.join_both()
        self.a.write(t, devices.vtodo(t[5:-4], "Buy oat milk"))
        new = self.b.add("home", "Call mum")
        self.a.sync()
        rep = self.b.sync()["collections"]["tasks"]
        self.assertEqual((rep["fetched"], rep["sent"]), (1, 1))
        self.a.sync()
        self.assertEqual(self.a.files(), self.b.files())
        self.assertIn("Buy oat milk", self.b.read(t))
        self.assertIn(new, self.a.files())

    def test_deletion_goes_to_tasks_trash(self):
        t = self.a.add("home", "Buy milk")
        self.join_both()
        self.a.remove(t)
        self.a.sync()
        rep = self.b.sync()["collections"]["tasks"]
        self.assertEqual(rep["deleted_here"], 1)
        self.assertIsNone(self.b.read(t))
        self.assertEqual(self.b.trashed(), [t])

    def test_removed_list_leaves_no_folder(self):
        t = self.a.add("trip", "Pack")
        self.join_both()
        self.a.remove(t)
        self.a.remove("trip/displayname")
        os.rmdir(os.path.join(self.a.tasks, "trip"))
        self.a.sync()
        self.b.sync()
        self.assertFalse(os.path.exists(os.path.join(self.b.tasks, "trip")))
        self.assertEqual(self.b.trashed(), [t])

    def test_edit_wins_over_deletion_either_order(self):
        t1 = self.a.add("home", "One")
        t2 = self.a.add("home", "Two")
        self.join_both()
        # t1: deleted on a, edited on b; a syncs first
        self.a.remove(t1)
        self.b.write(t1, devices.vtodo(t1[5:-4], "One, edited"))
        # t2: edited on a, deleted on b; b syncs first (its deletion is refused, the edit comes back)
        self.a.write(t2, devices.vtodo(t2[5:-4], "Two, edited"))
        self.b.remove(t2)
        self.a.sync()
        self.b.sync()
        self.a.sync()
        for d in (self.a, self.b):
            self.assertIn("One, edited", d.read(t1))
            self.assertIn("Two, edited", d.read(t2))

    def test_same_task_edited_on_both_is_merged(self):
        # Field by field (merge_sync_test.py has the cases): neither says when it changed, so the Hub's (first) title
        # stays and b's goes in the notes. With no version both agreed on, both are kept (a fresh start, below).
        t = self.a.add("home", "Buy milk")
        uid = t[5:-4]
        self.join_both()
        self.a.write(t, devices.vtodo(uid, "Buy milk today"))
        self.b.write(t, devices.vtodo(uid, "Buy milk and bread"))
        self.a.sync()
        rep = self.b.sync()["collections"]["tasks"]
        self.assertEqual((rep["merged"], rep["kept_both"]), ([t], []))
        self.a.sync()
        self.assertEqual(self.a.files(), self.b.files())
        self.assertEqual(len([k for k in self.b.files() if k.endswith(".ics")]), 1)
        self.assertIn("SUMMARY:Buy milk today\r\n", self.b.read(t))
        self.assertIn("Title: Buy milk and bread", self.b.read(t))

    def test_offline_edits_on_both_meet(self):
        self.a.add("home", "Seed")
        self.join_both()
        a_new = [self.a.add("home", "From a %d" % i) for i in range(3)]
        b_new = [self.b.add("work", "From b %d" % i) for i in range(3)]
        self.a.sync()
        self.b.sync()
        self.a.sync()
        self.assertEqual(self.a.files(), self.b.files())
        for p in a_new + b_new:
            self.assertIn(p, self.a.files())

    def test_second_device_with_its_own_tasks_merges_without_deleting(self):
        same = self.a.add("home", "Same on both", uid="same")
        self.b.add("home", "Same on both", uid="same")
        self.a.add("home", "Differs", uid="differs")
        self.b.write("home/differs.ics", devices.vtodo("differs", "Differs, b's way"))
        only_b = self.b.add("work", "Only on b")
        self.join_both()
        rep = self.b.status()["collections"]["tasks"]
        self.assertTrue(rep["fresh"])
        self.assertEqual(rep["kept_both"], ["home/differs.ics"])
        self.a.sync()
        self.assertEqual(self.a.files(), self.b.files())
        self.assertIn(same, self.a.files())
        self.assertIn(only_b, self.a.files())
        self.assertEqual(sum("Differs" in v for v in self.a.files().values()), 2)

    def test_hidden_and_stray_files_stay_here(self):
        self.a.add("home", "Task")
        self.a.write("home/.task.ics.tmp", "half written")
        self.a.write("loose.txt", "not in a list")
        self.join_both()
        self.assertNotIn("home/.task.ics.tmp", self.b.files())
        self.assertNotIn("loose.txt", self.b.files())

    def test_missing_folder_deletes_nothing_on_the_hub(self):
        for i in range(3):
            self.a.add("home", "Task %d" % i)
        self.join_both()
        os.rename(self.a.tasks, self.a.tasks + "-moved")
        self.b.add("home", "Added on b meanwhile")
        self.b.sync()
        rep = self.a.sync()["collections"]["tasks"]
        self.assertTrue(rep["missing"])
        self.assertEqual((rep["held_deletes"], rep["deleted_there"]), (4, 0))     # 3 tasks and displayname
        self.assertFalse(os.path.exists(self.a.tasks))      # not made again with only b's new task in it
        self.b.sync()
        self.assertEqual(len([k for k in self.b.files() if k.endswith(".ics")]), 4)

    def test_many_deletions_held_unless_allowed(self):
        tasks = [self.a.add("home", "Task %d" % i) for i in range(30)]
        self.join_both()
        for t in tasks[:25]:
            self.a.remove(t)
        rep = self.a.sync()["collections"]["tasks"]
        self.assertEqual((rep["held_deletes"], rep["deleted_there"]), (25, 0))
        self.assertEqual(self.a.status()["pending"]["tasks"]["deleted"], 25)
        rep = self.a.sync("--allow-deletes")["collections"]["tasks"]
        self.assertEqual(rep["deleted_there"], 25)
        self.b.sync()
        self.assertEqual(len(self.b.trashed()), 25)

    def test_out_of_reach_waits(self):
        t = self.a.add("home", "Task")
        self.a.run("join", self.url)
        self.a.write(t, devices.vtodo(t[5:-4], "Edited offline"))
        self.stop_hub()
        self.stop_hub = lambda: None
        st = self.a.sync()
        self.assertEqual(st["state"], "offline")
        self.assertEqual(self.a.run("sync", "--quiet").stdout, "")
        status = self.a.status()
        self.assertEqual(status["pending"]["tasks"], {"changed": 1, "deleted": 0})
        self.assertIsNotNone(status["last_ok"])


class MemoryHubTest(Scenarios, unittest.TestCase):
    def start_hub(self):
        self.hub = testhub.TestHub()
        return self.hub.url, self.hub.stop

    def test_a_new_hub_is_seeded_and_nothing_is_deleted(self):
        t = self.a.add("home", "Task")
        self.join_both()
        self.b.remove(t)        # deleted on b while the Hub is replaced: a fresh start must not spread that
        old = self.hub
        self.hub = testhub.TestHub()
        self.url, self.stop_hub = self.hub.url, self.hub.stop
        old.stop()
        for d in (self.a, self.b):
            d.run("join", self.url)
        self.assertTrue(self.a.status()["collections"]["tasks"]["fresh"])
        self.assertIn(t, self.hub.live())
        self.assertIn(t, self.b.files())        # came back: a fresh start adds, never deletes

    def test_a_name_the_hub_refuses_is_kept_and_said(self):
        self.a.add("home", "Task", name="odd")
        self.hub.mem.refuse.add("home/odd.ics")
        self.a.run("join", self.url)
        rep = self.a.status()["collections"]["tasks"]
        self.assertEqual(rep["skipped"], {"home/odd.ics": "bad_name"})
        self.assertIsNotNone(self.a.read("home/odd.ics"))

    def test_changes_in_pages(self):
        self.hub.mem.page = 3
        for i in range(10):
            self.a.add("home", "Task %d" % i)
        self.join_both()
        self.assertEqual(self.a.files(), self.b.files())


if __name__ == "__main__":
    unittest.main()
