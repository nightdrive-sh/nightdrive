#!/usr/bin/env python3
"""Claude Code's sign-in running out, seen from Nightdrive's background uses of `claude -p` (#3664).

claude -p prints "Warning: this sign-in ends between … Run claude auth login before then …" on stderr in the last days
of a sign-in. Claude writes, Ask Claude, Mail's replies and Translate keep stderr out of their text (#3661), so they
hand it here instead, and the user gets one notification a day per account, with a button that signs in again.

  claude-signin warn [FILE] [--json] [--dry-run]   read claude -p's stderr (FILE, or stdin); on a sign-in warning,
                                                   notify unless this account was told today. --json: what it found,
                                                   {found, line, ended, account, dir, shown}; --dry-run: no notification,
                                                   nothing marked as told
  claude-signin login [DIR]                        claude auth login on that account (its config dir; the default
                                                   ~/.claude), in this terminal: the notification's button runs it

The account is the config dir claude ran with: $CLAUDE_CONFIG_DIR, as the caller passes its own environment on, else
~/.claude. Its name is said only when there are several accounts (topbar/scripts/claude-accounts)."""

import datetime
import json
import os
import re
import shlex
import subprocess
import sys

HOME = os.path.expanduser("~")
STATE = os.path.join(HOME, ".local/state/nightdrive/claude-signin.json")   # {config dir: the day it was told}
ACCOUNTS = os.path.join(HOME, ".config/topbar/scripts/claude-accounts")
TERMINAL = os.path.join(HOME, ".config/hypr/scripts/terminal")
CLAUDE = os.path.join(HOME, ".local/bin/claude")
ICON = "claude"
# Claude Code's three wordings: ends between A and B / can end at any time from now until B / may have ended between
WARNING = re.compile(r"^\s*Warning: this sign-in (.+)$", re.M)
# Its advice for scripts, which isn't ours to give: our own line says what to do
SETUP_TOKEN = re.compile(r",? or use claude setup-token for unattended jobs\.?", re.I)


def find(stderr):
    """The warning's line, or None."""
    m = WARNING.search(stderr or "")
    return m.group(0).strip() if m else None


def config_dir(env=None):
    env = os.environ if env is None else env
    d = env.get("CLAUDE_CONFIG_DIR") or os.path.join(HOME, ".claude")
    return os.path.normpath(os.path.expanduser(d))


def account(d):
    """(name, how many accounts there are): the name is "" when it can't be told."""
    try:
        out = subprocess.run([ACCOUNTS, "--json"], capture_output=True, text=True, timeout=5).stdout
        rows = json.loads(out or "[]")
    except (OSError, ValueError, subprocess.SubprocessError):
        return "", 1
    name = next((r.get("name", "") for r in rows if os.path.normpath(r.get("dir", "")) == d), "")
    return name, len(rows)


def message(line, name="", several=False):
    """(title, body) for the notification, from Claude Code's line: its dates, without its advice (ours is last)."""
    ended = "may have ended" in line
    said = SETUP_TOKEN.sub(".", line.replace("Warning: this sign-in", "This sign-in", 1))
    # Up to its first full stop after the dates: "Renewing it does not move…" and its own advice are left out
    said = re.split(r"(?<=[.)])\s+(?=Renewing|Run claude|If requests)", said)[0].rstrip(".") + "."
    who = f" ({name})" if several and name else ""
    title = ("Claude Code's sign-in may have ended" if ended else "Claude Code's sign-in ends soon") + who
    # Short: the notification shows about six lines
    then = "If so, Claude writes, Ask Claude, Mail and Translate can't reach Claude." if ended else \
        "Claude writes, Ask Claude, Mail and Translate stop then."
    where = f" on the {name} account" if several and name else ""
    body = f"{said} {then} Sign in again{where}: Sign in, or claude auth login in a terminal."
    return title, body


def told_today(d, today):
    try:
        with open(STATE) as f:
            return json.load(f).get(d) == today
    except (OSError, ValueError):
        return False


def mark(d, today):
    try:
        with open(STATE) as f:
            state = json.load(f)
    except (OSError, ValueError):
        state = {}
    state[d] = today
    os.makedirs(os.path.dirname(STATE), exist_ok=True)
    tmp = STATE + ".tmp"
    with open(tmp, "w") as f:
        json.dump(state, f)
    os.replace(tmp, STATE)


def notify(title, body, d):
    """In the background, so the caller goes on while the notification waits for its click: Sign in opens a terminal
    with claude auth login on this account."""
    login = [TERMINAL, "--dir", HOME, "--", os.path.join(os.path.dirname(os.path.abspath(__file__)), "claude-signin"),
             "login", d]
    script = ('a=$(notify-send -a Claude -i "$1" -A login="Sign in" -w -- "$2" "$3"); '
              '[[ $a == login ]] && shift 3 && exec "$@"')
    env = {k: v for k, v in os.environ.items() if not k.startswith("CLAUDE")}   # the terminal's claude: no child session
    subprocess.Popen(["bash", "-c", script, "_", ICON, title, body] + login, env=env, start_new_session=True,
                     stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def warn(stderr, as_json=False, dry_run=False, env=None, today=None):
    line = find(stderr)
    d = config_dir(env)
    today = today or datetime.date.today().isoformat()
    out = {"found": bool(line), "line": line or "", "ended": bool(line and "may have ended" in line),
           "account": "", "dir": d, "shown": False}
    if line:
        name, count = account(d)
        out["account"] = name
        if not told_today(d, today):
            if not dry_run:
                notify(*message(line, name, count > 1), d)
                mark(d, today)
            out["shown"] = True
    if as_json:
        print(json.dumps(out))
    return 0


def login(d):
    env = {k: v for k, v in os.environ.items() if not k.startswith("CLAUDE")}
    if os.path.normpath(d) != os.path.join(HOME, ".claude"):
        env["CLAUDE_CONFIG_DIR"] = d
    claude = CLAUDE if os.access(CLAUDE, os.X_OK) else "claude"
    print(f"Signing Claude Code in again ({d}):\n  {shlex.join([claude, 'auth', 'login'])}\n", flush=True)
    rc = subprocess.run([claude, "auth", "login"], env=env).returncode
    try:
        input("\nDone. Press Enter to close." if rc == 0 else f"\nclaude auth login failed ({rc}). Press Enter to close.")
    except EOFError:
        pass
    return rc


USAGE = "usage: claude-signin warn [FILE] [--json] [--dry-run] | login [DIR]"


def main(argv):
    if argv[:1] == ["warn"]:
        args = argv[1:]
        as_json, dry = "--json" in args, "--dry-run" in args
        files = [a for a in args if not a.startswith("--")]
        try:
            text = open(files[0], errors="replace").read() if files else sys.stdin.read()
        except OSError:
            text = ""
        return warn(text, as_json, dry)
    if argv[:1] == ["login"]:
        return login(os.path.normpath(os.path.expanduser(argv[1])) if len(argv) > 1 else config_dir())
    print(USAGE, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
