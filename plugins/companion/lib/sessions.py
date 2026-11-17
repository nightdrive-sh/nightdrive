"""The Claude Code sessions on this desktop, as the companion shows them (protocol.md › State).

Which windows run Claude comes from topbar/scripts/claude-sessions, the same as the bar's (quickshell/Claude.qml); what
each one is doing from its window's title, which Claude Code sets (✳ when it waits for you, a spinner while it works).
A permission request waiting in hypr/scripts/claude-notify leaves <address>.perm in its state folder, with what it asks
as JSON, and the hook takes <address>.answer as the answer (allow or deny).
"""
import json
import os
import re
import subprocess
import time

import transcript

HOME = os.path.expanduser("~")
SESSIONS = f"{HOME}/.config/topbar/scripts/claude-sessions"
STATE = os.path.join(os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}"), "nightdrive", "claude-notify")
WAITING_GLYPH = "✳"
LETTER = re.compile(r"[A-Za-z0-9À-ɏ]")


def _run_json(argv, default):
    try:
        out = subprocess.run(argv, capture_output=True, text=True, timeout=5).stdout
        return json.loads(out) if out.strip() else default
    except (OSError, subprocess.SubprocessError, ValueError):
        return default


def _parse_title(title):
    """("working" | "waiting", topic) from Claude Code's window title, as Claude.qml reads it."""
    m = re.match(r"^(\S)\s+(.*)$", title or "")
    if not m or m.group(1) == WAITING_GLYPH or LETTER.match(m.group(1)):
        return "waiting", (m.group(2) if m and not LETTER.match(m.group(1)) else title) or ""
    return "working", m.group(2)


def _permission(address):
    """What the session's permission request asks, or None. An old hook only touches the file: then Deny alone."""
    path = os.path.join(STATE, f"{address}.perm")
    try:
        with open(path) as f:
            text = f.read().strip()
    except OSError:
        return None
    try:
        p = json.loads(text) if text else {}
    except ValueError:
        p = {}
    return {"tool": p.get("tool", "a tool"), "what": p.get("what", ""), "allow": bool(p.get("allow"))}


class Sessions:
    """Keeps what changed between looks: a session that went from working to waiting while its window wasn't the
    active one wants you, until it works again or you go to it (here or on the desktop)."""

    def __init__(self):
        self.last_state = {}
        self.wants = set()

    def look(self):
        found = _run_json([SESSIONS], [])
        clients = {c.get("address"): c for c in _run_json(["hyprctl", "-j", "clients"], [])}
        active = _run_json(["hyprctl", "-j", "activewindow"], {}).get("address", "")
        out, seen = [], {}
        for f in found:
            addr = f.get("address", "")
            client = clients.get(addr)
            if not client:
                continue
            state, topic = _parse_title(client.get("title", ""))
            perm = _permission(addr)
            if perm:
                state = "permission"
            busy = "working" if state == "working" else "waiting"
            if self.last_state.get(addr) == "working" and busy == "waiting" and addr != active:
                self.wants.add(addr)
            if busy == "working" or addr == active:
                self.wants.discard(addr)
            seen[addr] = busy
            d = f.get("dir", "")
            out.append({
                "id": addr, "dir": d, "project": d.rstrip("/").split("/")[-1] or "/", "topic": topic,
                "state": state, "wants": addr in self.wants or state == "permission",
                "started": f.get("started", 0), "last": transcript.last(d, f.get("started", 0)),
                **({"permission": perm} if perm else {}),
            })
        self.last_state = seen
        self.wants &= set(seen)
        return _ordered(out)

    def seen(self, addr):
        """You looked at it here: it no longer wants you."""
        self.wants.discard(addr)

    def permission(self, addr):
        return _permission(addr)

    def answer(self, addr, decision):
        tmp = os.path.join(STATE, f".{addr}.answer")
        with open(tmp, "w") as f:
            f.write(decision)
        os.replace(tmp, os.path.join(STATE, f"{addr}.answer"))


def _ordered(sessions):
    """The ones that need you first (a permission request before a question), then the newest."""
    rank = {"permission": 0, "waiting": 1, "working": 2}
    return sorted(sessions, key=lambda s: (not s["wants"], rank[s["state"]], -s["started"]))


class Demo:
    """Made-up sessions that change over time, for a machine without Hyprland (and the sandbox, a screenshot)."""

    def __init__(self):
        self.t0 = time.time()
        self.answered = {}
        self.wants = {"demo-mail"}

    def look(self):
        now = time.time()
        k = int((now - self.t0) // 20) % 3
        perm = None if "demo-nd" in self.answered else {"tool": "Bash", "what": "nightdrive sandbox check", "allow": True}
        out = [
            {"id": "demo-nd", "project": "nightdrive", "dir": "~/dotfiles", "topic": "Companion proto",
             "state": "permission" if perm else "working", "started": now - 1500,
             "last": "Bash: nightdrive sandbox check", **({"permission": perm} if perm else {})},
            {"id": "demo-ferry", "project": "ferry", "dir": "~/Projects/ferry", "topic": "Relay port",
             "state": "waiting", "started": now - 2400,
             "last": "Keep the old relay port as a fallback, or drop it in this release?"},
            {"id": "demo-deck", "project": "deck-player", "dir": "~/Projects/deck", "topic": "Gapless playback",
             "state": "working", "started": now - 720,
             "last": ["Bash: cargo test --workspace", "Edit: src/queue.rs", "Read: src/decoder.rs"][k]},
            {"id": "demo-web", "project": "website", "dir": "~/Projects/nightdrive-website", "topic": "Docs contents",
             "state": "working", "started": now - 180, "last": "Edit: data/docs.json"},
            {"id": "demo-mail", "project": "mail", "dir": "~/dotfiles", "topic": "Thread sort order",
             "state": "waiting", "started": now - 3600,
             "last": "Threads sort by the newest reply again. Tests pass, nothing committed."},
        ]
        for s in out:
            s["wants"] = s["id"] in self.wants or s["state"] == "permission"
        return _ordered(out)

    def seen(self, addr):
        self.wants.discard(addr)

    def permission(self, addr):
        return next((s.get("permission") for s in self.look() if s["id"] == addr), None)

    def answer(self, addr, decision):
        self.answered[addr] = decision
