#!/usr/bin/env python3
"""Small gaps from the threat scenarios (#1887): `python3 config/mcp/small_gaps_test.py`.

- asks_if: a change tool's call asks on the card though Access allows it when its command says yes (sound to a speaker
  on the network, an event into a shared calendar), and one that fails or says anything else stops the call.
- display … --keep: the new scale is on trial in the runtime dir until the user keeps it, so a restart finds the old
  one; Keep saves it, anything else puts the old one back. hyprland.lua reads the trial over the saved value.
- The card's list rows: an entry with a line end in it stays one entry.
- Schemas: Deck's ids and uris are Spotify's form, the bar's icons stay visible.
- Ferry's card names the device Ferry would pick; a calendar marked shared says so.
Commands run against stand-ins in PATH (hyprctl, qs, ferry) in homes of their own."""

import hashlib
import json
import os
import re
import stat
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest import mock

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
SCRIPTS = HERE.parent / "hypr/scripts"
sys.path.insert(0, str(HERE))

import access  # noqa: E402
import confirm  # noqa: E402
import registry  # noqa: E402
import run  # noqa: E402
from run import ToolError  # noqa: E402


def stub(path, text):
    path.write_text(text)
    path.chmod(path.stat().st_mode | stat.S_IXUSR)


def tool_spec(path, name):
    return next(t for t in json.loads(Path(path).read_text())["tools"] if t["name"] == name)


# --- asks_if --------------------------------------------------------------------------------------------------------

class AsksIf(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = Path(self.tmp.name)
        self.says = self.dir / "says"
        stub(self.dir / "asks", f"#!/bin/sh\necho \"$@\" >> {self.dir}/asked\ncat {self.says}\n")
        stub(self.dir / "act", f"#!/bin/sh\necho done >> {self.dir}/ran\necho '{{}}'\n")
        stub(self.dir / "fails", "#!/bin/sh\necho 'No output named x' >&2\nexit 1\n")
        spec = {"name": "t_out", "title": "Out", "description": "x", "class": "change", "area": "sound-display",
                "inputSchema": {"type": "object", "properties": {"output": {"type": "string"}},
                                "required": ["output"], "additionalProperties": False},
                "command": ["./act"], "undo": ["./act"], "asks_if": ["./asks", "{output}"]}
        self.tool = registry.Tool(spec, self.dir, "test")
        self.reg = registry.Registry(core=self.dir / "none", active=self.dir / "none", access_file=self.dir / "a.json")
        self.reg.visible = lambda: {"t_out": self.tool}
        self.reg.rules = access.Access("open")
        self.reg.undo = None
        self.cards = []
        self.reg.confirm = SimpleNamespace(ask=lambda t, a: self.cards.append(a) or self.allow)
        self.allow = True

    def tearDown(self):
        self.tmp.cleanup()

    def call(self, said, output="raop_sink.x"):
        self.says.write_text(said)
        return self.reg.call("t_out", {"output": output})

    def test_yes_asks_and_runs_when_allowed(self):
        self.call("yes\n")
        self.assertEqual(self.cards, [{"output": "raop_sink.x"}])
        self.assertTrue((self.dir / "ran").exists())

    def test_yes_and_denied_runs_nothing(self):
        self.allow = False
        with self.assertRaises(ToolError):
            self.call("yes")
        self.assertFalse((self.dir / "ran").exists())

    def test_no_runs_without_the_card(self):
        self.call("no")
        self.assertEqual(self.cards, [])
        self.assertTrue((self.dir / "ran").exists())

    def test_anything_else_stops_the_call(self):
        for said in ("", "yes please", "YES", "true", "no\nyes"):
            with self.subTest(said=said), self.assertRaises(ToolError) as e:
                self.call(said)
            self.assertIn("didn't say yes, no or first KEY", str(e.exception))
        self.assertFalse((self.dir / "ran").exists())

    def test_a_failing_command_stops_the_call_with_its_message(self):
        self.tool.spec["asks_if"] = ["./fails"]
        with self.assertRaises(ToolError) as e:
            self.call("no")
        self.assertIn("No output named x", str(e.exception))
        self.assertFalse((self.dir / "ran").exists())

    def test_the_argument_is_one_element(self):
        self.call("no", output="a; touch /tmp/x --b")
        self.assertEqual((self.dir / "asked").read_text(), "a; touch /tmp/x --b\n")

    def test_ask_level_asks_without_the_command(self):
        self.reg.rules = access.Access("open", {"sound-display": {"modify": "ask"}})
        self.call("no")
        self.assertEqual(len(self.cards), 1)

    def test_format(self):
        spec = dict(self.tool.spec)
        self.assertIsNone(registry.problem(spec, None))
        for bad in ({"asks_if": "./asks"}, {"asks_if": ["./asks", "{nothing}"]}, {"class": "read", "asks_if": ["x"]}):   # an act tool's may say first KEY (#1981)
            with self.subTest(bad=bad):
                self.assertIsNotNone(registry.problem({**spec, **bad}, None))

    def test_the_real_tools_pass(self):
        for path, name in ((REPO / "config/mcp/tools/sound-display.json", "sound_output"),
                           (REPO / "plugins/calendar/mcp.json", "calendar_add")):
            spec = tool_spec(path, name)
            self.assertIn("asks_if", spec)
            self.assertIsNone(registry.problem(spec, "calendar" if "calendar" in name else None), name)


# --- the sound output and the calendar ------------------------------------------------------------------------------

PW_DUMP = [
    {"type": "PipeWire:Interface:Metadata", "metadata": [{"key": "default.audio.sink", "value": {"name": "alsa_out"}}]},
    {"id": 40, "type": "PipeWire:Interface:Node", "info": {"props": {"media.class": "Audio/Sink",
                                                                      "node.name": "alsa_out", "node.description": "Speakers"}}},
    {"id": 41, "type": "PipeWire:Interface:Node", "info": {"props": {
        "media.class": "Audio/Sink", "node.name": "raop_sink.Olohuone.local.10.0.0.5.7000", "node.description": "Olohuone",
        "node.network": True}}},
    {"id": 42, "type": "PipeWire:Interface:Node", "info": {"props": {"media.class": "Audio/Sink",
                                                                      "node.name": "roc-sink", "node.description": "Kitchen"}}},
]


class Sound(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        b = Path(self.tmp.name)
        (b / "dump.json").write_text(json.dumps(PW_DUMP))
        stub(b / "pw-dump", f"#!/bin/sh\ncat {b}/dump.json\n")
        stub(b / "wpctl", "#!/bin/sh\necho 'Volume: 0.40'\n")
        self.env = {**os.environ, "PATH": f"{b}:{os.environ['PATH']}"}

    def tearDown(self):
        self.tmp.cleanup()

    def sound(self, *args):
        p = subprocess.run([str(SCRIPTS / "sound"), *args], env=self.env, capture_output=True, text=True, timeout=20)
        return p.returncode, p.stdout.strip()

    def test_remote(self):
        self.assertEqual(self.sound("remote", "raop_sink.Olohuone.local.10.0.0.5.7000"), (0, "yes"))
        self.assertEqual(self.sound("remote", "roc-sink"), (0, "yes"))   # by its name alone
        for name in ("alsa_out", "nothing", "--help", "raop_sink"):
            self.assertEqual(self.sound("remote", name), (0, "no"), name)
        self.assertEqual(self.sound("remote")[0], 1)

    def test_card(self):
        status, out = self.sound("card", "raop_sink.Olohuone.local.10.0.0.5.7000")
        self.assertEqual(json.loads(out)["Plays on"], "Olohuone")
        self.assertIn("On the network", json.loads(out)["Where"])
        self.assertEqual(json.loads(self.sound("card", "alsa_out")[1])["Where"], "This computer")


class SharedCalendar(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.home = Path(self.tmp.name)
        conf = self.home / ".config/calendar/calendars.conf"
        conf.parent.mkdir(parents=True)
        self.conf = conf
        for cal, name in (("fam", "Family"), ("me", "Mine"), ("work", "Work")):
            d = self.home / f".local/share/calendar/acct/{cal}"
            d.mkdir(parents=True)
            (d / "displayname").write_text(name)

    def tearDown(self):
        self.tmp.cleanup()

    def shared(self, *args, conf):
        self.conf.write_text("[account acct]\ntype = carddav\naddress = a@b.c\npassword-cmd = true\n"
                             f"caldav-url = https://dav.example/\n{conf}")
        env = {**os.environ, "HOME": str(self.home), "XDG_CONFIG_HOME": str(self.home / ".config"),
               "XDG_DATA_HOME": str(self.home / ".local/share")}
        p = subprocess.run([sys.executable, str(REPO / "plugins/calendar/lib/write.py"), "shared", *args], env=env,
                           capture_output=True, text=True, timeout=20)
        return p.returncode, p.stdout.strip(), p.stderr.strip()

    def test_marked_calendars(self):
        conf = "shared = Family, work\n"
        self.assertEqual(self.shared("--calendar", "Family", conf=conf)[:2], (0, "yes"))
        self.assertEqual(self.shared("--calendar", "acct/work", conf=conf)[:2], (0, "yes"))   # by id, any case
        # One not marked asks the first time (first_time_test.py, #1929)
        self.assertEqual(self.shared("--calendar", "Mine", conf=conf)[:2], (0, "first Mine (acct/me)"))
        self.assertEqual(self.shared("--calendar", "Mine", conf="shared = yes\n")[:2], (0, "yes"))
        self.assertEqual(self.shared("--calendar", "Family", conf="")[:2], (0, "first Family (acct/fam)"))

    def test_unknown_stops_with_adds_reason(self):
        status, _, err = self.shared("--calendar", "Nope; rm -rf ~", conf="shared = Family\n")
        self.assertEqual(status, 1)
        self.assertIn("No calendar 'Nope; rm -rf ~'", err)
        status, _, err = self.shared(conf="")   # three take events: which one
        self.assertIn("Which calendar?", err)


# --- display … --keep -----------------------------------------------------------------------------------------------

MONITORS = [{"name": "eDP-1", "description": "Panel", "width": 2560, "height": 1600, "scale": 2.0,
             "refreshRate": 60.0, "focused": True, "transform": 0, "availableModes": ["2560x1600@60.00Hz"]}]
QS = r'''#!/usr/bin/env python3
import hashlib, json, os, shutil, sys
d = os.environ["T"]
a = sys.argv[1:]
if a[:3] == ["ipc", "call", "claudeConfirm"]:
    op = a[3]
    if op == "open":
        data = open(a[4], "rb").read()
        # what is on disk while the card asks
        for name, path in (("display", os.environ["HOME"] + "/.local/state/nightdrive/display"),
                           ("display-trial", os.environ["XDG_RUNTIME_DIR"] + "/nightdrive/display-trial")):
            if os.path.exists(path):
                shutil.copy(path, os.path.join(d, "during-" + name))
        open(os.path.join(d, "request"), "wb").write(data)
        print("shown " + hashlib.md5(data).hexdigest())
    elif op == "answer":
        print(open(os.path.join(d, "answer")).read().strip())
'''


class DisplayTrial(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        t = Path(self.tmp.name)
        self.t, self.home, self.runtime = t, t / "home", t / "runtime"
        self.home.mkdir()
        self.runtime.mkdir(mode=0o700)
        b = t / "bin"
        b.mkdir()
        (t / "monitors.json").write_text(json.dumps(MONITORS))
        stub(b / "hyprctl", f"#!/bin/sh\n[ \"$1\" = -j ] && cat {t}/monitors.json || echo \"$@\" >> {t}/hyprctl\n")
        stub(b / "qs", QS)
        self.env = {**os.environ, "PATH": f"{b}:{os.environ['PATH']}", "HOME": str(self.home),
                    "XDG_RUNTIME_DIR": str(self.runtime), "T": str(t)}
        self.state = self.home / ".local/state/nightdrive/display"
        self.trial = self.runtime / "nightdrive/display-trial"
        self.state.parent.mkdir(parents=True)
        self.state.write_text("eDP-1 1.6\nbuiltin left\n")
        (self.home / ".config/hypr").mkdir(parents=True)   # as link.sh links it: the config that reads the trial
        (self.home / ".config/hypr/hyprland.lua").symlink_to(REPO / "config/hypr/hyprland.lua")

    def tearDown(self):
        self.tmp.cleanup()

    def scale(self, value, answer, keep=True):
        (self.t / "answer").write_text(answer)
        p = subprocess.run([str(SCRIPTS / "display"), "scale", "eDP-1", value, *(["--keep"] if keep else [])],
                           env=self.env, capture_output=True, text=True, timeout=60)
        return p.returncode, p.stdout, p.stderr

    def during(self, name):
        p = self.t / f"during-{name}"
        return p.read_text() if p.exists() else ""

    def test_on_trial_until_kept(self):
        status, out, err = self.scale("2", "allow")
        self.assertEqual(status, 0, err)
        self.assertEqual(json.loads(out)["kept"], True)
        # While the card asked: the saved value as it was, the new one on trial (a restart would find 1.6)
        self.assertEqual(self.during("display"), "eDP-1 1.6\nbuiltin left\n")
        self.assertEqual(self.during("display-trial"), "eDP-1 2\n")
        # Kept: saved, and nothing on trial
        self.assertEqual(sorted(self.state.read_text().split("\n")), ["", "builtin left", "eDP-1 2"])
        self.assertEqual(self.trial.read_text(), "")

    def test_not_kept_goes_back(self):
        status, out, err = self.scale("2", "deny")
        self.assertEqual(json.loads(out)["kept"], False)
        self.assertEqual(sorted(self.state.read_text().split("\n")), ["", "builtin left", "eDP-1 1.6"])
        self.assertEqual(self.trial.read_text(), "")

    def test_auto_on_trial(self):
        self.scale("auto", "allow")
        self.assertEqual(self.during("display-trial"), "eDP-1 auto\n")
        self.assertEqual(self.state.read_text(), "builtin left\n")

    def test_a_config_that_doesnt_read_the_trial_saves_at_once(self):
        (self.home / ".config/hypr/hyprland.lua").unlink()
        (self.home / ".config/hypr/hyprland.lua").write_text("-- an older one\n")
        status, out, err = self.scale("2", "deny")
        self.assertEqual(self.during("display"), "builtin left\neDP-1 2\n")   # the screen changes while asked
        self.assertEqual(self.during("display-trial"), "")
        self.assertIn("eDP-1 1.6", self.state.read_text())                   # and goes back

    def test_without_keep_saves_at_once(self):
        status, _, err = self.scale("2", "deny", keep=False)
        self.assertEqual(status, 0, err)
        self.assertIn("eDP-1 2", self.state.read_text())
        self.assertFalse((self.t / "request").exists())

    def test_hyprland_reads_the_trial_over_the_saved(self):
        lua = (REPO / "config/hypr/hyprland.lua").read_text()
        start = lua.index("local scales, modes, builtinSide")
        end = lua.index("trial:close()\nend\n") + len("trial:close()\nend\n")
        block = lua[start:end] + ('for k, v in pairs(scales) do print("scale", k, v) end\n'
                                  'for k, v in pairs(modes) do print("mode", k, v) end\n')
        self.state.write_text("eDP-1 1.6\nDP-2 1.25\nmode DP-2 3840x2160@60\nmode HDMI-A-1 1920x1080@120\n")
        self.trial.parent.mkdir(parents=True, exist_ok=True)
        self.trial.write_text("eDP-1 2\nDP-2 auto\nmode HDMI-A-1 auto\nbad line here\n")
        p = subprocess.run(["lua", "-e", f'HOME = "{self.home}"\n' + block], env=self.env, capture_output=True,
                           text=True, timeout=10)
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertEqual(sorted(p.stdout.splitlines()),
                         ["mode\tDP-2\t3840x2160@60", "scale\teDP-1\t2"])   # DP-2's scale and HDMI's mode: default


# --- the card, schemas ----------------------------------------------------------------------------------------------

class CardAndSchemas(unittest.TestCase):
    def test_a_line_end_in_an_entry_stays_one_entry(self):
        for value, want in ((["a@x.fi\nbcc@evil.fi", "c@y.fi"], "a@x.fi⟨U+000A⟩bcc@evil.fi\nc@y.fi"),
                            (["a\r\nb"], "a⟨U+000D⟩⟨U+000A⟩b"), (["a b"], "a⟨U+2028⟩b"),
                            ("one two", "one⟨U+2029⟩two"), (["x", 2], "x\n2")):
            row = confirm.field("to", {}, value)
            self.assertEqual(row["text"], want)
            self.assertEqual(row["lines"], want.count("\n") + 1)

    def test_deck_ids_are_spotifys(self):
        tools = {t["name"]: t for t in json.loads((REPO / "plugins/deck/mcp.json").read_text())["tools"]}
        cases = [("deck_artist_albums", "artist_id", "0UF7XLthtbSF2Eur7559oV",
                  ["x/../../me/player?", "0UF7XLthtbSF2Eur7559o", "0UF7XLthtbSF2Eur7559oV/", "0UF7XLthtbSF2Eur7559oV?a"]),
                 ("deck_album", "album_uri", "spotify:album:2Js9F9O6V6mDZTal95Iner",
                  ["spotify:album:../../me", "spotify:album:2Js9F9O6V6mDZTal95Iner/tracks", "spotify:album:"]),
                 ("deck_play_song", "track_uri", "spotify:track:0U0ldCRmgCqhVvD6ksG63j",
                  ["spotify:track:0U0ldCRmgCqhVvD6ksG63j\n", "spotify:track:x"])]
        for name, arg, good, bad in cases:
            tool = SimpleNamespace(name=name, spec=tools[name])
            other = {"album_uri": "spotify:album:2Js9F9O6V6mDZTal95Iner"} if name == "deck_play_song" else {}
            run.check(tool, {arg: good, **other})
            for value in bad:
                with self.subTest(name=name, value=value), self.assertRaises(ToolError):
                    run.check(tool, {arg: value, **other})

    def test_a_pattern_ends_where_the_text_does(self):
        for pattern, value, ok in (("^[a-z0-9][a-z0-9-]*$", "synthwave", True), ("^[a-z0-9][a-z0-9-]*$", "synthwave\n", False),
                                   ("^a[$]b$", "a$b", True), (r"^a\$$", "a$", True), (r"^a\$$", "a$\n", False),
                                   ("^spotify:album:", "spotify:album:x", True)):
            with self.subTest(pattern=pattern, value=value):
                self.assertEqual(run.beyond({"pattern": pattern}, value) is None, ok)

    def test_the_bar_stays_visible(self):
        tool = SimpleNamespace(name="appearance_bar_style",
                               spec=tool_spec(REPO / "config/mcp/tools/appearance.json", "appearance_bar_style"))
        run.check(tool, {"opacity": 0, "icon_opacity": 20})
        for low in (0, 5, 19):
            with self.assertRaises(ToolError):
                run.check(tool, {"opacity": 0, "icon_opacity": low})

    def test_flatpak_search_ends_its_options(self):
        text = (SCRIPTS / "pkg-search").read_text()
        self.assertRegex(text, r'"flatpak", "search", "--columns=[^"]*", "--", q\]')


class FerryDevice(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        b = Path(self.tmp.name)
        devices = [{"id": "macbook", "name": "Jari - MacBook", "kind": "computer", "online": False},
                   {"id": "iphone", "name": "iphone", "kind": "phone", "online": True},
                   {"id": "x", "name": "macbook", "kind": "phone", "online": True}]
        (b / "list.json").write_text(json.dumps({"devices": devices}))
        stub(b / "ferry", f"#!/bin/sh\ncat {b}/list.json\n")
        self.env = {**os.environ, "PATH": f"{b}:{os.environ['PATH']}"}

    def tearDown(self):
        self.tmp.cleanup()

    def card(self, want):
        p = subprocess.run([str(REPO / "plugins/ferry/device"), want], env=self.env, capture_output=True, text=True,
                           timeout=20, cwd=REPO / "plugins/ferry")
        return p.returncode, p.stdout.strip(), p.stderr.strip()

    def test_names_the_device_ferry_picks(self):
        self.assertEqual(json.loads(self.card("iphone")[1]), {"Goes to": "iphone (phone, online)"})
        # An id first in Ferry's list wins over another's name, as in Ferry
        self.assertEqual(json.loads(self.card("macbook")[1]), {"Goes to": "Jari - MacBook (computer, offline)"})

    def test_unknown_stops_the_call(self):
        for want in ("phone", "", "--to"):
            status, _, err = self.card(want)
            self.assertEqual(status, 1)
            self.assertIn("No device", err)

    def test_both_sends_show_it(self):
        for name in ("ferry_send_text", "ferry_send_files"):
            spec = tool_spec(REPO / "plugins/ferry/mcp.json", name)
            self.assertEqual(spec["card"], ["./device", "{to}"])


if __name__ == "__main__":
    unittest.main()
