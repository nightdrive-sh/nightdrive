#!/usr/bin/env python3
"""Registers Nightdrive's MCP server in Claude Code: `nightdrive mcp install|remove|status` (plan: Dashboard #1761).

install does two things, and says what before doing them:
- `claude mcp add -s user nightdrive -- …/nightdrive mcp`, so every Claude Code session sees the server (the launcher's
  ⌘⌥Enter and `nightdrive ask` included). Claude writes and Mail's replies run `claude -p --strict-mcp-config`, which
  leaves user servers out, so they stay without it.
- `mcp__nightdrive__*` in permissions.allow of ~/.claude/settings.json, so Claude Code doesn't ask about each tool: the
  server asks itself, on its own card, for what has consequences. Asking twice would only teach the user to say yes.

What install added is written down (STATE), and remove takes away exactly that: a rule or a server the user had before
stays. Without Claude Code there is nothing to register, and that isn't an error.
"""

import argparse
import difflib
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

NAME = "nightdrive"                                   # the name in Claude Code: its tools are mcp__nightdrive__…
RULE = f"mcp__{NAME}__*"
HOME = Path.home()
SETTINGS = HOME / ".claude" / "settings.json"         # the user's own Claude Code settings
CLAUDE_JSON = HOME / ".claude.json"                   # where `claude mcp add -s user` keeps servers; only read here
STATE = HOME / ".local/state/nightdrive/mcp-install.json"
LINKED = HOME / ".local/bin/nightdrive"               # link.sh's link to the live checkout
REPO = Path(__file__).resolve().parents[2]


class Refused(Exception):
    """Stops the command with a message and exit 1. Raised before writing, except when `claude mcp` itself fails."""


def claude():
    """Claude Code's command, or None. ~/.local/bin is its installer's place and may not be in a script's PATH."""
    own = HOME / ".local/bin/claude"
    return str(own) if os.access(own, os.X_OK) else shutil.which("claude")


def server_command():
    """The command Claude Code starts: the linked `nightdrive` when it is this checkout, so the registration follows
    updates and survives a move; this checkout's own otherwise (a worktree), which is the one being tried out."""
    own = REPO / "bin" / "nightdrive"
    if LINKED.exists() and LINKED.resolve() == own.resolve():
        return [str(LINKED), "mcp"]
    return [str(own), "mcp"]


def registered():
    """The user-scope server called NAME as {command, args}, or None. Read from Claude Code's own file: `claude mcp get`
    starts the server to check it, too slow to merely ask whether it is there."""
    try:
        servers = json.loads(CLAUDE_JSON.read_text()).get("mcpServers") or {}
    except (OSError, ValueError):
        return None
    s = servers.get(NAME)
    return {"command": s.get("command"), "args": s.get("args") or []} if isinstance(s, dict) else None


def connected(cmd):
    """Claude Code's health check of the server: ✔ Connected, ✘ Failed… as `claude mcp get` says it."""
    try:
        out = subprocess.run([cmd, "mcp", "get", NAME], capture_output=True, text=True, timeout=30).stdout
    except (OSError, subprocess.TimeoutExpired):
        return "unknown"
    line = next((l for l in out.splitlines() if l.strip().startswith("Status:")), "")
    return line.split(":", 1)[1].strip() if line else "unknown"


# --- settings.json ------------------------------------------------------------------------------------------------

def read_settings():
    """(text, data): "" and {} when there is no file. A file that isn't a JSON object stops everything, as the user's
    other settings are in it and only they know what was meant."""
    try:
        text = SETTINGS.read_text()
    except FileNotFoundError:
        return "", {}
    try:
        data = json.loads(text)
    except ValueError as e:
        raise Refused(f"{SETTINGS} isn't valid JSON ({e}): fix it first, nothing was changed.")
    if not isinstance(data, dict):
        raise Refused(f"{SETTINGS} isn't a JSON object: nothing was changed.")
    return text, data


def dump(data):
    # Claude Code's own format (two spaces, a newline at the end), so the diff shows only what changed
    return json.dumps(data, indent=2, ensure_ascii=False) + "\n"


def update_settings(change, created=()):
    """Makes `change` (a function that edits the data) to the file as it is now, not as it was shown: Claude Code
    rewrites it at times (a first `claude mcp add` did), and what the user agreed to is the rule, not those bytes. A
    file install created and left empty goes. Atomic (a temporary file renamed over it), into the link's target when the
    file is a symlink, so the link stays."""
    text, data = read_settings()
    change(data)
    if "file" in created and not data:
        SETTINGS.unlink(missing_ok=True)
        return
    if dump(data) == text:
        return
    target = Path(os.path.realpath(SETTINGS))
    target.parent.mkdir(parents=True, exist_ok=True)
    mode = target.stat().st_mode & 0o777 if target.exists() else 0o644
    fd, tmp = tempfile.mkstemp(dir=target.parent, prefix=".settings.", suffix=".tmp")
    try:
        with os.fdopen(fd, "w") as f:
            f.write(dump(data))
        os.chmod(tmp, mode)
        os.replace(tmp, target)
    except BaseException:
        os.unlink(tmp)
        raise


# --- what install added -------------------------------------------------------------------------------------------

def load_state():
    try:
        return json.loads(STATE.read_text())
    except (OSError, ValueError):
        return {}


def save_state(state):
    if not state.get("server") and not state.get("rule"):
        STATE.unlink(missing_ok=True)
        return
    STATE.parent.mkdir(parents=True, exist_ok=True)
    STATE.write_text(json.dumps(state, indent=2) + "\n")


def allow_list(data):
    """permissions.allow, or [] when missing; anything but a list there stops everything, as with an invalid file."""
    perms = data.get("permissions", {})
    allow = perms.get("allow", []) if isinstance(perms, dict) else None
    if not isinstance(allow, list):
        raise Refused(f"permissions.allow in {SETTINGS} isn't a list: nothing was changed.")
    return allow


def allowed(allow):
    # mcp__nightdrive alone allows the whole server as well (Claude Code › Permissions)
    return RULE in allow or f"mcp__{NAME}" in allow


def add_rule(data):
    allow = allow_list(data)
    if not allowed(allow):
        data.setdefault("permissions", {}).setdefault("allow", allow).append(RULE)


def drop_rule(created):
    """The change that takes the rule away, and the containers install made for it once they are empty, so the file
    is as it was before."""
    def change(data):
        allow = allow_list(data)
        if RULE not in allow:
            return
        allow.remove(RULE)
        perms = data["permissions"]
        if "allow" in created and not allow:
            del perms["allow"]
        if "permissions" in created and not perms:
            del data["permissions"]
    return change


def preview(text, data, change, created=()):
    """The diff that `change` makes to the file as it is: what the user is shown and asked about."""
    after = json.loads(json.dumps(data))
    change(after)
    if "file" in created and not after:
        return f"  delete {SETTINGS}, which install created and nothing else is in"
    return "".join(difflib.unified_diff(text.splitlines(keepends=True), dump(after).splitlines(keepends=True),
                                        str(SETTINGS), str(SETTINGS), n=2)).rstrip()


def confirm(what, args):
    """Shows `what` and asks. True to go on; --dry-run stops after showing, and without a terminal to answer on only
    --yes goes on."""
    print(what)
    if args.dry_run:
        print("\n--dry-run: nothing was changed.")
        return False
    if args.yes:
        return True
    if not sys.stdin.isatty():
        raise Refused("\nNothing was changed: run it in a terminal to answer, or with --yes.")
    return input("\nGo ahead? [y/N] ").strip().lower() in ("y", "yes")


def run_claude(cmd, *argv):
    out = subprocess.run([cmd, "mcp", *argv], capture_output=True, text=True, timeout=60)
    if out.returncode != 0:
        raise Refused(f"claude mcp {argv[0]} failed: {(out.stderr or out.stdout).strip()}")


# --- the commands -------------------------------------------------------------------------------------------------

def install(args):
    cmd = claude()
    if not cmd:
        print("Claude Code isn't installed: there is nothing to register Nightdrive's server in.")
        return 0
    state, want, have = load_state(), server_command(), registered()
    have_cmd = have and [have["command"], *have["args"]]
    # a server of this name that install didn't add is someone else's choice: not replaced without being removed first
    # (the same command added by hand is fine as it is, and stays theirs)
    if have and have != state.get("server") and have_cmd != want:
        raise Refused(f"Claude Code already has a server called {NAME}: {' '.join(have_cmd)}\n"
                      f"Nothing was changed. To replace it: claude mcp remove {NAME} -s user, then install again.")
    text, data = read_settings()
    register, allow = have_cmd != want, not allowed(allow_list(data))
    if not register and not allow:
        print(f"Already installed: {' '.join(want)}, its tools allowed in {SETTINGS}.")
        return 0

    steps = []
    if register:
        instead = f" (in place of {' '.join(have_cmd)})" if have else ""
        steps.append(f"Register the server in Claude Code, for all your projects{instead}:\n"
                     f"  claude mcp add -s user {NAME} -- {' '.join(want)}")
    if allow:
        steps.append("Allow its tools in Claude Code, so it doesn't ask about each one (Nightdrive asks on screen for "
                     f"what has consequences):\n{preview(text, data, add_rule)}")
    if not confirm("\n\n".join(f"{i}. {s}" for i, s in enumerate(steps, 1)), args):
        return 0

    # settings.json first: a `claude mcp add` may rewrite the file, and after ours it keeps the rule
    text, data = read_settings()
    if allow and not allowed(allow_list(data)):   # the user may have allowed it meanwhile, and then it is theirs
        perms = data.get("permissions", {})
        missing = (("file", not text), ("permissions", "permissions" not in data), ("allow", "allow" not in perms))
        state.update(rule=True, created=[k for k, m in missing if m])
        save_state(state)   # before writing: a rule recorded but not written is only skipped by remove
        update_settings(add_rule)
    if register:
        if have:
            run_claude(cmd, "remove", NAME, "-s", "user")
        run_claude(cmd, "add", "-s", "user", NAME, "--", *want)
        state["server"] = {"command": want[0], "args": want[1:]}
        save_state(state)
    print("Installed. A new Claude Code session has Nightdrive's tools (`/mcp` lists them).")
    return 0


def remove(args):
    state, cmd, have = load_state(), claude(), registered()
    text, data = read_settings()
    created = state.get("created", [])
    server = bool(state.get("server")) and have == state.get("server") and bool(cmd)
    rule = bool(state.get("rule")) and RULE in allow_list(data)
    # what was taken away by hand since isn't install's any more
    if not server:
        state.pop("server", None)
    if not rule:
        state.pop("rule", None)
        state.pop("created", None)
    if not server and not rule:
        save_state(state)
        print("Nothing that `nightdrive mcp install` added is there.")
        if have:
            print(f"Claude Code's server {NAME} ({' '.join([have['command'], *have['args']])}) wasn't added by it: "
                  f"claude mcp remove {NAME} -s user removes it.")
        return 0

    steps = []
    if server:
        steps.append(f"Remove the server from Claude Code:\n  claude mcp remove {NAME} -s user")
    if rule:
        steps.append(f"Take away the rule that allows its tools:\n{preview(text, data, drop_rule(created), created)}")
    if not confirm("\n\n".join(f"{i}. {s}" for i, s in enumerate(steps, 1)), args):
        return 0

    if server:
        run_claude(cmd, "remove", NAME, "-s", "user")
        state.pop("server", None)
        save_state(state)
    if rule:
        update_settings(drop_rule(created), created)
        state.pop("rule", None)
        state.pop("created", None)
        save_state(state)
    print("Removed.")
    return 0


def status(args):
    cmd, have, state = claude(), registered(), load_state()
    try:
        allow = allow_list(read_settings()[1])
    except Refused:
        allow = []
    info = {
        "claude": cmd,
        "server": [have["command"], *have["args"]] if have else None,
        "connection": connected(cmd) if cmd and have else None,
        "allowed": allowed(allow),
        "byInstall": {"server": bool(state.get("server")), "rule": bool(state.get("rule"))},
    }
    if args.json:
        print(json.dumps(info, indent=2))
        return 0
    row = lambda k, v: print(f"{k:<13}{v}")
    row("Claude Code", cmd or "not installed")
    row("Server", f"{NAME}: {' '.join(info['server'])} – {info['connection']}" if have
        else "not registered (nightdrive mcp install)")
    row("Its tools", f"allowed ({RULE} in {SETTINGS})" if info["allowed"]
        else "Claude Code asks before each one (nightdrive mcp install allows them)")
    return 0


def main():
    p = argparse.ArgumentParser(prog="nightdrive mcp", description="Nightdrive's MCP server in Claude Code.")
    sub = p.add_subparsers(dest="command", required=True)
    for name, text in (("install", "register the server and allow its tools"),
                       ("remove", "take away what install added")):
        s = sub.add_parser(name, help=text)
        s.add_argument("--yes", action="store_true", help="don't ask")
        s.add_argument("--dry-run", action="store_true", help="only show what would change")
    sub.add_parser("status", help="whether it is registered and allowed").add_argument("--json", action="store_true")
    args = p.parse_args()
    try:
        return {"install": install, "remove": remove, "status": status}[args.command](args)
    except Refused as e:
        print(e, file=sys.stderr)
        return 1
    except (KeyboardInterrupt, EOFError):
        print("\nNothing more was changed.", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
