#!/usr/bin/env python3
"""run.expand's tests: `python3 config/mcp/expand_test.py`. A value that would begin a word with - is refused unless a
-- came before it in the template, or it is the value of a group's [option, {name}] pair (#1930); and every tool's
templates, the core's and every plugin's, still expand with values they take."""

import json
import sys
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
sys.path.insert(0, str(HERE))

import run  # noqa: E402
from run import ToolError  # noqa: E402

TEMPLATES = ("command", "undo", "before", "card", "asks_if")


def refused(template, values):
    try:
        run.expand(template, values)
    except ToolError as e:
        return "begins with \"-\"" in str(e)
    return False


class Dash(unittest.TestCase):
    def test_positional_refused(self):
        for template, values in [
            (["notes", "trash", "--json", "{note}"], {"note": "--all"}),     # a switch, then the note
            (["nightmail", "search", "{query}"], {"query": "-rf"}),
            (["home-assistant", "set", "{entity}", "{state}"], {"entity": "light.x", "state": "--help"}),
            (["deck", "volume", "{delta}"], {"delta": -5}),                  # a number too
            (["nightmail", "delete", "--check", "{ids}"], {"ids": ["a", "-b"]}),
            (["x", ["{limit}"]], {"limit": "-1"}),                           # a group without an option
            (["x", ["--in", "{dirs}"]], {"dirs": ["a", "--all"]}),           # a list after the option's first item
            (["x", ["--in", "{dirs}"]], {"dirs": ["--all"]}),
            (["x", "--app", "{app}"], {"app": "-x"}),                         # outside a group: can't tell
            (["x", "{name}.txt"], {"name": "-r"}),                           # the value begins the word
        ]:
            with self.subTest(template=template, values=values):
                self.assertTrue(refused(template, values))

    def test_after_double_dash(self):
        self.assertEqual(run.expand(["notes", "restore", "--", "{names}"], {"names": ["-a", "b"]}),
                         ["notes", "restore", "--", "-a", "b"])
        self.assertEqual(run.expand(["x", ["--until", "{until}"], "--", "{id}"], {"until": "", "id": "-1"}),
                         ["x", "--until", "", "--", "-1"])
        # a -- inside a group that is there counts for what follows it
        self.assertEqual(run.expand(["x", ["--to", "{to}", "--"], "{text}"], {"to": "p", "text": "-hi"}),
                         ["x", "--to", "p", "--", "-hi"])
        # …and one that is left out doesn't
        self.assertTrue(refused(["x", ["--to", "{to}", "--"], "{text}"], {"text": "-hi"}))

    def test_option_value_in_a_group(self):
        self.assertEqual(run.expand(["tasks", "add", ["--note", "{note}"], "--", "{title}"],
                                    {"note": "- milk", "title": "Shop"}),
                         ["tasks", "add", "--note", "- milk", "--", "Shop"])
        self.assertEqual(run.expand(["x", ["--limit", "{n}"]], {"n": -1}), ["x", "--limit", "-1"])

    def test_option_words_and_plain_values_unchanged(self):
        self.assertEqual(run.expand(["x", "--json", "{a}", "--b={b}", "n-{c}"], {"a": "a-b", "b": "-1", "c": "-2"}),
                         ["x", "--json", "a-b", "--b=-1", "n--2"])
        self.assertEqual(run.expand(["x", ["--sensors", "{s}"], "{q}"], {"s": True, "q": "q"}), ["x", "--sensors", "q"])

    def test_message(self):
        tool = type("T", (), {"name": "notes_read", "spec": {"command": ["notes", "read", "--json", "{note}"]}})
        with self.assertRaises(ToolError) as caught:
            run.prepare(tool, {"note": "--all"})
        self.assertEqual(str(caught.exception),
                         "notes_read takes no note that begins with \"-\": the command would read it as an option.")


class BeforeTheCard(unittest.TestCase):
    def test_refused_without_asking(self):
        """An act tool always asks on screen; a value its command would refuse is refused first, so the user isn't
        asked to allow a call that then fails."""
        import tempfile
        import registry
        asked = []
        with tempfile.TemporaryDirectory() as tmp:
            tool = {"name": "test_act", "description": "A test.", "class": "act", "area": "mail",
                    "inputSchema": {"type": "object", "properties": {"to": {"type": "string"}}},
                    "command": ["true", "{to}"]}
            (Path(tmp) / "tools.json").write_text(json.dumps({"tools": [tool]}))
            (Path(tmp) / "access.json").write_text(json.dumps({"version": 2, "level": "open", "areas": {}}))
            reg = registry.Registry(core=tmp, active=Path(tmp) / "none", access_file=Path(tmp) / "access.json",
                                    log=lambda text: None)
            reg.confirm = type("Card", (), {"ask": staticmethod(lambda *a: asked.append(a) or False)})
            with self.assertRaises(ToolError) as caught:
                reg.call("test_act", {"to": "--all"})
            self.assertIn("begins with \"-\"", str(caught.exception))
            self.assertEqual(asked, [])
            with self.assertRaises(ToolError):   # an ordinary value gets the card (refused here)
                reg.call("test_act", {"to": "someone"})
            self.assertEqual(len(asked), 1)


def sample(prop, name):
    """A value its schema takes that is like what a call gives: its enum's first, its minimum, a pattern's example."""
    if "enum" in prop:
        return prop["enum"][0]
    kind = prop.get("type")
    kind = kind[0] if isinstance(kind, list) else kind
    if kind in ("integer", "number"):
        return prop.get("minimum", 1)
    if kind == "boolean":
        return True
    if kind == "array":
        return [sample(prop.get("items", {}), name)]
    if kind == "object":
        return {}
    if "pattern" in prop:
        return {"album_uri": "spotify:album:" + "a" * 22, "artist_id": "a" * 22}.get(name, "0")
    return f"{name} value"


def all_tools():
    files = sorted((HERE / "tools").glob("*.json")) + sorted(REPO.glob("plugins/*/mcp.json"))
    for path in files:
        for tool in json.loads(path.read_text())["tools"]:
            yield path, tool


class EveryTool(unittest.TestCase):
    def test_templates_expand(self):
        """Each template with every name it uses given (its schema's sample, else a word an output would give): no
        tool's ordinary values are refused, and its words come out as before."""
        count = 0
        for path, tool in all_tools():
            props = tool["inputSchema"].get("properties", {})
            for key in TEMPLATES:
                template = tool.get(key)
                if not isinstance(template, list):
                    continue
                values = {n: sample(props[n], n) if n in props else f"{n}-0" for n in run.placeholders(template)}
                with self.subTest(file=str(path.relative_to(REPO)), tool=tool["name"], template=key):
                    argv = run.expand(template, values)
                    self.assertTrue(argv and not any(run.PLACEHOLDER.search(w) for w in argv), argv)
                    count += 1
        self.assertGreater(count, 100)


if __name__ == "__main__":
    unittest.main()
