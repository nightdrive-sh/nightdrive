"""The Hub's requests (client.py) against the in-memory Hub (testhub.py): 409 with the Hub's state, tombstones,
paging, names in URLs, another Hub at the address, and a Hub out of reach.

    python3 config/hub/lib/client_test.py
"""
import os
import socket
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import client as hc  # noqa: E402
import manifest as mf  # noqa: E402
import testhub  # noqa: E402


def h(b):
    return mf.data_hash(b)


class ClientTest(unittest.TestCase):
    def setUp(self):
        self.hub = testhub.TestHub()
        self.c = hc.Client(self.hub.url)

    def tearDown(self):
        self.c.close()
        self.hub.stop()

    def test_info(self):
        self.assertEqual(self.c.info()["server"], self.hub.mem.server_id)

    def test_write_conflict_and_read(self):
        r = self.c.put("tasks", "l/a.ics", b"one", 0, h(b"one"))
        self.assertEqual((r["version"], r["changed"]), (1, True))
        self.c.put("tasks", "l/a.ics", b"two", 1, h(b"two"))
        with self.assertRaises(hc.Conflict) as e:
            self.c.put("tasks", "l/a.ics", b"three", 1, h(b"three"))
        st = e.exception.state
        self.assertEqual((st.version, st.hash, st.deleted, st.body), (2, h(b"two"), False, b"two"))
        got = self.c.get("tasks", "l/a.ics")
        self.assertEqual((got.version, got.body), (2, b"two"))

    def test_tombstone(self):
        self.c.put("tasks", "l/a.ics", b"one", 0, h(b"one"))
        self.assertEqual(self.c.delete("tasks", "l/a.ics", 1)["version"], 2)
        st = self.c.get("tasks", "l/a.ics")
        self.assertEqual((st.version, st.deleted), (2, True))
        self.assertIsNone(self.c.delete("tasks", "l/none.ics", 0))
        self.assertEqual(self.c.get("tasks", "l/none.ics").version, 0)

    def test_changes_in_pages(self):
        self.hub.mem.page = 2
        for i in range(5):
            self.c.put("tasks", "l/%d.ics" % i, b"x%d" % i, 0, h(b"x%d" % i))
        pages = list(self.c.changes("tasks", 0))
        self.assertEqual([len(p) for p, _ in pages], [2, 2, 1])
        self.assertEqual(pages[-1][1], 5)
        self.assertEqual(list(self.c.changes("tasks", 5)), [([], 5)])

    def test_names_escaped(self):
        name = "Koti ja #1/ä %20?.ics"
        self.c.put("tasks", name, b"x", 0, h(b"x"))
        self.assertIn(name, self.hub.live())
        self.assertEqual(self.c.get("tasks", name).body, b"x")

    def test_another_hub_at_the_address(self):
        self.c.server = "not-this-one"
        with self.assertRaises(hc.ServerChanged):
            self.c.info()

    def test_out_of_reach(self):
        s = socket.socket()
        s.bind(("127.0.0.1", 0))
        port = s.getsockname()[1]
        s.close()       # a port nobody listens on: refused
        with self.assertRaises(hc.Offline):
            hc.Client("http://127.0.0.1:%d" % port).info()

    def test_bad_address(self):
        with self.assertRaises(ValueError):
            hc.Client("hub.example")


if __name__ == "__main__":
    unittest.main()
