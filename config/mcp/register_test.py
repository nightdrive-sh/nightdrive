#!/usr/bin/env python3
"""`nightdrive mcp status`'s warning about Claude Code's own permissions (#1837, #1865):
`python3 config/mcp/register_test.py`. A rule that lets Claude Code run any command, in the user's settings.json or
settings.local.json, gets round Nightdrive's limits and is named; one command, or one subcommand, isn't. So is one
that runs or writes anything through a wrapper (timeout, find -exec, cp, hyprctl dispatch), and an Edit or Write
rule that reaches the Access file, Claude Code's settings or this checkout (#1885)."""

import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent))

import register  # noqa: E402

ANY = ["Bash", "Bash(*)", "Bash(*:*)", "Bash(:*)", " Bash(* ) ", "Bash(nightdrive *)", "Bash(nightdrive:*)",
       "Bash(~/.local/bin/nightdrive *)", "Bash(/home/u/dotfiles/bin/nightdrive *)", "Bash(nightmail *)",
       "Bash(python3:*)", "Bash(python3.14 *)", "Bash(bash *)", "Bash(sh:*)", "Bash(sudo *)", "Bash(env *)",
       "Bash(xargs:*)", "Bash(home-assistant *)", "Bash(software-claude *)",
       # #1885: what runs another command, writes any file or starts things on the desktop
       "Bash(find *)", "Bash(awk *)", "Bash(sed *)", "Bash(git *)", "Bash(git:*)", "Bash(make *)", "Bash(npx *)",
       "Bash(uv run *)", "Bash(uv run:*)", "Bash(timeout *)", "Bash(nohup *)", "Bash(setsid *)", "Bash(cp *)",
       "Bash(tee *)", "Bash(hyprctl *)", "Bash(hyprctl dispatch *)", "Bash(qs *)", "Bash(qs -p *)", "Bash(gio *)",
       "Bash(gio launch *)", "Bash(xdg-open *)", "Bash(/usr/bin/timeout *)", "Bash(curl *)", "Bash(git -c *)",
       "Bash(find ~/Notes -name *)", "Bash(sed -n *)", "Bash(xargs -0 *)", "Bash(npm exec *)", "Bash(flatpak run *)"]
NOT_ANY = ["Bash(nightdrive release *)", "Bash(nightdrive mcp status)", "Bash(git status)", "Bash(ls:*)", "Read(*)",
           "Bash(python3 tools/build.py *)", "mcp__nightdrive", "Bashful", "WebFetch(*)", None, 42, ["Bash"],
           "Bash(git add:*)", "Bash(git log *)", "Bash(uv run pytest *)", "Bash(npm run build)", "Bash(hyprctl clients)",
           "Bash(find . -name x)", "Bash(qs ipc call launcher rows)", "Bash(jq *)", "Bash(grep *)", "Bash(rg:*)",
           "Bash(cat *)"]
# Edit and Write rules that reach Nightdrive's settings, Claude Code's or the server's code; and ones that don't
EDITS = ["Edit", "Write", "Edit(*)", "Write(**)", "Edit(/**)", "Edit(//**)", "Edit(~/**)", "Edit(~/.config/**)",
         "Edit(~/.config/nightdrive/*)", "Edit(~/.claude*)", "Edit(~/.claude/**)", "Write(~/.claude.json)",
         "Edit(~/.local/state/**)", "MultiEdit(.config/**)", "Edit(//home/**)", "Edit(~/.config)", "Edit(~/.c*/**)"]
NOT_EDITS = ["Edit(~/Notes/**)", "Write(~/Downloads/*)", "Edit(src/**)", "Read(~/.config/**)", "Bash(cp *)", "Edit(",
             None, "Edit(~/.config/kitty/**)", "Edit(//tmp/**)"]


class Rules(unittest.TestCase):
    def test_any_command(self):
        for rule in ANY:
            with self.subTest(rule=rule):
                self.assertTrue(register.any_command(rule))

    def test_not_any_command(self):
        for rule in NOT_ANY:
            with self.subTest(rule=rule):
                self.assertFalse(register.any_command(rule))

    def test_edits_that_reach_the_settings(self):
        home = Path("/home/u")
        with mock.patch.object(register, "HOME", home), mock.patch.object(register, "REPO", home / "dotfiles"):
            for rule in EDITS + ["Edit(~/dotfiles/**)", "Edit(//home/u/dotfiles/config/mcp/*.py)"]:
                with self.subTest(rule=rule):
                    self.assertTrue(register.edits_guarded(rule))
            for rule in NOT_EDITS + ["Edit(~/dotfiles/docs/**)"]:
                with self.subTest(rule=rule):
                    self.assertFalse(register.edits_guarded(rule))
            out = register.wide_open({"permissions": {"allow": ["Read(*)", "Edit(~/.config/**)"]}}, "settings.json")
            self.assertEqual(len(out), 1)
            self.assertIn("Edit(~/.config/**) allowed in settings.json", out[0])

    def test_accept_edits_mode(self):
        self.assertIn("acceptEdits", register.wide_open({"permissions": {"defaultMode": "acceptEdits"}})[0])

    def test_bypass_mode(self):
        self.assertIn("bypassPermissions", register.wide_open({"permissions": {"defaultMode": "bypassPermissions"}})[0])

    def test_odd_files(self):
        for data in ({}, {"permissions": []}, {"permissions": {"allow": "Bash"}}, [], "x"):
            self.assertEqual(register.wide_open(data), [])


class LocalSettings(unittest.TestCase):
    def warnings(self, text):
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp)
            (home / ".claude").mkdir()
            if text is not None:
                (home / ".claude/settings.local.json").write_text(text)
            with mock.patch.object(register, "HOME", home), \
                    mock.patch.object(register, "SETTINGS_LOCAL", home / ".claude/settings.local.json"):
                return register.local_wide_open()

    def test_named(self):
        out = self.warnings(json.dumps({"permissions": {"allow": ["Bash(git status)", "Bash(nightmail *)"]}}))
        self.assertEqual(len(out), 1)
        self.assertIn("Bash(nightmail *) allowed in ~/.claude/settings.local.json", out[0])

    def test_missing_or_broken(self):
        for text in (None, "", "{", "[]"):
            self.assertEqual(self.warnings(text), [])


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
