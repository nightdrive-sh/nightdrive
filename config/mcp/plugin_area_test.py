#!/usr/bin/env python3
"""A plugin from outside Nightdrive keeps its tools in its own area (#1865): `python3 config/mcp/plugin_area_test.py`.
In `nightdrive` its reads would run even on Strict, in `mail` under the rules the user set for Mail, and Access would
show them on that row. The repository's own plugins (Mail's tools in `mail`) are as before."""

import json
import re
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import registry  # noqa: E402


def tool(area, name="acme_read"):
    return {"name": name, "description": "A test.", "class": "read", "area": area,
            "inputSchema": {"type": "object", "properties": {}}, "command": ["true"]}


class PluginArea(unittest.TestCase):
    def read(self, folder, plugin, *tools):
        path = Path(folder) / "mcp.json"
        path.write_text(json.dumps({"tools": list(tools)}))
        return registry.read_file(path, folder, plugin)

    def test_external_own_area(self):
        with tempfile.TemporaryDirectory() as tmp:
            tools, problems = self.read(tmp, "acme", tool("acme"))
            self.assertEqual(([t.name for t in tools], problems), (["acme_read"], []))

    def test_external_in_a_core_area(self):
        with tempfile.TemporaryDirectory() as tmp:
            for area in ("nightdrive", "mail", "screen", "software"):
                with self.subTest(area=area):
                    tools, problems = self.read(tmp, "acme", tool(area))
                    self.assertEqual(tools, [])
                    self.assertIn("keeps its tools in its own area", problems[0])

    def test_external_named_as_a_core_area(self):
        """An outside plugin called "screen" doesn't get Access's What's on screen row by its id."""
        with tempfile.TemporaryDirectory() as tmp:
            tools, problems = self.read(tmp, "screen", tool("screen", name="screen_read"))
            self.assertEqual(tools, [])
            self.assertIn("own area", problems[0])

    def test_repository_plugin(self):
        folder = registry.REPO / "plugins" / "mail"
        tools, problems = registry.read_file(folder / "mcp.json", folder, "mail")
        self.assertEqual(problems, [])
        self.assertIn("mail_thread", [t.name for t in tools])


class OtherAreasNames(unittest.TestCase):
    """A tool's text doesn't name a tool of another area: one the user said No to would still be named (#1865)."""

    def test_descriptions(self):
        files = sorted((HERE / "tools").glob("*.json")) + sorted((registry.REPO / "plugins").glob("*/mcp.json"))
        tools = {t["name"]: (t["area"], json.dumps(t)) for f in files for t in json.loads(f.read_text())["tools"]}
        for name, (area, text) in tools.items():
            for word in set(re.findall(r"\b[a-z][a-z0-9_]+\b", text)) - {name}:
                with self.subTest(tool=name, names=word):
                    self.assertFalse(word in tools and tools[word][0] != area)


if __name__ == "__main__":
    unittest.main()
