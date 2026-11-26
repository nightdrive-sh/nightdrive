#!/usr/bin/env python3
"""register.py's own: `python3 config/mcp/register_test.py`. Its warning about Claude Code's own permissions is
claude_rules.py's, tested in claude_rules_test.py."""

import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent))

import register  # noqa: E402


class ChangeLog(unittest.TestCase):
    def test_made_private(self):
        """A log written before it was made 600 (drafts' text in it) is made so by install and status."""
        import changes
        with tempfile.TemporaryDirectory() as tmp:
            log = Path(tmp) / "claude-changes.jsonl"
            log.write_text("{}\n")
            log.chmod(0o644)
            with mock.patch.object(changes, "FILE", log):
                changes.private()
                self.assertEqual(log.stat().st_mode & 0o777, 0o600)
                log.unlink()
                changes.private()   # none yet: nothing to do, no error
            self.assertIs(register.changes, changes)


if __name__ == "__main__":
    unittest.main()
