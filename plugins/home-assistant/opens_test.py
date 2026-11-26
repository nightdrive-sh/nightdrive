#!/usr/bin/env python3
"""What Claude's home_assistant_set keeps to since #1923: `python3 plugins/home-assistant/opens_test.py`.
- Running an automation or a script is held to Access's unlock choice by what it would do, as a scene is (#1880): its
  actions are read from Home Assistant's config, with the scenes, scripts and automations they start, and one that
  would unlock a lock or open a cover (by id, by a group, by an area, as a device action) isn't run without the choice.
  One whose config can't be read isn't either. One that only locks, closes or does something else runs as before.
- Setting an input_boolean that says whether anyone is home needs the presence choice, as reading one does.
Home Assistant is a stand-in (home_assistant_test.House): nothing is sent anywhere."""

import io
import json
import os
import sys
import unittest
from contextlib import redirect_stdout
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent))
from home_assistant_test import CLAUDE, House, ha, scene  # noqa: E402

UNLOCK = json.dumps({"unlock": True})


def call(action, *ids, **target):
    return {"action": action, "target": {"entity_id": list(ids), **target} if ids else target}


def auto(key, name="Automation"):
    """An automation's state: its config's id is an attribute"""
    return {"state": "on", "attributes": {"friendly_name": name, "id": key}}


STATES = {
    "automation.leave": auto("1001", "Leave home"),
    "automation.via_script": auto("1002"),
    "automation.via_scene": auto("1003"),
    "automation.via_service": auto("1004"),
    "automation.chain": auto("1005"),
    "automation.guarded_if": auto("1006"),
    "automation.choose": auto("1007"),
    "automation.lock_up": auto("1008", "Lock up"),
    "automation.area": auto("1009"),
    "automation.ha_area": auto("1010"),
    "automation.device_unlock": auto("1011"),
    "automation.device_lock": auto("1012"),
    "automation.group": auto("1013"),
    "automation.templated": auto("1014"),
    "automation.lights": auto("1015", "Evening lights"),
    "automation.yaml": {"state": "on", "attributes": {"friendly_name": "From YAML"}},   # no id: no config to read
    "automation.gone": auto("9999"),
    "scene.leave": scene("light.hall", "lock.front_door"),
    "script.open_up": {"state": "off", "attributes": {"friendly_name": "Open up"}},
    "script.loop_a": {"state": "off", "attributes": {}},
    "group.doors": {"state": "locked", "attributes": {"entity_id": ["lock.back_door"]}},
}
CONFIGS = {
    ("automation", "1001"): {"triggers": [{"trigger": "state", "entity_id": "person.x"}],
                             "actions": [call("lock.unlock", "lock.front_door")]},
    ("automation", "1002"): {"actions": [call("script.turn_on", "script.open_up")]},
    ("automation", "1003"): {"actions": [{"scene": "scene.leave"}]},
    ("automation", "1004"): {"actions": [{"service": "script.open_up"}]},
    ("automation", "1005"): {"actions": [call("automation.trigger", "automation.leave")]},
    # A lock in a condition, a trigger or a wait opens nothing
    ("automation", "1006"): {"triggers": [{"trigger": "state", "entity_id": "lock.front_door"}],
                             "conditions": [{"condition": "state", "entity_id": "lock.front_door", "state": "locked"}],
                             "actions": [{"if": [{"condition": "state", "entity_id": "lock.front_door"}],
                                          "then": [call("light.turn_on", "light.hall")]},
                                         {"wait_for_trigger": [{"trigger": "state", "entity_id": "cover.garage"},
                                                               {"trigger": "device", "device_id": "abc",
                                                                "domain": "lock", "type": "unlocked"}]}]},
    ("automation", "1007"): {"action": [{"choose": [{"conditions": [], "sequence": [
        {"parallel": [call("light.turn_on", "light.hall"), call("cover.open_cover", "cover.garage")]}]}]}]},
    ("automation", "1008"): {"actions": [call("lock.lock", "lock.front_door"), call("cover.close_cover", "cover.garage"),
                                         {"device_id": "abc", "domain": "lock", "type": "lock",
                                          "entity_id": "lock.back_door"}]},
    ("automation", "1009"): {"actions": [call("lock.unlock", area_id="hall")]},
    ("automation", "1010"): {"actions": [call("homeassistant.turn_on", area_id="garage")]},
    ("automation", "1011"): {"actions": [{"device_id": "abc", "domain": "lock", "type": "unlock",
                                          "entity_id": "lock.back_door"}]},
    ("automation", "1012"): {"actions": [{"device_id": "abc", "domain": "lock", "type": "lock"}]},
    ("automation", "1013"): {"actions": [call("homeassistant.turn_on", "group.doors")]},
    ("automation", "1014"): {"actions": [{"action": "{{ 'lock.' ~ what }}", "target": {"entity_id": "lock.x"}}]},
    ("automation", "1015"): {"actions": [call("light.turn_on", "light.hall"), call("script.turn_on", "script.loop_a"),
                                         call("scene.turn_on", "scene.deleted")]},   # a scene that isn't: sets nothing
    ("script", "open_up"): {"sequence": [{"delay": 5}, call("cover.open_cover", "cover.garage")]},
    # Scripts that start each other: followed once each
    ("script", "loop_a"): {"sequence": [{"action": "script.loop_b"}]},
    ("script", "loop_b"): {"sequence": [call("script.turn_on", "script.loop_a"), call("switch.turn_on", "switch.tv")]},
}
OPENING = ["automation.leave", "automation.via_script", "automation.via_scene", "automation.via_service",
           "automation.chain", "automation.choose", "automation.area", "automation.ha_area",
           "automation.device_unlock", "automation.group", "automation.templated", "script.open_up"]
HARMLESS = ["automation.guarded_if", "automation.lock_up", "automation.device_lock", "automation.lights"]


class Run(unittest.TestCase):
    def set(self, eid, state="run", check=False, options="{}", env=None):
        house = House(STATES, CONFIGS)
        out = io.StringIO()
        with mock.patch.dict(os.environ, env or {**CLAUDE, "NIGHTDRIVE_MCP_OPTIONS": options}), redirect_stdout(out):
            ha.set_state(house, eid, state, check=check)
        return house, out.getvalue()

    def refused(self, eid, state="run", check=False, options="{}"):
        with self.assertRaises(SystemExit), mock.patch("sys.stderr", io.StringIO()) as err:
            self.set(eid, state, check, options)
        return err.getvalue()

    def test_what_would_open_is_refused(self):
        for eid in OPENING:
            for check in (True, False):
                with self.subTest(eid=eid, check=check):
                    self.assertIn("wasn't run", self.refused(eid, check=check))

    def test_the_refusal_names_what_it_opens(self):
        self.assertIn("may open or unlock cover.garage", self.refused("automation.via_script"))
        self.assertIn("lock.back_door", self.refused("automation.group"))
        self.assertIn("lock.front_door", self.refused("automation.via_scene"))

    def test_nothing_is_called_when_refused(self):
        house = House(STATES, CONFIGS)
        with mock.patch.dict(os.environ, CLAUDE), self.assertRaises(SystemExit), \
                mock.patch("sys.stderr", io.StringIO()):
            ha.set_state(house, "automation.via_script", "run")
        self.assertEqual(house.posts, [])

    def test_what_cant_be_read_is_refused(self):
        for eid in ("automation.yaml", "automation.gone"):
            with self.subTest(eid=eid):
                self.assertIn("can't be read", self.refused(eid))

    def test_what_opens_nothing_runs(self):
        for eid in HARMLESS:
            with self.subTest(eid=eid):
                _, card = self.set(eid, check=True)
                self.assertNotIn("Sets", json.loads(card))
                house, _ = self.set(eid)
                self.assertEqual(house.posts, [("/api/services/automation/trigger",
                                                {"entity_id": eid, "skip_condition": False})])

    def test_with_unlock_it_runs_and_the_card_says_what_it_opens(self):
        _, card = self.set("automation.via_script", check=True, options=UNLOCK)
        self.assertEqual(json.loads(card)["Sets"], "cover.garage")
        house, _ = self.set("automation.leave", options=UNLOCK)
        self.assertEqual(len(house.posts), 1)

    def test_on_and_off_are_the_automations_choice(self):
        self.assertIn("turn one on or off", self.refused("automation.leave", "off", options=UNLOCK))
        house, _ = self.set("automation.leave", "off", options=json.dumps({"automations": True}))
        self.assertEqual(house.posts, [("/api/services/automation/turn_off", {"entity_id": "automation.leave"})])

    def test_the_users_own_calls_are_as_before(self):
        house, _ = self.set("automation.leave", env={"NIGHTDRIVE_MCP": ""})
        self.assertEqual(len(house.posts), 1)


class Presence(unittest.TestCase):
    STATES = {"input_boolean.someone_home": {"state": "on", "attributes": {"friendly_name": "Someone home"}},
              "input_boolean.x": {"state": "off", "attributes": {"friendly_name": "Away mode"}},
              "input_boolean.guest_mode": {"state": "off", "attributes": {"friendly_name": "Guest mode"}}}

    def set(self, eid, state, check=False, options="{}"):
        house = House(self.STATES)
        out = io.StringIO()
        with mock.patch.dict(os.environ, {**CLAUDE, "NIGHTDRIVE_MCP_OPTIONS": options}), redirect_stdout(out):
            ha.set_state(house, eid, state, check=check)
        return house, out.getvalue()

    def test_needs_the_choice(self):
        for eid in ("input_boolean.someone_home", "input_boolean.x"):
            for check in (True, False):
                with self.subTest(eid=eid, check=check), self.assertRaises(SystemExit), \
                        mock.patch("sys.stderr", io.StringIO()) as err, redirect_stdout(io.StringIO()) as out:
                    try:
                        self.set(eid, "off", check)
                    finally:
                        self.assertIn("whether anyone is home", err.getvalue())
                        self.assertEqual(out.getvalue(), "")   # no card: its Now would tell

    def test_with_the_choice_it_is_set(self):
        house, _ = self.set("input_boolean.someone_home", "off", options=json.dumps({"presence": True}))
        self.assertEqual(house.posts, [("/api/services/input_boolean/turn_off",
                                        {"entity_id": "input_boolean.someone_home"})])

    def test_others_are_as_before(self):
        house, _ = self.set("input_boolean.guest_mode", "on")
        self.assertEqual(len(house.posts), 1)


if __name__ == "__main__":
    unittest.main()
