#!/usr/bin/env python3
"""Claude's arguments checked before anything runs (#1862): `python3 config/mcp/check_test.py`. run.check keeps the
schema's limits; software's ids, Deck's uris, a calendar uid and a display's scale are refused before the command
they would reach, which here is a stand-in in PATH that leaves a mark when it runs."""

import json
import os
import stat
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
SCRIPTS = HERE.parent / "hypr/scripts"
sys.path.insert(0, str(HERE))

import registry  # noqa: E402
import run  # noqa: E402
from run import ToolError  # noqa: E402

SCHEMA = {"type": "object", "additionalProperties": False, "properties": {
    "query": {"type": "string", "minLength": 2, "maxLength": 10},
    "uri": {"type": "string", "pattern": "^spotify:album:"},
    "n": {"type": "integer", "minimum": 1, "maximum": 100},
    "paths": {"type": "array", "minItems": 1, "maxItems": 3, "items": {"type": "string", "minLength": 1}},
}}


def tool(schema=SCHEMA):
    return SimpleNamespace(name="t", spec={"inputSchema": schema})


class Check(unittest.TestCase):
    def refused(self, args, words):
        with self.assertRaises(ToolError) as e:
            run.check(tool(), args)
        self.assertIn(words, str(e.exception))

    def test_limits(self):
        self.refused({"query": "x"}, "at least 2 characters")
        self.refused({"query": "x" * 11}, "at most 10 characters")
        self.refused({"uri": "--help"}, "must match")
        self.refused({"uri": "x spotify:album:1"}, "must match")
        self.refused({"n": -5}, "at least 1")
        self.refused({"n": 101}, "at most 100")
        self.refused({"n": 100.5}, "must be integer")
        self.refused({"n": True}, "must be integer")
        self.refused({"paths": []}, "at least 1 item")
        self.refused({"paths": ["a", "b", "c", "d"]}, "at most 3 items")
        self.refused({"paths": ["a", ""]}, "each of paths must be at least 1 characters")
        self.refused({"paths": ["a", 3]}, "each of paths must be string")
        run.check(tool(), {"query": "ab", "uri": "spotify:album:1", "n": 1, "paths": ["a"]})
        run.check(tool(), {"n": 100})

    def test_broken_pattern_refuses(self):
        broken = {"type": "object", "properties": {"q": {"type": "string", "pattern": "("}}}
        with self.assertRaises(ToolError):
            run.check(tool(broken), {"q": "x"})

    def test_registry_leaves_out_broken_limits(self):
        base = {"name": "t", "description": "d", "command": ["true"], "class": "read", "area": "nightdrive"}
        for prop in ({"type": "string", "minLength": "2"}, {"type": "string", "pattern": "("},
                     {"type": "integer", "maximum": True}, {"type": "array", "items": {"minLength": None}}):
            spec = {**base, "inputSchema": {"type": "object", "properties": {"x": prop}}}
            self.assertIsNotNone(registry.problem(spec, None), prop)
        self.assertIsNone(registry.problem({**base, "inputSchema": SCHEMA}, None))

    def test_every_tool_keeps_its_limits(self):
        """The tools as shipped: none left out by the new checks."""
        tools, problems = registry.Registry(active="/nonexistent").load()
        self.assertFalse([p for p in problems if "must be a number" in p or "regular expression" in p])
        self.assertIn("contacts_find", {t.name for t in read_plugin("contacts")})


def read_plugin(pid):
    return registry.read_file(REPO / "plugins" / pid / "mcp.json", REPO / "plugins" / pid, pid)[0]


class StandIns(unittest.TestCase):
    """Commands in a PATH of their own that only leave a mark: what reached them."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = Path(self.tmp.name)
        self.bin = self.dir / "bin"
        self.bin.mkdir()
        self.marks = self.dir / "marks"
        self.env = {**os.environ, "PATH": f"{self.bin}:/usr/bin:/bin", "HOME": str(self.dir),
                    "NIGHTDRIVE_MCP": "1", "NIGHTDRIVE_MCP_OPTIONS": "{}"}

    def tearDown(self):
        self.tmp.cleanup()

    def stand_in(self, name, body=""):
        f = self.bin / name
        f.write_text(f'#!/bin/bash\necho "{name} $*" >> {self.marks}\n{body}\n')
        f.chmod(f.stat().st_mode | stat.S_IEXEC)

    def ran(self):
        return self.marks.read_text() if self.marks.exists() else ""

    def run_(self, *argv):
        return subprocess.run(argv, capture_output=True, text=True, env=self.env, stdin=subprocess.DEVNULL)


class Software(StandIns):
    HOSTILE_DNF = ["https://evil.example/x.rpm", "./x.rpm", "x.rpm", "/tmp/x", "-y", "--help", "*", "@core",
                   "a b", "fo\no", ""]
    HOSTILE_FLATPAK = ["--system", "-a", "org/evil", "https://x", "org.x App", ""]

    def setUp(self):
        super().setUp()
        for name in ("dnf", "flatpak", "rpm", "pkexec"):
            self.stand_in(name, "exit 1")

    def test_apply_refuses_before_dnf(self):
        for ident in self.HOSTILE_DNF:
            for argv in (["preview", "install", "dnf", ident], ["install", "dnf", ident, "--check"],
                         ["remove", "dnf", ident, "--card"]):
                p = self.run_(str(SCRIPTS / "software-apply"), *argv)
                self.assertNotEqual(p.returncode, 0, argv)
        self.assertEqual(self.ran(), "")

    def test_apply_refuses_before_flatpak(self):
        for ident in self.HOSTILE_FLATPAK:
            p = self.run_(str(SCRIPTS / "software-apply"), "preview", "install", "flatpak", ident)
            self.assertNotEqual(p.returncode, 0, ident)
        self.assertEqual(self.ran(), "")

    def test_a_name_still_goes_to_dnf_after_dashes(self):
        self.run_(str(SCRIPTS / "software-apply"), "preview", "install", "dnf", "gcc-c++")
        self.assertIn("dnf install --assumeno -- gcc-c++", self.ran())
        self.run_(str(SCRIPTS / "software-apply"), "preview", "remove", "flatpak", "org.gimp.GIMP")
        self.assertIn("flatpak info --user -- org.gimp.GIMP", self.ran())

    def test_pkg_info(self):
        for source, ident in [("dnf", i) for i in self.HOSTILE_DNF] + [("flatpak", i) for i in self.HOSTILE_FLATPAK]:
            self.assertNotEqual(self.run_(str(SCRIPTS / "pkg-info"), source, ident).returncode, 0, ident)
        self.assertEqual(self.ran(), "")
        self.run_(str(SCRIPTS / "pkg-info"), "dnf", "bash")
        self.assertIn("rpm -q -- bash", self.ran())

    def test_group_members_are_protected(self):
        self.stand_in("dnf", 'printf "%s\\n" "Id                   : hardware-support" '
                             '"Mandatory packages   : must-have" "Default packages     : qrtr" '
                             '"                     : usb_modeswitch" "Optional packages    : gpsd"')
        p = self.run_(str(SCRIPTS / "software-claude"))
        names = p.stdout.split()
        for name in ("must-have", "qrtr", "usb_modeswitch"):
            self.assertIn(name, names)
        self.assertNotIn("gpsd", names)
        self.assertNotIn("@hardware-support", names)
        self.assertIn("dnf -q group info -- hardware-support", self.ran())


class Display(StandIns):
    MONITORS = [{"name": "eDP-1", "description": "", "width": 3024, "height": 1964, "scale": 2,
                 "availableModes": ["3024x1964@60.00Hz"]}]

    def setUp(self):
        super().setUp()
        (self.dir / "monitors.json").write_text(json.dumps(self.MONITORS))
        self.stand_in("hyprctl", f'[[ $1 == -j ]] && cat {self.dir}/monitors.json; true')
        state = self.dir / ".local/state/nightdrive"
        state.mkdir(parents=True)
        (state / "display").write_text("eDP-1 2\n")

    def scale(self, value, *more):
        return self.run_(str(SCRIPTS / "display"), "scale", "eDP-1", value, *more)

    def test_claude_gets_only_the_listed_scales(self):
        for value in ("0.1", "100", "1.1", "1.33", "3"):
            p = self.scale(value, "--keep")
            self.assertEqual(p.returncode, 1, value)
            self.assertIn("doesn't take the scale", p.stderr)
        self.assertNotIn("hyprctl reload", self.ran())
        self.assertEqual(self.scale("2", "--keep").returncode, 0)      # as saved: no card to keep it
        self.assertEqual(self.scale("2.0", "--keep").returncode, 0)

    def test_the_revert_sets_back_anything(self):
        self.assertEqual(self.scale("1.1").returncode, 0)
        self.assertIn("hyprctl reload", self.ran())


class Deck(StandIns):
    def test_uris_before_deck(self):
        self.stand_in("deck", "exit 1")
        playback = REPO / "plugins/deck/lib/playback.py"
        for argv in (["play-album", "--help"], ["play-album", "spotify:track:abc"], ["queue-album", "spotify:album:a b"],
                     ["play-song", "--version", "spotify:album:abc"], ["queue-song", "spotify:track:a", "-x"],
                     ["play-album", "spotify:album:abc\n"], ["play-song", "spotify:track:a", "spotify:track:b"]):
            p = self.run_(sys.executable, str(playback), *argv)
            self.assertEqual(p.returncode, 1, argv)
            self.assertIn("uri", p.stderr)
        self.assertEqual(self.ran(), "")
        self.run_(sys.executable, str(playback), "play-album", "spotify:album:4aawyAB9vmqN3uQ7FjRGTy")
        self.assertIn("deck status --json", self.ran())   # past the check: Deck is asked


class Calendar(unittest.TestCase):
    def test_uid_never_names_a_file_elsewhere(self):
        sys.path.insert(0, str(REPO / "plugins/calendar/lib"))
        try:
            import write
        except ImportError as e:
            self.skipTest(f"calendar's libraries: {e}")
        with tempfile.TemporaryDirectory() as d:
            folder = Path(d) / "cal"
            folder.mkdir()
            (Path(d) / "outside.ics").write_text("UID:outside\n")
            (folder / ".hidden.ics").write_text("UID:.hidden\n")
            (folder / "ok.ics").write_text("UID:ok\n")
            cal = {"path": str(folder)}
            for uid in ("../outside", ".hidden", "a/b", "", "x\0y"):
                self.assertIsNone(write.event_file(cal, uid), uid)
            self.assertEqual(write.event_file(cal, "ok"), folder / "ok.ics")


if __name__ == "__main__":
    unittest.main()
