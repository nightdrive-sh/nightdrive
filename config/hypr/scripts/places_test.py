#!/usr/bin/env python3
"""Places (#3276): `python3 config/hypr/scripts/places_test.py`. The file is read as it is and written back keeping
what isn't ours, mode 600; names match in any case and can't be taken twice; one SSID may be in two places; the
command's --json answers; show and put give back exactly what was there. A throwaway HOME, and the Wi-Fi now comes
from NIGHTDRIVE_PLACES_WIFI, never nmcli."""

import json
import os
import stat
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.dont_write_bytecode = True
import places  # noqa: E402

CMD = os.path.join(HERE, "places")


class Base(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.env = {"HOME": self.tmp.name, "PATH": os.environ.get("PATH", "/usr/bin:/bin"),
                    places.WIFI_ENV: "Feature"}
        self.old = {k: os.environ.get(k) for k in self.env}
        os.environ.update(self.env)
        self.file = places.path()

    def tearDown(self):
        for k, v in self.old.items():
            if v is None:
                os.environ.pop(k, None)
            else:
                os.environ[k] = v
        self.tmp.cleanup()

    def write(self, data):
        os.makedirs(os.path.dirname(self.file), exist_ok=True)
        with open(self.file, "w") as f:
            json.dump(data, f)

    def read(self):
        with open(self.file) as f:
            return json.load(f)

    def run_cmd(self, *args, wifi="Feature", ok=True):
        env = dict(self.env, **{places.WIFI_ENV: wifi})
        p = subprocess.run([sys.executable, CMD, *args], capture_output=True, text=True, env=env)
        if ok:
            self.assertEqual(p.returncode, 0, p.stderr)
        return p


class Library(Base):
    def test_reads_the_file_saved_on_19_11_as_it_is(self):
        self.write({"places": [{"name": "work", "wifi": ["Feature"]}]})
        self.assertEqual(places.load(), [{"name": "work", "wifi": ["Feature"]}])

    def test_missing_or_broken_file_is_no_places(self):
        self.assertEqual(places.load(), [])
        os.makedirs(os.path.dirname(self.file))
        with open(self.file, "w") as f:
            f.write("{nope")
        self.assertEqual(places.load(), [])

    def test_slips_in_a_hand_edit_are_dropped_not_fatal(self):
        self.write({"places": [{"name": "work", "wifi": "Feature"}, {"wifi": ["x"]}, "home", {"name": " "}]})
        self.assertEqual(places.load(), [{"name": "work", "wifi": []}])

    def test_write_keeps_unknown_keys_and_is_private(self):
        self.write({"version": 2, "places": [{"name": "work", "wifi": ["Feature"], "wired": ["dock"]}]})
        with places.editing() as rows:
            places.add(rows, "home", ["Koti"])
        data = self.read()
        self.assertEqual(data["version"], 2)
        self.assertEqual(data["places"][0]["wired"], ["dock"])
        self.assertEqual(stat.S_IMODE(os.stat(self.file).st_mode), 0o600)

    def test_unchanged_is_not_written(self):
        self.write({"places": [{"name": "work", "wifi": ["Feature"]}]})
        before = os.stat(self.file).st_mtime_ns
        with places.editing() as rows:
            places.add(rows, "WORK", ["Feature"])
        self.assertEqual(os.stat(self.file).st_mtime_ns, before)

    def test_names_match_in_any_case_and_are_not_taken_twice(self):
        rows = [{"name": "Work", "wifi": ["Feature"]}]
        place, added, created, _ = places.add(rows, "work", ["Guest"])
        self.assertFalse(created)
        self.assertEqual(len(rows), 1)
        self.assertEqual(place, {"name": "Work", "wifi": ["Feature", "Guest"]})
        self.assertEqual(added, ["Guest"])

    def test_one_ssid_in_two_places_is_allowed_and_told(self):
        rows = [{"name": "office", "wifi": ["eduroam"]}]
        _, _, created, shared = places.add(rows, "campus", ["eduroam"])
        self.assertTrue(created)
        self.assertEqual(shared, {"eduroam": ["office"]})
        self.assertEqual([r["name"] for r in places.here(rows, ["eduroam"])], ["office", "campus"])

    def test_bad_names_and_ssids(self):
        for name in ("", "  ", "-rf", "a" * 41, "tab\there"):
            with self.assertRaises(places.PlaceError, msg=name):
                places.check_name(name)
        for ssid in ("", "x" * 33, "ä" * 17, "new\nline"):
            with self.assertRaises(places.PlaceError, msg=ssid):
                places.check_ssid(ssid)
        self.assertEqual(places.check_ssid("x" * 32), "x" * 32)

    def test_add_without_wifi_says_so(self):
        with self.assertRaisesRegex(places.PlaceError, "isn't on Wi-Fi"):
            places.add([], "work", [])

    def test_unknown_place_lists_the_places(self):
        with self.assertRaisesRegex(places.PlaceError, "The places: work.*places add"):
            places.remove([{"name": "work", "wifi": []}], "home")

    def test_forget_keeps_the_place(self):
        rows = [{"name": "work", "wifi": ["Feature"]}]
        self.assertEqual(places.forget(rows, "Work", "Feature"), {"name": "work", "wifi": []})
        with self.assertRaisesRegex(places.PlaceError, "has no network"):
            places.forget(rows, "work", "Feature")

    def test_snapshot_and_put_restore_exactly(self):
        rows = [{"name": "work", "wifi": ["Feature"], "wired": ["dock"]}]
        snap = places.snapshot(rows, "WORK")
        self.assertEqual(snap["name"], "work")
        places.remove(rows, "work")
        places.put(rows, snap["name"], json.loads(snap["previous"]))
        self.assertEqual(rows, [{"name": "work", "wifi": ["Feature"], "wired": ["dock"]}])
        snap = places.snapshot(rows, "home")
        self.assertEqual(snap, {"name": "home", "previous": "null"})
        places.add(rows, "home", ["Koti"])
        places.put(rows, snap["name"], None)
        self.assertEqual([r["name"] for r in rows], ["work"])

    def test_nmcli_escapes(self):
        self.assertEqual(places._nmcli_fields(r"yes:Cafe\:Guest"), ["yes", "Cafe:Guest"])
        self.assertEqual(places._nmcli_fields(r"no:back\\slash"), ["no", "back\\slash"])


class Command(Base):
    def json(self, *args, **kw):
        return json.loads(self.run_cmd(*args, "--json", **kw).stdout)

    def test_list_and_here(self):
        self.write({"places": [{"name": "work", "wifi": ["Feature"]}, {"name": "home", "wifi": ["Koti"]}]})
        self.assertEqual(self.json("list"), {"places": [{"name": "work", "wifi": ["Feature"], "here": True},
                                                        {"name": "home", "wifi": ["Koti"], "here": False}],
                                             "wifi": ["Feature"]})
        self.assertEqual(self.json("here", wifi="Koti"), {"wifi": ["Koti"], "places": ["home"]})
        self.assertEqual(self.json("here", wifi=""), {"wifi": [], "places": []})
        self.assertEqual(self.run_cmd("here", wifi="").stdout.strip(), "Not on Wi-Fi")
        self.assertIn("work: Feature  (here)", self.run_cmd().stdout)

    def test_add_takes_the_wifi_now(self):
        out = self.json("add", "work")
        self.assertEqual((out["name"], out["wifi"], out["created"], out["added"]), ("work", ["Feature"], True, ["Feature"]))
        self.assertEqual(self.read(), {"places": [{"name": "work", "wifi": ["Feature"]}]})
        p = self.run_cmd("add", "home", wifi="", ok=False)
        self.assertEqual(p.returncode, 1)
        self.assertIn("isn't on Wi-Fi", p.stderr)

    def test_add_given_networks_after_dashes(self):
        out = self.json("add", "--", "cottage", "Mökki", "Mökki 5G")
        self.assertEqual(out["wifi"], ["Mökki", "Mökki 5G"])

    def test_remove_and_forget(self):
        self.write({"places": [{"name": "work", "wifi": ["Feature", "Guest"]}]})
        self.assertEqual(self.json("forget", "work", "Guest")["place"]["wifi"], ["Feature"])
        self.assertEqual(self.json("remove", "WORK"), {"name": "work", "removed": {"name": "work", "wifi": ["Feature"]}})
        p = self.run_cmd("remove", "work", ok=False)
        self.assertEqual(p.returncode, 1)
        self.assertIn("No place called", p.stderr)

    def test_show_then_put_is_the_undo(self):
        self.write({"places": [{"name": "work", "wifi": ["Feature"]}]})
        snap = json.loads(self.run_cmd("show", "work").stdout)
        self.run_cmd("remove", "work")
        self.run_cmd("put", "--", snap["name"], snap["previous"])
        self.assertEqual(self.read()["places"], [{"name": "work", "wifi": ["Feature"]}])
        snap = json.loads(self.run_cmd("show", "home").stdout)
        self.run_cmd("add", "home", "Koti")
        self.run_cmd("put", "--", snap["name"], snap["previous"])
        self.assertEqual([p["name"] for p in self.read()["places"]], ["work"])

    def test_usage(self):
        self.assertEqual(self.run_cmd("remove", ok=False).returncode, 2)
        self.assertEqual(self.run_cmd("nope", ok=False).returncode, 2)


if __name__ == "__main__":
    unittest.main()
