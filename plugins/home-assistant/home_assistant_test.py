#!/usr/bin/env python3
"""What Claude's Home Assistant tools keep to (#1866): `python3 plugins/home-assistant/home_assistant_test.py`.
- Whether anyone is home is the presence choice's: a sensor that says it by its id or name, without a device class,
  is left out too (binary_sensor.jari_home, "Someone home"); a place's temperature isn't.
- Running an automation keeps its conditions (automation.trigger with skip_condition false).
Home Assistant is a stand-in: nothing is sent anywhere."""

import importlib.machinery
import importlib.util
import io
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
              ("sensor", "sensor.x", {"friendly_name": "Läsnäolo"})]
    SHOWN = [("binary_sensor", "binary_sensor.front_door", {"device_class": "door"}),
             ("sensor", "sensor.home_temperature", {"friendly_name": "Home temperature"}),
             ("sensor", "sensor.outdoor", {"friendly_name": "Outdoor humidity"}),
             ("binary_sensor", "binary_sensor.washer", {"friendly_name": "Washer running"}),
             ("sensor", "sensor.x", {"friendly_name": 42})]

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


if __name__ == "__main__":
    unittest.main()
