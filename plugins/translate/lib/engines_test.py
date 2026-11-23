"""engines.py and cli.py: reading translate-shell's raw reply, the direction, and the user's own engine."""
import json
import os
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import cli      # noqa: E402
import config   # noqa: E402
import engines  # noqa: E402

# What `trans -dump fi:en kolinaa` printed, shortened: the reply between the transfer's chunk sizes
DUMP = """2f0
[[["rattle","kolinaa",null,null,3]],[["noun",["clatter","rattle","eau de Cologne"],[],"kolina",1]],"fi"]
0
"""


class ParseDump(unittest.TestCase):
    def test_translation_and_other_words(self):
        self.assertEqual(engines.parse_dump(DUMP), ("rattle", ["clatter", "eau de Cologne"]))

    def test_sentence_parts_are_joined(self):
        raw = json.dumps([[["Good morning. ", "Hyvää huomenta."], ["Thanks.", "Kiitos."]], None, "fi"])
        self.assertEqual(engines.parse_dump(raw), ("Good morning. Thanks.", []))

    def test_not_a_reply(self):
        self.assertIsNone(engines.parse_dump("Did you mean: kolina\n"))
        self.assertIsNone(engines.parse_dump("[[]]"))


class Direction(unittest.TestCase):
    def test_guess_and_overrides(self):
        pair = ["fi", "en"]
        self.assertEqual(cli.direction("kolinaa", None, None, pair), ("fi", "en", True))
        self.assertEqual(cli.direction("rattling", None, None, pair), ("en", "fi", True))
        self.assertEqual(cli.direction("kolinaa", None, "fi", pair), ("en", "fi", False))
        self.assertEqual(cli.direction("kolinaa", "sv", "de", pair), ("sv", "de", False))
        # A pair the guess doesn't know starts from its first language
        self.assertEqual(cli.direction("god morgon", None, None, ["sv", "en"]), ("sv", "en", True))


class OwnEngine(unittest.TestCase):
    def test_command_gets_text_on_stdin_or_in_argv(self):
        spec = {"type": "command", "command": ["tr", "a-z", "A-Z"]}
        self.assertEqual(engines.translate("up", spec, "moi", "fi", "en")["translation"], "MOI")
        spec = {"type": "command", "command": ["printf", "%s", "{from}>{to}:{text}"]}
        self.assertEqual(engines.translate("echo", spec, "moi", "fi", "en")["translation"], "fi>en:moi")

    def test_user_engines_are_read_and_bad_ones_left_out(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder = Path(tmp) / "engines.d"
            folder.mkdir()
            (folder / "mine.json").write_text('{"name": "Mine", "type": "command", "command": ["cat"]}')
            (folder / "broken.json").write_text("{nope")
            (folder / "odd.json").write_text('{"type": "teleport"}')
            old, config.USER_ENGINES = config.USER_ENGINES, folder
            try:
                found = config.engines()
            finally:
                config.USER_ENGINES = old
        self.assertTrue(found["mine"]["own"])
        self.assertNotIn("broken", found)
        self.assertNotIn("odd", found)
        self.assertIn("opus-mt", found)


if __name__ == "__main__":
    os.environ.setdefault("LC_ALL", "C.UTF-8")
    unittest.main()
