#!/usr/bin/env python3
"""Claude's places tools (#3276): `python3 config/hypr/scripts/places_mcp_test.py`. The three load in the Sound and
display area with the right classes; their argv, filled as the server fills it, is what `places` reads; the notice
has its values from the output; and an add's or a remove's undo (before's snapshot, then put) leaves the file as it
was. The `places` beside this file stands in for `nightdrive places`, with a throwaway HOME and the Wi-Fi from
NIGHTDRIVE_PLACES_WIFI."""

import json
import os
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
MCP = os.path.join(HERE, "..", "..", "mcp")
sys.path.insert(0, MCP)
sys.dont_write_bytecode = True
import registry  # noqa: E402
import run  # noqa: E402
import undo  # noqa: E402

CMD = os.path.join(HERE, "places")


def tools():
    found, problems = registry.read_file(os.path.join(MCP, "tools", "places.json"), MCP, None)
    assert not problems, problems
    return {t.name: t for t in found}


class Tools(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.home = self.tmp.name
        self.file = os.path.join(self.home, ".config", "nightdrive", "places.json")
        os.makedirs(os.path.dirname(self.file))
        with open(self.file, "w") as f:
            json.dump({"places": [{"name": "work", "wifi": ["Feature"]}]}, f)

    def tearDown(self):
        self.tmp.cleanup()

    def places(self, argv):
        """argv as the tool gives it, `nightdrive places …` run as this checkout's script."""
        self.assertEqual(argv[:2], ["nightdrive", "places"])
        env = {"HOME": self.home, "PATH": os.environ.get("PATH", "/usr/bin:/bin"), "NIGHTDRIVE_PLACES_WIFI": "Guest"}
        p = subprocess.run([sys.executable, CMD, *argv[2:]], capture_output=True, text=True, env=env)
        self.assertEqual(p.returncode, 0, p.stderr)
        return json.loads(p.stdout) if p.stdout.strip().startswith("{") else p.stdout

    def saved(self):
        with open(self.file) as f:
            return json.load(f)

    def change(self, name, arguments):
        """A change tool's call as the server makes it: before, the command, then its undo filled from before, the
        output and the arguments (undo.py's order). → (output, notice)."""
        tool = tools()[name]
        state = self.places(run.expand(tool.spec["before"], arguments))
        output = self.places(run.expand(tool.spec["command"], arguments))
        values = {**arguments, **output, **state}
        notice = undo.notice_text(tool, {**state, **arguments, **output})
        self.undo_argv = run.expand(tool.spec["undo"], values)
        return output, notice

    def test_all_three_load_in_sound_and_display(self):
        t = tools()
        self.assertEqual(sorted(t), ["places_add", "places_list", "places_remove"])
        self.assertEqual({n: (x.cls, x.spec["area"]) for n, x in t.items()},
                         {"places_add": ("change", "sound-display"), "places_list": ("read", "sound-display"),
                          "places_remove": ("change", "sound-display")})
        self.assertTrue(t["places_remove"].spec["deletes"])
        self.assertNotIn("mask", t["places_list"].spec)   # SSIDs are personal, not secret: network_status shows them too

    def test_list(self):
        out = self.places(run.expand(tools()["places_list"].spec["command"], {}))
        self.assertEqual(out, {"places": [{"name": "work", "wifi": ["Feature"], "here": False}], "wifi": ["Guest"]})

    def test_add_new_place_with_the_wifi_now_and_undo(self):
        out, notice = self.change("places_add", {"name": "Cafe"})
        self.assertEqual((out["name"], out["wifi"], out["created"]), ("Cafe", ["Guest"], True))
        self.assertEqual(notice, "Place Cafe: Guest")
        self.places(self.undo_argv)
        self.assertEqual(self.saved()["places"], [{"name": "work", "wifi": ["Feature"]}])

    def test_add_to_a_place_in_other_case_and_undo(self):
        out, notice = self.change("places_add", {"name": "WORK", "wifi": ["Feature 5G", "-dash"]})
        self.assertEqual(out["wifi"], ["Feature", "Feature 5G", "-dash"])
        self.assertEqual(notice, "Place work: Feature, Feature 5G, -dash")
        self.places(self.undo_argv)
        self.assertEqual(self.saved()["places"], [{"name": "work", "wifi": ["Feature"]}])

    def test_remove_and_undo(self):
        out, notice = self.change("places_remove", {"name": "Work"})
        self.assertEqual(notice, "Removed the place work")
        self.assertEqual(self.saved()["places"], [])
        self.places(self.undo_argv)
        self.assertEqual(self.saved()["places"], [{"name": "work", "wifi": ["Feature"]}])

    def test_a_name_like_an_option_stays_a_name(self):
        argv = run.expand(tools()["places_remove"].spec["command"], {"name": "-rf"})
        self.assertEqual(argv[-2:], ["--", "-rf"])


if __name__ == "__main__":
    unittest.main()
