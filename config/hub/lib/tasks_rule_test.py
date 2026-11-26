"""Tasks' rule (tasks_rule.py): the other side of a conflict as a task of its own that Tasks reads, a deleted task to
Tasks' trash, the rest to the state folder, and empty folders tidied.

    python3 config/hub/lib/tasks_rule_test.py
"""
import os
import sys
import tempfile
import unittest

HOME = tempfile.mkdtemp(prefix="hub-rule-")
# Before Tasks' store is imported: it reads where its folder is once
os.environ.update(XDG_DATA_HOME=os.path.join(HOME, "data"), XDG_STATE_HOME=os.path.join(HOME, "state"))
os.environ.pop("NIGHTDRIVE_TASKS_DIR", None)

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import apps  # noqa: E402
import devices  # noqa: E402
import tasks_rule  # noqa: E402
import store  # noqa: E402  (Tasks' own, on the path tasks_rule set)

ROOT = os.path.join(HOME, "data", "nightdrive", "tasks")


def put(rel, text):
    p = os.path.join(ROOT, rel)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p, "w", newline="") as f:
        f.write(text)


class TasksRuleTest(unittest.TestCase):
    def setUp(self):
        self.rule = tasks_rule.TasksRule()

    def test_root_is_tasks_own(self):
        self.assertEqual(self.rule.root(), ROOT)
        self.assertEqual(str(store.DATA), ROOT)

    def test_accepts_a_lists_files_only(self):
        self.assertTrue(self.rule.accept("home/x.ics"))
        self.assertTrue(self.rule.accept("home/displayname"))
        self.assertFalse(self.rule.accept("loose.ics"))
        self.assertFalse(self.rule.accept("home/deeper/x.ics"))

    def test_keep_both_makes_a_task_tasks_reads(self):
        put("home/abc.ics", devices.vtodo("abc", "Hub's side"))
        mine = devices.vtodo("abc", "My side", "DUE;VALUE=DATE:20261201\r\n").encode()
        new = self.rule.keep_both("home/abc.ics", mine)
        self.assertTrue(new.startswith("home/") and new.endswith(".ics"), new)
        self.assertNotEqual(new[5:7], "ab")         # its short id isn't the original's
        found = {t.get("UID"): t for _, _, t in store.load()}
        self.assertEqual(set(found), {"abc", new[5:-4]})
        copy = found[new[5:-4]]
        self.assertEqual(copy.get("SUMMARY"), "My side (%s)" % apps.host())
        self.assertEqual(copy.get("DUE"), "20261201")          # the rest of this side as it was
        # A second conflict on the same task doesn't overwrite the first copy
        again = self.rule.keep_both("home/abc.ics", mine)
        self.assertNotEqual(again, new)
        self.assertEqual(len({t.get("UID") for _, _, t in store.load()}), 3)

    def test_keep_both_of_a_broken_task_or_a_name_goes_to_state(self):
        self.assertIsNone(self.rule.keep_both("home/broken.ics", b"not a vtodo"))
        self.assertIsNone(self.rule.keep_both("home/displayname", b"Mine\n"))
        kept = os.listdir(os.path.join(HOME, "state", "nightdrive", "hub", "conflicts", "tasks", "home"))
        self.assertEqual(sorted(k.split(" (")[0] for k in kept), ["broken.ics", "displayname"])

    def test_put_away(self):
        put("trip/t.ics", devices.vtodo("t", "Pack"))
        put("trip/displayname", "Trip\n")
        self.rule.put_away("trip/t.ics")
        self.assertTrue(os.path.isfile(os.path.join(HOME, "state", "nightdrive", "tasks", "trash", "trip", "t.ics")))
        self.rule.put_away("trip/displayname")
        self.assertTrue(os.path.isfile(os.path.join(HOME, "state", "nightdrive", "hub", "trash", "tasks", "trip",
                                                    "displayname")))
        self.assertFalse(os.path.exists(os.path.join(ROOT, "trip")))     # the empty list's folder went too
        self.assertTrue(os.path.isdir(ROOT))                              # the root never


if __name__ == "__main__":
    try:
        unittest.main()
    finally:
        import shutil
        shutil.rmtree(HOME, ignore_errors=True)
