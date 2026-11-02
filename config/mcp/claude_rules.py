#!/usr/bin/env python3
"""What in Claude Code's own permissions gets round Nightdrive's limits, in plain words: `nightdrive mcp status` names
each rule (register.py), and Settings › Claude › Access shows the same lines (status --json's warnings).

Nightdrive's card and Access keep only its own tools back: a rule in Claude Code's settings that lets it run the same
command, change Access, type on the desktop or change the server's code and settings, does what the tools can't
without asking (Dashboard #1837, #1885, #1928). Read from the user's settings.json and settings.local.json, which hold
for every session (the second for those started in home too); another project's own .claude/settings apply in that
project alone, and aren't looked into.

`python3 claude_rules.py` prints the warnings for this user's settings.
"""

import json
import os
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import access  # noqa: E402  (after the path above)
import registry  # noqa: E402

HOME = Path.home()
REPO = Path(__file__).resolve().parents[2]
SETTINGS = HOME / ".claude" / "settings.json"
SETTINGS_LOCAL = HOME / ".claude" / "settings.local.json"

# Commands that run any other, or Nightdrive's own: a rule that lets them run with any arguments lets everything.
# Besides shells and interpreters: what runs a command it is given (timeout, nohup, find -exec, awk's system(), sed's
# e, git -c core.pager=…, make, npx, sqlite3's .shell, busybox sh), what writes any file (cp, tee, dd, curl -o,
# patch: claude-access.json too), and what starts things on the desktop (hyprctl dispatch exec, qs with a config of its
# own, gio launch, xdg-open a .desktop file) (#1885, #1928)
ANY_COMMAND = re.compile(r"(?:ba|z|da|fi|k|c|tc)?sh|python[\d.]*|perl|ruby|node|deno|bun|lua|php|tclsh|env|xargs|exec|"
                         r"eval|command|builtin|source|sudo|doas|pkexec|run0|su|systemd-run|flatpak-spawn|flatpak|"
                         r"timeout|nohup|setsid|nice|ionice|stdbuf|chrt|taskset|time|watch|script|strace|ltrace|gdb|"
                         r"unshare|nsenter|chroot|bwrap|firejail|parallel|find|fd|awk|[gm]awk|g?sed|git|make|cmake|"
                         r"just|npx|npm|pnpm|yarn|uvx?|pipx?|poetry|cargo|go|docker|podman|toolbox|distrobox|ssh|"
                         r"cp|mv|install|ln|tee|dd|rsync|tar|unzip|curl|wget|truncate|vim?|nvim|emacs|ed|ex|patch|"
                         r"sponge|sqlite3|busybox|toybox|socat|expect|at|batch|crontab|"
                         r"hyprctl|qs|quickshell|gio|xdg-open|gtk-launch|kitty|foot|ghostty|alacritty|wezterm|tmux|"
                         r"screen|systemctl|dbus-send|gdbus|busctl|"
                         r"nightdrive|nightmail|contacts|calendar|notes|tasks|ferry|home-assistant|software-\w+")
# One subcommand that runs whatever follows it: Bash(uv run *) is as open as Bash(uv *)
ANY_SUBCOMMAND = re.compile(r"(?:uv (?:tool )?run|npm (?:exec|x)|pnpm (?:exec|dlx)|yarn dlx|poetry run|pipx run|"
                            r"git -c|hyprctl dispatch|flatpak run|docker run|podman run|gio (?:launch|open)|"
                            r"qs (?:-p|--path|-c|--config))[\s:]*\*.*")
# Commands that take one to run anywhere in their arguments (find -exec, sed's e, xargs): with a * at the end, what
# Claude adds there is theirs, so Bash(find ~/Notes -name *) runs anything too
EXEC_ANYWHERE = re.compile(r"find|fd|xargs|parallel|g?sed")
# What types or clicks on the desktop: Enter on Nightdrive's card is the user's Allow, whoever pressed it. With any
# arguments or none (Bash(wtype -k Return) is all it takes)
INPUT = re.compile(r"wtype|ydotool|xdotool|dotoolc?|wlrctl|kdotool")
# What changes Access, or what it allowed once (#1929), from the command line; `nightdrive mcp access` alone and
# `allowed` only show it
ACCESS_COMMANDS = tuple(f"nightdrive mcp access {w}" for w in ("level", "set", "option", "forget"))
# What Claude Code may change with Edit or Write that raises Nightdrive's limits or Claude Code's own: the Access file,
# its first-time allowances and the install's note (#1885), the list of plugins that are on, which names the folders
# their tools come from (#1928), and Claude Code's settings. A rule whose path covers one of them (Edit, Write(**),
# Edit(~/.config/**), Write(~/.cache/**)) is named like a rule that runs anything.
GUARDED_FILES = (".config/nightdrive/claude-access.json", ".config/nightdrive/claude-allowed.json",
                 ".local/state/nightdrive/mcp-install.json", ".cache/nightdrive/plugins.d/active",
                 ".claude/settings.json", ".claude/settings.local.json", ".claude.json")
# And the code that runs: the server, its command, the desktop scripts its tools run, the plugins (their mcp.json and
# commands); each plugin that is on from outside this checkout too. Their docs (*.md) don't run.
GUARDED_FOLDERS = ("config/mcp", "bin", "config/hypr/scripts", "plugins")
SKIPPED = {"__pycache__", "node_modules"}
EDIT_TOOLS = ("Edit", "Write", "MultiEdit", "NotebookEdit")


def bash_inner(rule):
    """What is in a Bash rule's parentheses, stripped ("" for Bash alone); None for any other rule."""
    m = re.fullmatch(r"Bash(?:\((.*)\))?", rule.strip()) if isinstance(rule, str) else None
    return (m.group(1) or "").strip() if m else None


def rule_tool(rule):
    """The Claude Code tool a permission rule is for: Bash, Edit, mcp__nightdrive__…; None for what isn't a rule."""
    m = re.match(r"\s*(\w+)", rule) if isinstance(rule, str) else None
    return m[1] if m else None


def split_command(inner):
    """(the command's name, the rest): Bash(~/.local/bin/nightdrive mcp *) is nightdrive's, as on PATH."""
    first = re.split(r"[\s:]", inner, maxsplit=1)[0]
    return Path(first).name, inner[len(first):].lstrip(" :")


def any_command(rule):
    """Whether one permissions.allow rule lets Claude Code run any command: Bash, Bash(*), Bash(*:*), or any arguments
    to a shell, an interpreter, a command that runs or writes anything, or one of Nightdrive's own commands
    (Bash(nightdrive *), Bash(python3:*), Bash(timeout *)), a subcommand that runs anything (Bash(uv run *)), or a *
    at the end for one that takes a command anywhere (Bash(find . -name *))."""
    inner = bash_inner(rule)
    if inner is None:
        return False
    if inner in ("", ":*") or inner.startswith("*"):
        return True
    # Any arguments to the command itself; not one subcommand of it (Bash(nightdrive release *)) nor one command as it
    # is (Bash(nightdrive mcp status))
    name, rest = split_command(inner)
    if rest.startswith("*"):
        return bool(ANY_COMMAND.fullmatch(name))
    return bool(ANY_SUBCOMMAND.fullmatch(f"{name} {rest}")) or (bool(EXEC_ANYWHERE.fullmatch(name))
                                                                and inner.endswith("*"))


def types_input(rule):
    """Whether a Bash rule lets Claude Code press keys or click: Bash(wtype *), Bash(ydotool key 28:1 28:0)."""
    inner = bash_inner(rule)
    return bool(inner) and bool(INPUT.fullmatch(split_command(inner)[0]))


def command_words(argv):
    """A tool's command as far as it is the same on every call: its name and subcommands, up to the first option or
    argument (nightmail send {draft} --check is "nightmail send")."""
    words = []
    for i, a in enumerate(argv):
        if not isinstance(a, str) or a.startswith("-") or "{" in a:
            break
        words.append(Path(a).name if i == 0 else a)
    return " ".join(words)


def kept_commands(tools=None, rules=None):
    """The commands that Nightdrive runs only once its card or Access allows them: every act tool's, a tool's whose
    right Access sets to Ask or No, one's that asks when it reaches further (asks_if), and those that change Access.
    Read from the tools that are on, as the server lists them, and the user's Access as it is now."""
    tools = registry.all_tools()[0].values() if tools is None else tools
    rules = access.load() if rules is None else rules
    kept = set(ACCESS_COMMANDS)
    for tool in tools:
        if rules.decide(tool.cls, tool.area, tool.right) != "allow" or tool.spec.get("asks_if"):
            words = command_words(tool.spec["command"])
            # A name alone (python3, ./send-files) is a command that runs anything, caught as such, or none on PATH
            if " " in words:
                kept.add(words)
    return sorted(kept)


def runs_kept(rule, kept):
    """Whether a Bash rule lets Claude Code run one of the kept commands: one that covers it with a * (Bash(nightmail
    send *), Bash(nightdrive mcp *)), or names it with arguments (Bash(nightmail send 42 --check))."""
    inner = bash_inner(rule)
    if not inner:
        return False
    name, rest = split_command(inner)
    command = re.sub(r"\s+", " ", f"{name} {re.sub(r':[*]$', ' *', rest)}".strip())
    star = command.find("*")
    if star < 0:
        # Not the kept words alone: Bash(nightdrive network) is the status, network_off's is `… network {what} off`
        return any(command.startswith(f"{k} ") for k in kept)
    fixed = command[:star]   # what comes before the first *: a command that starts with it is allowed
    return any(f"{k} ".startswith(fixed) or fixed.startswith(f"{k} ") for k in kept)


def glob_regex(pattern):
    """A permission rule's path as a regex over absolute paths, the way Claude Code reads it (gitignore's): ** any
    folders, * and ? within one name. //x is /x, ~/x is in home, and a path of its own (x, ./x, /x) is taken from
    home, as a session started there sees it."""
    if pattern.startswith("//"):
        pattern = pattern[1:]
    elif pattern.startswith("~/"):
        pattern = f"{HOME}/{pattern[2:]}"
    else:
        pattern = f"{HOME}/{pattern.removeprefix('./').lstrip('/')}"
    out, i = "", 0
    while i < len(pattern):
        if pattern.startswith("**/", i):
            out, i = out + "(?:.*/)?", i + 3
        elif pattern.startswith("**", i):
            out, i = out + ".*", i + 2
        elif pattern[i] == "*":
            out, i = out + "[^/]*", i + 1
        elif pattern[i] == "?":
            out, i = out + "[^/]", i + 1
        else:
            out, i = out + re.escape(pattern[i]), i + 1
    return re.compile(out.rstrip("/"))


def code_files(folder):
    """The files in a folder that can run or be read as a tool's definition: all but docs, caches and hidden ones."""
    for top, dirs, files in os.walk(folder):
        dirs[:] = [d for d in dirs if d not in SKIPPED and not d.startswith(".")]
        yield from (Path(top) / f for f in files if not f.endswith(".md"))


def guarded_paths(folders=None):
    """Every path an Edit or Write rule must not reach, as strings: GUARDED_FILES, the code in GUARDED_FOLDERS and in
    each plugin that is on, and the folders above them all (a rule for a folder covers what is in it)."""
    folders = [REPO / f for f in GUARDED_FOLDERS] + [d for _, d in registry.plugin_folders()] \
        if folders is None else folders
    targets = [HOME / f for f in GUARDED_FILES] + [p for d in folders for p in (Path(d), *code_files(d))]
    return {str(p) for t in targets for p in (t, *t.parents)}


def edits_guarded(rule, paths=None):
    """Whether one permissions.allow rule lets Claude Code change a guarded file without asking: Edit or Write alone,
    or with a path that covers one."""
    m = re.fullmatch(r"(\w+)(?:\((.*)\))?", rule.strip()) if isinstance(rule, str) else None
    if not m or m.group(1) not in EDIT_TOOLS:
        return False
    inner = (m.group(2) or "").strip()
    if inner in ("", "*", "**", "/**", "//**", "~/**"):
        return True
    regex = glob_regex(inner)
    return any(regex.fullmatch(p) for p in (guarded_paths() if paths is None else paths))


def wide_open(data, where=None, kept=None, paths=None):
    """What in a settings file lets Claude Code past Nightdrive's limits, in plain words, each rule named; [] when
    nothing does. kept and paths (kept_commands, guarded_paths) are read when a rule needs them."""
    perms = data.get("permissions") if isinstance(data, dict) else None
    if not isinstance(perms, dict):
        return []
    out, where = [], where or f"~/{SETTINGS.relative_to(HOME)}"
    if perms.get("defaultMode") == "bypassPermissions":
        out.append(f"Claude Code doesn't ask before anything (defaultMode bypassPermissions in {where}): it can run "
                   "any command, and so get round these limits.")
    if perms.get("defaultMode") == "acceptEdits":
        out.append(f"Claude Code changes files without asking (defaultMode acceptEdits in {where}): a session started "
                   "in your home folder can change Nightdrive's settings, and so get round these limits.")
    allow = [r for r in perms.get("allow") or () if isinstance(r, str)] if isinstance(perms.get("allow"), list) else []
    anything = [r for r in allow if any_command(r)]
    typing = [r for r in allow if types_input(r) and r not in anything]
    rest = [r for r in allow if bash_inner(r) and r not in anything + typing]
    if rest and kept is None:
        kept = kept_commands()
    kept_rules = [r for r in rest if runs_kept(r, kept)]
    edit_rules = [r for r in allow if rule_tool(r) in EDIT_TOOLS]
    if edit_rules and paths is None:
        paths = guarded_paths()
    edits = [r for r in edit_rules if edits_guarded(r, paths)]
    named = lambda rules: f"{', '.join(rules)} allowed in {where}"
    if anything:
        out.append(f"Claude Code may run any command without asking ({named(anything)}): it can get round these "
                   "limits.")
    if kept_rules:
        out.append(f"Claude Code may run what Nightdrive's card or Access keeps back without asking "
                   f"({named(kept_rules)}): it can get round these limits.")
    if typing:
        out.append(f"Claude Code may type or click without asking ({named(typing)}): it can allow Nightdrive's card "
                   "itself.")
    if edits:
        out.append(f"Claude Code may change Nightdrive's settings, its tools or its own without asking "
                   f"({named(edits)}): it can get round these limits.")
    return out


def read_json(path):
    """A settings file's data; {} when it is missing or not JSON (it isn't ours to judge)."""
    try:
        return json.loads(Path(path).read_text())
    except (OSError, ValueError):
        return {}


def warnings(data=None):
    """The warnings of settings.json (its data as register.py read it, else read here) and settings.local.json."""
    data = read_json(SETTINGS) if data is None else data
    local = read_json(SETTINGS_LOCAL)
    rules = [r for d in (data, local) if isinstance(d, dict) and isinstance(d.get("permissions"), dict)
             for r in d["permissions"].get("allow") or () if isinstance(r, str)]
    # Each read once, and only when a rule needs it: Settings › Claude › Access asks on every visit
    kept = kept_commands() if any(bash_inner(r) for r in rules) else []
    paths = guarded_paths() if any(rule_tool(r) in EDIT_TOOLS for r in rules) else set()
    return wide_open(data, kept=kept, paths=paths) + wide_open(local, f"~/{SETTINGS_LOCAL.relative_to(HOME)}",
                                                               kept, paths)


if __name__ == "__main__":
    print("\n".join(warnings()) or "Nothing in Claude Code's settings gets round Nightdrive's limits.")
