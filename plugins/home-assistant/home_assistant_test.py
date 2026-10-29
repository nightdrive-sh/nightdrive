#!/usr/bin/env python3
"""What Claude's Home Assistant tools keep to (#1866): `python3 plugins/home-assistant/home_assistant_test.py`.
- Whether anyone is home is the presence choice's: a sensor that says it by its id or name, without a device class,
  is left out too (binary_sensor.jari_home, "Someone home"); a place's temperature isn't.
- Running an automation keeps its conditions (automation.trigger with skip_condition false).
- Without the unlock choice a scene that sets a lock or a cover (or a group of one) isn't run, and a script, button or
  switch whose name says a door, gate or lock is marked on its card; an input_boolean that says whether anyone is
  home is presence (#1880).
Home Assistant is a stand-in: nothing is sent anywhere."""

import importlib.machinery
import importlib.util
import io
import json
import os
import unittest
from contextlib import redirect_stdout
from pathlib import Path
from unittest import mock

SCRIPT = Path(__file__).resolve().parent / "bin/home-assistant"
loader = importlib.machinery.SourceFileLoader("home_assistant_script", str(SCRIPT))
ha = importlib.util.module_from_spec(importlib.util.spec_from_loader("home_assistant_script", loader))
loader.exec_module(ha)


class Presence(unittest.TestCase):
    HIDDEN = [("binary_sensor", "binary_sensor.jari_home", {}),
              ("binary_sensor", "binary_sensor.template_1", {"friendly_name": "Someone home"}),
              ("binary_sensor", "binary_sensor.x", {"friendly_name": "Jari kotona"}),
              ("binary_sensor", "binary_sensor.hall", {"device_class": "motion"}),
              ("binary_sensor", "binary_sensor.olohuone_liike", {}),
              ("sensor", "sensor.jari_location", {}),
              ("sensor", "sensor.family", {"friendly_name": "Who is away"}),
              ("sensor", "sensor.pixel_geocoded_location", {}),
              ("sensor", "sensor.x", {"friendly_name": "Läsnäolo"}),
              ("input_boolean", "input_boolean.someone_home", {}),
              ("input_boolean", "input_boolean.away_mode", {"friendly_name": "Away"}),
              ("input_boolean", "input_boolean.x", {"friendly_name": "Jari kotona"})]
    SHOWN = [("binary_sensor", "binary_sensor.front_door", {"device_class": "door"}),
             ("sensor", "sensor.home_temperature", {"friendly_name": "Home temperature"}),
             ("sensor", "sensor.outdoor", {"friendly_name": "Outdoor humidity"}),
             ("binary_sensor", "binary_sensor.washer", {"friendly_name": "Washer running"}),
             ("sensor", "sensor.x", {"friendly_name": 42}),
             ("input_boolean", "input_boolean.guest_mode", {"friendly_name": "Guest mode"})]

    def test_hidden(self):
        for domain, eid, attrs in self.HIDDEN:
            with self.subTest(eid=eid, attrs=attrs):
                self.assertTrue(ha.presence(domain, eid, attrs))

    def test_shown(self):
        for domain, eid, attrs in self.SHOWN:
            with self.subTest(eid=eid, attrs=attrs):
                self.assertFalse(ha.presence(domain, eid, attrs))


class Client:
    def __init__(self):
        self.posts = []

    def call(self, method, path, data=None):
        if method == "POST":
            self.posts.append((path, data))
            return []
        return {"entity_id": "automation.lights", "state": "on", "attributes": {"friendly_name": "Lights"}}


class Automation(unittest.TestCase):
    def test_run_keeps_conditions(self):
        c = Client()
        with mock.patch.dict(os.environ, {"NIGHTDRIVE_MCP": ""}), redirect_stdout(io.StringIO()):
            ha.set_state(c, "automation.lights", "run")
        self.assertEqual(c.posts, [("/api/services/automation/trigger",
                                    {"entity_id": "automation.lights", "skip_condition": False})])

    def test_others_as_before(self):
        c = Client()
        with mock.patch.dict(os.environ, {"NIGHTDRIVE_MCP": ""}), redirect_stdout(io.StringIO()):
            ha.set_state(c, "automation.lights", "off")
        self.assertEqual(c.posts, [("/api/services/automation/turn_off", {"entity_id": "automation.lights"})])


class House:
    """Home Assistant's states by id, and the services called"""

    def __init__(self, states):
        self.states, self.posts = states, []

    def call(self, method, path, data=None):
        if method == "POST":
            if path == "/api/template":
                return ""
            self.posts.append((path, data))
            return []
        eid = path.rsplit("/", 1)[1]
        if eid not in self.states:
            raise ha.urllib.error.HTTPError(path, 404, "not found", {}, None)
        return {"entity_id": eid, **self.states[eid]}


def scene(*members, name="Evening"):
    return {"state": "2026-10-29T10:00:00", "attributes": {"friendly_name": name, "entity_id": list(members)}}


CLAUDE = {"NIGHTDRIVE_MCP": "1", "NIGHTDRIVE_MCP_OPTIONS": "{}"}


class Opening(unittest.TestCase):
    STATES = {
        "scene.leave": scene("light.hall", "lock.front_door"),
        "scene.garage": scene("cover.garage", name="Garage"),
        "scene.grouped": scene("light.hall", "group.doors"),
        "scene.lost_group": scene("group.gone"),
        "scene.evening": scene("light.hall", "media_player.tv"),
        "group.doors": {"state": "locked", "attributes": {"entity_id": ["lock.back_door"]}},
        "script.open_garage": {"state": "off", "attributes": {"friendly_name": "Open garage"}},
        "switch.sonoff_1": {"state": "off", "attributes": {"friendly_name": "Autotallin ovi"}},
        "button.x": {"state": "unknown", "attributes": {"friendly_name": "Etuovi auki"}},
        "switch.kettle": {"state": "off", "attributes": {"friendly_name": "Kettle"}},
        "script.goodnight": {"state": "off", "attributes": {"friendly_name": "Good night"}},
    }

    def set(self, eid, state="run", check=False, options="{}"):
        house = House(self.STATES)
        out = io.StringIO()
        with mock.patch.dict(os.environ, {**CLAUDE, "NIGHTDRIVE_MCP_OPTIONS": options}), redirect_stdout(out):
            ha.set_state(house, eid, state, check=check)
        return house, json.loads(out.getvalue()) if check else out.getvalue()

    def refused(self, eid, check):
        with self.assertRaises(SystemExit), mock.patch("sys.stderr", io.StringIO()) as err:
            house, _ = self.set(eid, check=check)
        return err.getvalue()

    def test_a_scene_that_unlocks_or_opens_is_refused(self):
        for eid in ("scene.leave", "scene.garage", "scene.grouped", "scene.lost_group"):
            for check in (True, False):
                with self.subTest(eid=eid, check=check):
                    self.assertIn("wasn't run", self.refused(eid, check))

    def test_nothing_is_called_when_refused(self):
        house = House(self.STATES)
        with mock.patch.dict(os.environ, CLAUDE), self.assertRaises(SystemExit), \
                mock.patch("sys.stderr", io.StringIO()):
            ha.set_state(house, "scene.grouped", "run")
        self.assertEqual(house.posts, [])

    def test_with_unlock_the_card_says_what_it_sets(self):
        _, card = self.set("scene.grouped", check=True, options=json.dumps({"unlock": True}))
        self.assertEqual(card["Sets"], "lock.back_door")
        house, _ = self.set("scene.leave", options=json.dumps({"unlock": True}))
        self.assertEqual(house.posts, [("/api/services/scene/turn_on", {"entity_id": "scene.leave"})])

    def test_an_ordinary_scene_runs(self):
        _, card = self.set("scene.evening", check=True)
        self.assertNotIn("Sets", card)
        house, _ = self.set("scene.evening")
        self.assertEqual(len(house.posts), 1)

    def test_the_card_warns_of_what_its_name_says_opens(self):
        for eid, state in (("script.open_garage", "run"), ("switch.sonoff_1", "on"), ("button.x", "run")):
            with self.subTest(eid=eid):
                _, card = self.set(eid, state, check=True)
                self.assertIn("door, gate or lock", card.get("Note", ""))
        for eid, state in (("switch.kettle", "on"), ("script.goodnight", "run")):
            with self.subTest(eid=eid):
                _, card = self.set(eid, state, check=True)
                self.assertNotIn("Note", card)

    def test_the_users_own_calls_are_as_before(self):
        house = House(self.STATES)
        with mock.patch.dict(os.environ, {"NIGHTDRIVE_MCP": ""}), redirect_stdout(io.StringIO()):
            ha.set_state(house, "scene.leave", "run")
        self.assertEqual(len(house.posts), 1)


class Listing(unittest.TestCase):
    RAW = [{"entity_id": "input_boolean.someone_home", "state": "on", "attributes": {}},
           {"entity_id": "input_boolean.guest_mode", "state": "off", "attributes": {}},
           {"entity_id": "light.hall", "state": "on", "attributes": {}}]

    def ids(self, options):
        class C:
            def call(_, method, path, data=None):
                return {} if path == "/api/template" else self.RAW
        with mock.patch.dict(os.environ, {**CLAUDE, "NIGHTDRIVE_MCP_OPTIONS": options}), \
                mock.patch.object(ha, "favorites", lambda: []):
            return [e["id"] for e in ha.states(C())]

    def test_presence_booleans_need_the_choice(self):
        self.assertNotIn("input_boolean.someone_home", self.ids("{}"))
        self.assertIn("input_boolean.guest_mode", self.ids("{}"))
        self.assertIn("input_boolean.someone_home", self.ids(json.dumps({"presence": True})))


if __name__ == "__main__":
    unittest.main()
