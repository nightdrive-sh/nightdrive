#!/usr/bin/env python3
"""The list of plugins that are on gives the server only folders it may (#1950): `python3 config/mcp/active_list_test.py`.
A line in ~/.local/state/nightdrive/plugins.d/active that names a folder anywhere but this checkout's plugins/<id> or
~/.local/share/nightdrive/plugins/<id> (where `nightdrive plugins add` puts one) brings in no tools, and the list is no
longer in ~/.cache, where a cache cleaner or a rule that lets Claude write there could change it."""

import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import claude_rules  # noqa: E402
import registry  # noqa: E402


class ActiveList(unittest.TestCase):
    def folders(self, text):
        with tempfile.TemporaryDirectory() as tmp:
            active = Path(tmp) / "active"
            active.write_text(text)
            self.external = Path(tmp) / "external"
            (self.external / "acme").mkdir(parents=True)
            return registry.plugin_folders(active, self.external)

    def test_repo_plugin_is_this_checkouts(self):
        # Whatever folder the line names: a worktree's server reads its own mcp.json
        self.assertEqual(self.folders("mail\t/somewhere/else/mail\n"), [("mail", registry.REPO / "plugins" / "mail")])

    def test_external_plugin_in_its_place(self):
        with tempfile.TemporaryDirectory() as tmp:
            ext = Path(tmp)
            active = ext / "active"
            active.write_text(f"acme\t{ext}/acme\n")
            self.assertEqual(registry.plugin_folders(active, ext), [("acme", ext / "acme")])

    def test_forged_folder_left_out(self):
        for line in ("acme\t/tmp/evil\n", "acme\t/home/u/.local/share/nightdrive/plugins/other\n",
                     "evil\t/tmp/evil\n", "acme\t\n", "../evil\t/tmp/evil\n", "a/b\t/tmp/evil\n", "\t/tmp/evil\n"):
            with self.subTest(line=line):
                self.assertEqual(self.folders(line), [])

    def test_dot_dot_in_the_listed_folder(self):
        with tempfile.TemporaryDirectory() as tmp:
            ext = Path(tmp)
            active = ext / "active"
            active.write_text(f"acme\t{ext}/acme/../../evil\n")
            self.assertEqual(registry.plugin_folders(active, ext), [])

    def test_missing_list_no_plugins(self):
        self.assertEqual(registry.plugin_folders("/nonexistent/active"), [])

    def test_not_in_cache(self):
        self.assertEqual(registry.ACTIVE, Path.home() / ".local/state/nightdrive/plugins.d/active")
        self.assertIn(".local/state/nightdrive/plugins.d/active", claude_rules.GUARDED_FILES)
        self.assertFalse(any(".cache" in f for f in claude_rules.GUARDED_FILES))


if __name__ == "__main__":
    unittest.main()
