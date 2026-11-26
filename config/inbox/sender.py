"""Who left a message (#3132), found by itself so a session never has to say it (and can't get it wrong):

    {"kind": "claude", "session": id, "name": "#3132 Claude Inbox", "dir": "/home/…/dotfiles", "project": "dotfiles",
     "account": "default"}    a Claude Code session: from CLAUDE_CODE_SESSION_ID, which Claude Code gives its shell and
                              its MCP servers (so inbox_post's command has it too), and the session's record in
                              <account>/sessions/*.json for its name and folder
    {"kind": "app", "app": "Recorder"}           an app, by `--app NAME`
    {"kind": "other", "dir": "/home/…"}          anything else: a terminal, a script. The window marks these, as
                                                 nothing says who they are

None of this is proof: any process of the user's can set the same variables. It tells the user where to look, and a
run button is still shown whole and confirmed (actions.py), whoever sent it.
"""
import json
import os
import re
import subprocess
from pathlib import Path

HOME = Path.home()
ACCOUNTS = Path(__file__).resolve().parent.parent / "topbar/scripts/claude-accounts"
SESSION = re.compile(r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$")
TASK = re.compile(r"#(\d+)")
APP_MAX = 40


def config_dir(env):
    return Path(env.get("CLAUDE_CONFIG_DIR") or HOME / ".claude")


def account_name(cdir):
    """claude-accounts' name for the config dir (it may be renamed there), else its own: ~/.claude-work → work."""
    try:
        out = subprocess.run([str(ACCOUNTS), "name", str(cdir)], capture_output=True, text=True, timeout=5)
        if out.returncode == 0 and out.stdout.strip():
            return out.stdout.strip()
    except (OSError, subprocess.SubprocessError):
        pass
    if Path(cdir) == HOME / ".claude":
        return "default"
    return Path(cdir).name.lstrip(".").removeprefix("claude-") or "default"


def session_record(cdir, sid):
    """The newest record Claude Code keeps of the session (a resumed one's old record may linger): {} for none."""
    found = []
    for p in (Path(cdir) / "sessions").glob("*.json"):
        try:
            text = p.read_text()
            if f'"sessionId":"{sid}"' not in text.replace(" ", ""):
                continue
            found.append((p.stat().st_mtime, json.loads(text)))
        except (OSError, ValueError):
            continue
    return max(found, key=lambda f: f[0])[1] if found else {}


def task_of(name):
    m = TASK.search(name or "")
    return int(m.group(1)) if m else None


def detect(app=None, env=None, cwd=None):
    """The sender, from --app or the environment; cwd is the folder it was sent from (for a tool: the session's)."""
    env = os.environ if env is None else env
    cwd = str(cwd or env.get("NIGHTDRIVE_MCP_CWD") or os.getcwd())   # run.py: the session's folder, for a tool
    if app:
        return {"kind": "app", "app": " ".join(str(app).split())[:APP_MAX]}
    sid = env.get("CLAUDE_CODE_SESSION_ID", "")
    if not SESSION.match(sid):
        return {"kind": "other", "dir": cwd}
    cdir = config_dir(env)
    rec = session_record(cdir, sid)
    folder = rec.get("cwd") or cwd
    return {"kind": "claude", "session": sid, "name": rec.get("name") or "", "dir": folder,
            "project": Path(folder).name, "account": account_name(cdir)}


def same(a, b):
    """Whether two senders are the same one, for update: a session only adds to its own messages, an app to its own."""
    if a.get("kind") != b.get("kind"):
        return False
    key = {"claude": "session", "app": "app", "other": "dir"}.get(a.get("kind"))
    return bool(key) and a.get(key) == b.get(key)


def label(sender):
    """A short line for a terminal: "#3132 Claude Inbox · dotfiles", "Recorder", "a command in ~/x"."""
    kind = sender.get("kind")
    if kind == "claude":
        parts = [sender.get("name") or "Claude " + sender.get("session", "")[:8], sender.get("project")]
        if sender.get("account") not in (None, "", "default"):
            parts.append(sender["account"])
        return " · ".join(p for p in parts if p)
    if kind == "app":
        return sender.get("app") or "an app"
    return "a command in " + str(sender.get("dir") or "?").replace(str(HOME), "~", 1)
