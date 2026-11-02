#!/usr/bin/env python3
"""`nightdrive mcp status`'s warning about Claude Code's own permissions (#1837, #1865, #1885, #1928):
`python3 config/mcp/claude_rules_test.py`. A rule in the user's settings.json or settings.local.json that lets Claude
Code run any command gets round Nightdrive's limits and is named; one command, or one subcommand, isn't. So is one that
runs or writes anything through a wrapper (timeout, find -exec, cp, sqlite3), one that runs a command Nightdrive's card
or Access keeps back (nightmail send, nightdrive mcp access level), one that types on the desktop (wtype), and an Edit
or Write rule that reaches the Access file, the list of plugins that are on, Claude Code's settings or the code the
tools run."""

import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent))

import access  # noqa: E402
import claude_rules  # noqa: E402
import registry  # noqa: E402

ANY = ["Bash", "Bash(*)", "Bash(*:*)", "Bash(:*)", " Bash(* ) ", "Bash(nightdrive *)", "Bash(nightdrive:*)",
       "Bash(~/.local/bin/nightdrive *)", "Bash(/home/u/dotfiles/bin/nightdrive *)", "Bash(nightmail *)",
       "Bash(python3:*)", "Bash(python3.14 *)", "Bash(bash *)", "Bash(sh:*)", "Bash(sudo *)", "Bash(env *)",
       "Bash(xargs:*)", "Bash(home-assistant *)", "Bash(software-claude *)",
       # #1885: what runs another command, writes any file or starts things on the desktop
       "Bash(find *)", "Bash(awk *)", "Bash(sed *)", "Bash(git *)", "Bash(git:*)", "Bash(make *)", "Bash(npx *)",
       "Bash(uv run *)", "Bash(uv run:*)", "Bash(timeout *)", "Bash(nohup *)", "Bash(setsid *)", "Bash(cp *)",
       "Bash(tee *)", "Bash(hyprctl *)", "Bash(hyprctl dispatch *)", "Bash(qs *)", "Bash(qs -p *)", "Bash(gio *)",
       "Bash(gio launch *)", "Bash(xdg-open *)", "Bash(/usr/bin/timeout *)", "Bash(curl *)", "Bash(git -c *)",
       "Bash(find ~/Notes -name *)", "Bash(sed -n *)", "Bash(xargs -0 *)", "Bash(npm exec *)", "Bash(flatpak run *)",
       # #1928: sqlite3's .shell, busybox's sh, patch writes any file
       "Bash(sqlite3 *)", "Bash(busybox:*)", "Bash(patch *)", "Bash(toybox *)", "Bash(ed *)"]
NOT_ANY = ["Bash(nightdrive release *)", "Bash(nightdrive mcp status)", "Bash(git status)", "Bash(ls:*)", "Read(*)",
           "Bash(python3 tools/build.py *)", "mcp__nightdrive", "Bashful", "WebFetch(*)", None, 42, ["Bash"],
           "Bash(git add:*)", "Bash(git log *)", "Bash(uv run pytest *)", "Bash(npm run build)", "Bash(hyprctl clients)",
           "Bash(find . -name x)", "Bash(qs ipc call launcher rows)", "Bash(jq *)", "Bash(grep *)", "Bash(rg:*)",
           "Bash(cat *)", "Bash(edit *)", "Bash(sqlite3x)"]
# What presses a key or clicks: Enter on the card is Allow
TYPING = ["Bash(wtype *)", "Bash(wtype:*)", "Bash(wtype -k Return)", "Bash(ydotool *)", "Bash(/usr/bin/xdotool key *)",
          "Bash(dotool)", "Bash(dotoolc:*)", "Bash(wlrctl *)"]
NOT_TYPING = ["Bash(wtypes *)", "Bash(echo wtype)", "Edit(wtype)", "Bash", "Bash(*)", None]
KEPT = ["nightmail send", "home-assistant set", "nightdrive network", *claude_rules.ACCESS_COMMANDS]
# Rules that run a kept command: covered by a * or named with arguments
RUNS_KEPT = ["Bash(nightmail send *)", "Bash(nightmail send:*)", "Bash(nightmail se*)", "Bash(nightmail send 4*)",
             "Bash(~/.local/bin/nightmail send 42 --check)", "Bash(home-assistant  set *)", "Bash(nightdrive mcp *)",
             "Bash(nightdrive mcp access *)", "Bash(nightdrive mcp access:*)", "Bash(nightdrive mcp access level *)",
             "Bash(nightdrive mcp access level open)", "Bash(nightdrive mcp access forget calendar_add)",
             "Bash(nightdrive network wifi off)", "Bash(nightdrive n*)"]
NOT_KEPT = ["Bash(nightmail search *)", "Bash(nightmail sendx)", "Bash(nightdrive mcp status)",
            "Bash(nightdrive mcp access allowed)", "Bash(nightdrive mcp access)", "Bash(home-assistant states *)",
            "Bash(nightdrive network)", "Bash(nightdrive release *)", "Edit(nightmail send *)", "Bash", None]
# Edit and Write rules that reach Nightdrive's settings, Claude Code's or the code the tools run; and ones that don't
EDITS = ["Edit", "Write", "Edit(*)", "Write(**)", "Edit(/**)", "Edit(//**)", "Edit(~/**)", "Edit(~/.config/**)",
         "Edit(~/.config/nightdrive/*)", "Edit(~/.claude*)", "Edit(~/.claude/**)", "Write(~/.claude.json)",
         "Edit(~/.local/state/**)", "MultiEdit(.config/**)", "Edit(//home/**)", "Edit(~/.config)", "Edit(~/.c*/**)",
         "Edit(~/dotfiles/**)", "Edit(//home/u/dotfiles/config/mcp/*.py)",
         # #1928: the list of plugins that are on, first-time allowances, the plugins' and scripts' code
         "Write(~/.cache/**)", "Edit(~/.cache/nightdrive/plugins.d/*)",
         "Edit(~/.config/nightdrive/claude-allowed.json)",
         "Edit(~/dotfiles/plugins/**)", "Write(~/dotfiles/plugins/mail/mcp.json)", "Edit(~/dotfiles/plugins/*/bin/*)",
         "Edit(~/dotfiles/config/hypr/scripts/*)", "Edit(~/dotfiles/bin/nightdrive)", "Edit(//opt/outside/**)",
         "Edit(//opt/outside/tool.py)"]
NOT_EDITS = ["Edit(~/Notes/**)", "Write(~/Downloads/*)", "Edit(src/**)", "Read(~/.config/**)", "Bash(cp *)", "Edit(",
             None, "Edit(~/.config/kitty/**)", "Edit(//tmp/**)", "Edit(~/dotfiles/docs/**)",
             "Edit(~/.cache/thumbnails/**)",
             "Edit(~/dotfiles/plugins/**/*.md)", "Edit(~/dotfiles/config/quickshell/kit/**)", "Edit(//opt/other/**)"]


def fake_home(tmp):
    """A home with a checkout in it and a plugin from outside it (at tmp/opt/outside), as the rules see them."""
    home = Path(tmp) / "home/u"
    for f in ("dotfiles/config/mcp/access.py", "dotfiles/bin/nightdrive", "dotfiles/config/hypr/scripts/theme",
              "dotfiles/plugins/mail/mcp.json", "dotfiles/plugins/mail/bin/nightmail",
              "dotfiles/plugins/mail/README.md",
              "dotfiles/docs/claude.md", "dotfiles/config/quickshell/kit/Row.qml"):
        (home / f).parent.mkdir(parents=True, exist_ok=True)
        (home / f).write_text("")
    outside = Path(tmp) / "opt/outside"
    outside.mkdir(parents=True)
    (outside / "tool.py").write_text("")
    return home, outside


class Rules(unittest.TestCase):
    def test_any_command(self):
        for rule in ANY:
            with self.subTest(rule=rule):
                self.assertTrue(claude_rules.any_command(rule))

    def test_not_any_command(self):
        for rule in NOT_ANY:
            with self.subTest(rule=rule):
                self.assertFalse(claude_rules.any_command(rule))

    def test_typing(self):
        for rule in TYPING:
            with self.subTest(rule=rule):
                self.assertTrue(claude_rules.types_input(rule))
        for rule in NOT_TYPING:
            with self.subTest(rule=rule):
                self.assertFalse(claude_rules.types_input(rule))

    def test_runs_kept(self):
        for rule in RUNS_KEPT:
            with self.subTest(rule=rule):
                self.assertTrue(claude_rules.runs_kept(rule, KEPT))
        for rule in NOT_KEPT:
            with self.subTest(rule=rule):
                self.assertFalse(claude_rules.runs_kept(rule, KEPT))

    def test_edits_that_reach_the_settings(self):
        with tempfile.TemporaryDirectory() as tmp:
            home, outside = fake_home(tmp)
            # //x in a rule is /x: the fake root's paths are named as they would be from /
            with mock.patch.object(claude_rules, "HOME", home), \
                    mock.patch.object(claude_rules, "REPO", home / "dotfiles"):
                paths = {p[len(tmp):] for p in
                         claude_rules.guarded_paths([home / "dotfiles" / f for f in claude_rules.GUARDED_FOLDERS]
                                                    + [outside]) if p.startswith(f"{tmp}/")}
                with mock.patch.object(claude_rules, "HOME", Path("/home/u")):
                    for rule in EDITS:
                        with self.subTest(rule=rule):
                            self.assertTrue(claude_rules.edits_guarded(rule, paths))
                    for rule in NOT_EDITS:
                        with self.subTest(rule=rule):
                            self.assertFalse(claude_rules.edits_guarded(rule, paths))
                    out = claude_rules.wide_open({"permissions": {"allow": ["Read(*)", "Edit(~/.config/**)"]}},
                                                 "settings.json", [], paths)
        self.assertEqual(len(out), 1)
        self.assertIn("(Edit(~/.config/**) allowed in settings.json)", out[0])

    def test_each_rule_named(self):
        allow = ["Bash(git status)", "Bash(nightdrive *)", "Bash(sqlite3 *)", "Bash(nightmail send *)",
                 "Bash(nightdrive mcp access *)", "Bash(wtype *)", "Bash(ydotool *)", "Write(~/.cache/**)"]
        out = claude_rules.wide_open({"permissions": {"allow": allow}}, "s.json", ["nightmail send",
                                     *claude_rules.ACCESS_COMMANDS], {str(Path.home() / ".cache/nightdrive")})
        self.assertEqual(len(out), 4, out)
        self.assertIn("(Bash(nightdrive *), Bash(sqlite3 *) allowed in s.json)", out[0])
        self.assertIn("(Bash(nightmail send *), Bash(nightdrive mcp access *) allowed in s.json)", out[1])
        self.assertIn("(Bash(wtype *), Bash(ydotool *) allowed in s.json)", out[2])
        self.assertIn("(Write(~/.cache/**) allowed in s.json)", out[3])

    def test_accept_edits_mode(self):
        self.assertIn("acceptEdits", claude_rules.wide_open({"permissions": {"defaultMode": "acceptEdits"}})[0])

    def test_bypass_mode(self):
        out = claude_rules.wide_open({"permissions": {"defaultMode": "bypassPermissions"}})
        self.assertIn("bypassPermissions", out[0])

    def test_odd_files(self):
        for data in ({}, {"permissions": []}, {"permissions": {"allow": "Bash"}}, [], "x",
                     {"permissions": {"allow": [None, 3, ["Bash"]]}}):
            self.assertEqual(claude_rules.wide_open(data, kept=[], paths=set()), [])


def tool(name, cls, command, area="mail", **more):
    spec = {"name": name, "class": cls, "command": command, "area": area, **more}
    return registry.Tool(spec, Path("/x"), "test")


class Kept(unittest.TestCase):
    """Which tools' commands count as kept back: from the tools and the user's Access as they are."""
    TOOLS = [tool("mail_send", "act", ["nightmail", "send", "{draft}", "--check"]),
             tool("mail_archive", "change", ["nightmail", "archive", "{ids}"]),
             tool("mail_search", "read", ["nightmail", "search", "{query}"]),
             tool("sound_output", "change", ["nightdrive", "sound", "output", "{output}"], area="sound-display",
                  asks_if=["nightdrive", "sound", "remote", "{output}"]),
             tool("deck_pick", "change", ["python3", "lib/playback.py", "pick", "{source}"], area="deck"),
             tool("ferry_send_files", "act", ["./send-files", "--to", "{to}"], area="ferry")]

    def kept(self, own):
        return claude_rules.kept_commands(self.TOOLS, access.Access("normal", own))

    def test_act_and_asks_if(self):
        kept = self.kept({"mail": {"read": "allow", "modify": "allow"}, "deck": {"modify": "allow"}})
        self.assertIn("nightmail send", kept)
        self.assertIn("nightdrive sound output", kept)
        self.assertNotIn("nightmail archive", kept)
        self.assertNotIn("nightmail search", kept)
        self.assertNotIn("python3 lib/playback.py pick", kept)
        # A name alone isn't a command words can match: ./send-files has no subcommand
        self.assertFalse(any(k.startswith("send-files") for k in kept))
        self.assertTrue(set(claude_rules.ACCESS_COMMANDS) <= set(kept))

    def test_access_ask_or_no(self):
        kept = self.kept({"mail": {"read": "no", "modify": "ask"}, "deck": {"modify": "allow"}})
        self.assertIn("nightmail archive", kept)
        self.assertIn("nightmail search", kept)

    def test_words(self):
        self.assertEqual(claude_rules.command_words(["/usr/bin/nightmail", "send", "{draft}"]), "nightmail send")
        self.assertEqual(claude_rules.command_words(["nightdrive", "notifications", "dnd", "on", "--json"]),
                         "nightdrive notifications dnd on")
        self.assertEqual(claude_rules.command_words(["tasks", "add", ["--due", "{due}"], "{title}"]), "tasks add")


class LocalSettings(unittest.TestCase):
    def warnings(self, text, settings=None):
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp)
            (home / ".claude").mkdir()
            if text is not None:
                (home / ".claude/settings.local.json").write_text(text)
            with mock.patch.object(claude_rules, "HOME", home), \
                    mock.patch.object(claude_rules, "SETTINGS", home / ".claude/settings.json"), \
                    mock.patch.object(claude_rules, "SETTINGS_LOCAL", home / ".claude/settings.local.json"), \
                    mock.patch.object(claude_rules, "kept_commands", lambda: ["nightmail send"]), \
                    mock.patch.object(claude_rules, "guarded_paths", lambda: set()):
                return claude_rules.warnings({} if settings is None else settings)

    def test_named(self):
        out = self.warnings(json.dumps({"permissions": {"allow": ["Bash(git status)", "Bash(nightmail *)"]}}))
        self.assertEqual(len(out), 1)
        self.assertIn("Bash(nightmail *) allowed in ~/.claude/settings.local.json", out[0])

    def test_both_files(self):
        out = self.warnings(json.dumps({"permissions": {"allow": ["Bash(nightmail send:*)"]}}),
                            {"permissions": {"allow": ["Bash(wtype *)"]}})
        self.assertEqual(len(out), 2)
        self.assertIn("Bash(wtype *) allowed in ~/.claude/settings.json", out[0])
        self.assertIn("Bash(nightmail send:*) allowed in ~/.claude/settings.local.json", out[1])

    def test_missing_or_broken(self):
        for text in (None, "", "{", "[]"):
            self.assertEqual(self.warnings(text), [])


if __name__ == "__main__":
    unittest.main()
