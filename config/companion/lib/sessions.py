"""The Claude Code sessions on this desktop, as the companion shows them (protocol.md › State).

Which windows run Claude comes from topbar/scripts/claude-sessions, the same as the bar's (quickshell/Claude.qml); what
each one is doing from its window's title, which Claude Code sets (✳ when it waits for you, a spinner while it works).
A permission request waiting in hypr/scripts/claude-notify leaves <address>.perm in its state folder, with what it asks
and the request's id as JSON, and the hook takes <address>.answer as the answer ("allow ID" or "deny ID"): an answer
for another request of the session is thrown away. A question with choices (AskUserQuestion) comes to the same hook as
a permission request: it leaves <address>.ask instead, the questions whole, and takes "answer ID {question: answer}".
"""
import json
import os
import re
import subprocess
import time

import transcript

HOME = os.path.expanduser("~")
# This checkout's own claude-sessions (it gives each session's transcript), else the desktop's
_REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.realpath(__file__)))))
SESSIONS = next((p for p in (f"{_REPO}/config/topbar/scripts/claude-sessions",
                             f"{HOME}/.config/topbar/scripts/claude-sessions") if os.access(p, os.X_OK)), "")
STATE = os.path.join(os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}"), "nightdrive", "claude-notify")
WAITING_GLYPH = "✳"
LETTER = re.compile(r"[A-Za-z0-9À-ɏ]")
REQUEST = re.compile(r"[A-Za-z0-9]{1,32}")      # mktemp's random part, in claude-notify
MAX_ANSWER = 4000                               # characters of one answer (words of your own)


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
    req = str(p.get("request", ""))
    return {"tool": p.get("tool", "a tool"), "what": p.get("what", ""), "request": req,
            "allow": bool(p.get("allow")) and bool(REQUEST.fullmatch(req))}


def _question(address):
    """The question the session asks with choices (claude-notify's <address>.ask), or None:
    {request, questions: [{question, header, multiSelect, options: [{label, description}]}]}."""
    try:
        with open(os.path.join(STATE, f"{address}.ask")) as f:
            q = json.load(f)
    except (OSError, ValueError):
        return None
    if not isinstance(q, dict) or not REQUEST.fullmatch(str(q.get("request", ""))):
        return None
    out = []
    for x in q.get("questions") or []:
        if isinstance(x, dict) and x.get("question"):
            out.append({"question": str(x["question"]), "header": str(x.get("header") or ""),
                        "multiSelect": x.get("multiSelect") is True,
                        "options": [{"label": str(o.get("label", "")), "description": str(o.get("description") or "")}
                                    for o in x.get("options") or [] if isinstance(o, dict) and o.get("label")]})
    return {"request": q["request"], "questions": out} if out else None


def check_answers(question, request, answers):
    """The answers to send, {question: text}, or ValueError: every question it asks answered, for the request shown."""
    if not question:
        raise ValueError("It no longer asks")
    if request != question["request"]:
        raise ValueError("It asks something else now: read it again")
    if not isinstance(answers, dict):
        raise ValueError("No answers")
    out = {}
    for q in question["questions"]:
        a = answers.get(q["question"])
        a = re.sub(r"[\x00-\x1f\x7f]+", " ", a).strip() if isinstance(a, str) else ""
        if not a:
            raise ValueError(f"Answer “{q['header'] or q['question']}” too")
        out[q["question"]] = a[:MAX_ANSWER]
    return out


class Sessions:
    """Keeps what changed between looks: a session that went from working to waiting while its window wasn't the
    active one wants you, until it works again or you go to it (here or on the desktop)."""

    def __init__(self):
        self.last_state = {}
        self.wants = set()
        self.listed = {}               # the windows the last look found running Claude Code → (transcript, dir, started)
        self.active = {}               # the window that has the keyboard: where the dictation button types

    def look(self):
        found = _run_json([SESSIONS], [])
        clients = {c.get("address"): c for c in _run_json(["hyprctl", "-j", "clients"], [])}
        win = _run_json(["hyprctl", "-j", "activewindow"], {})
        active = win.get("address", "") if isinstance(win, dict) else ""
        out, seen, listed = [], {}, {}
        for f in found:
            addr = f.get("address", "")
            client = clients.get(addr)
            if not client:
                continue
            state, topic = _parse_title(client.get("title", ""))
            perm = _permission(addr)
            if perm:
                state = "permission"
            question = None if perm else _question(addr)
            busy = "working" if state == "working" else "waiting"
            if self.last_state.get(addr) == "working" and busy == "waiting" and addr != active:
                self.wants.add(addr)
            if question:
                self.wants.add(addr)
            elif busy == "working" or addr == active:
                self.wants.discard(addr)
            seen[addr] = busy
            d = f.get("dir", "")
            listed[addr] = (f.get("transcript"), d, f.get("started", 0))
            out.append({
                "id": addr, "dir": d, "project": d.rstrip("/").split("/")[-1] or "/", "topic": topic,
                # its own name (/rename; Claude Code's record, via claude-sessions), else the window title's topic
                "name": f.get("name") or topic,
                "state": state, "wants": addr in self.wants or state == "permission",
                # when its status last changed (claude-sessions): how long this turn has worked, or it has waited
                "since": f.get("since") or f.get("started", 0),
                "started": f.get("started", 0), "last": transcript.last(f.get("transcript"), d, f.get("started", 0)),
                # done as the sessions bar has it (Claude.qml): waiting, not asking or working, the last reply's last
                # line signing off with ✅
                "done": state == "waiting" and f.get("status") not in ("waiting", "busy")
                        and str(f.get("last", "")).startswith("✅"),
                # waiting for you in the terminal (AskUserQuestion: "input needed"), whose question only shows there
                "asks": f.get("waitingFor", "") if f.get("status") == "waiting" and state != "permission" else "",
                **({"permission": perm} if perm else {}),
                # the question whole, with its choices, while claude-notify waits for Companion's answer
                **({"question": question} if question else {}),
            })
        self.last_state = seen
        self.listed = listed
        self.active = _active(win, out) if active else {}
        self.wants &= set(seen)
        return _ordered(out)

    def window(self, addr):
        """addr, when it is a session's window: the page sends and stops only there, never into another window."""
        if addr not in self.listed:
            raise ValueError("No such session (it may have ended)")
        return addr

    def active_is_session(self):
        """Whether the window that has the keyboard now is a session's: the dictation button presses Enter there."""
        win = _run_json(["hyprctl", "-j", "activewindow"], {})
        return isinstance(win, dict) and win.get("address") in self.listed

    def log(self, addr):
        """What it said and did lately (transcript.recent), for its own view on the page."""
        path, d, started = self.listed.get(self.window(addr), ("", "", 0))
        return transcript.recent(path, d, started) if path or d else []

    def seen(self, addr):
        """You looked at it here: it no longer wants you."""
        self.wants.discard(addr)

    def permission(self, addr):
        return _permission(addr)

    def answer(self, addr, decision, request):
        if not REQUEST.fullmatch(request):
            raise ValueError("Answer it in its terminal")
        tmp = os.path.join(STATE, f".{addr}.answer")
        with open(tmp, "w") as f:
            f.write(f"{decision} {request}\n")
        os.replace(tmp, os.path.join(STATE, f"{addr}.answer"))

    def question(self, addr):
        return _question(addr)

    def reply(self, addr, request, answers):
        """Answers its question (check_answers): the hook gives them to Claude Code as the terminal would."""
        answers = check_answers(_question(addr), request, answers)
        tmp = os.path.join(STATE, f".{addr}.answer")
        with open(tmp, "w") as f:
            f.write(f"answer {request} {json.dumps(answers, ensure_ascii=False)}\n")
        os.replace(tmp, os.path.join(STATE, f"{addr}.answer"))


def _active(win, found):
    """The active window as the dictation button shows it: a session by its name and project (and Enter sends the words
    as its prompt), any other window by its class and title."""
    s = next((s for s in found if s["id"] == win.get("address")), None)
    if s:
        return {"session": s["id"], "name": s["name"] or s["project"], "detail": s["project"] if s["name"] else ""}
    return {"session": "", "name": win.get("class", "") or "a window", "detail": win.get("title", "")}


PM = re.compile(r"project manager|\bpm\b", re.I)


def _is_pm(s):
    """A project manager's session (nightdrive-pm, "Cold Start Project Manager"): it runs the others, so it goes first."""
    return bool(PM.search(s.get("name", "")) or PM.search(s.get("topic", ""))
                or PM.search(s.get("project", "").replace("-", " ")))


def _ordered(sessions):
    """The project managers first, marked pm (the robot, never done: as the sessions bar's leads), then the rest in the
    order they were started, each tile keeping its place: sorted by what they need, they moved under your finger
    whenever one changed. What needs you shows in the tile's colour."""
    for s in sessions:
        s.setdefault("name", s.get("topic", ""))
        s.setdefault("since", s.get("started", 0))
        s["pm"] = _is_pm(s)
        s["done"] = s.get("done", False) and not s["pm"]
    return sorted(sessions, key=lambda s: (not s["pm"], s["started"], s["id"]))


class Demo:
    """Made-up sessions that change over time, for a machine without Hyprland (and the sandbox, a screenshot)."""
    active = {"session": "demo-mail", "name": "Thread sort order", "detail": "mail"}

    def __init__(self):
        self.t0 = time.time()
        self.answered = {}
        self.wants = {"demo-mail"}

    def look(self):
        now = time.time()
        k = int((now - self.t0) // 20) % 3
        perm = None if "demo-nd" in self.answered else {"tool": "Bash", "what": "nightdrive sandbox check",
                                                           "request": "demo", "allow": True}
        out = [
            {"id": "demo-nd", "project": "nightdrive", "dir": "~/dotfiles", "topic": "Companion proto",
             "state": "permission" if perm else "working", "started": now - 1500,
             "last": "Bash: nightdrive sandbox check", **({"permission": perm} if perm else {})},
            {"id": "demo-ferry", "project": "ferry", "dir": "~/Projects/ferry", "topic": "Relay port",
             "state": "waiting", "started": now - 2400, "done": True,
             "last": "Keep the old relay port as a fallback, or drop it in this release?"},
            {"id": "demo-deck", "project": "deck-player", "dir": "~/Projects/deck", "topic": "Gapless playback",
             "state": "working", "started": now - 720,
             "last": ["Bash: cargo test --workspace", "Edit: src/queue.rs", "Read: src/decoder.rs"][k]},
            {"id": "demo-web", "project": "website", "dir": "~/Projects/nightdrive-website", "topic": "Docs contents",
             "state": "working", "started": now - 180, "last": "Edit: data/docs.json"},
            {"id": "demo-mail", "project": "mail", "dir": "~/dotfiles", "topic": "Thread sort order",
             "state": "waiting", "started": now - 3600,
             "last": "Threads sort by the newest reply again. Tests pass, nothing committed.",
             **({} if "demo-mail" in self.answered else {"asks": "input needed", "question": DEMO_QUESTION})},
        ]
        for s in out:
            s["wants"] = s["id"] in self.wants or s["state"] == "permission"
        return _ordered(out)

    def seen(self, addr):
        self.wants.discard(addr)

    def active_is_session(self):
        return True

    def window(self, addr):
        if not any(s["id"] == addr for s in self.look()):
            raise ValueError("No such session (it may have ended)")
        return addr

    def log(self, addr):
        s = next(s for s in self.look() if s["id"] == self.window(addr))
        return [{"role": "user", "kind": "text", "text": f"Let's work on {s['topic'].lower()} in {s['project']}."},
                {"role": "assistant", "kind": "text", "text": "Looking at it now."},
                {"role": "assistant", "kind": "tool", "text": "Read: src/main.rs"},
                {"role": "assistant", "kind": "text", "text": s["last"]}]

    def permission(self, addr):
        return next((s.get("permission") for s in self.look() if s["id"] == addr), None)

    def answer(self, addr, decision, request):
        self.answered[addr] = decision

    def question(self, addr):
        return next((s.get("question") for s in self.look() if s["id"] == addr), None)

    def reply(self, addr, request, answers):
        self.answered[addr] = check_answers(self.question(addr), request, answers)


DEMO_QUESTION = {"request": "demoask", "questions": [
    {"question": "Which order should threads sort in?", "header": "Order", "multiSelect": False, "options": [
        {"label": "Newest reply", "description": "A thread moves up when someone answers in it, as in most mail apps."},
        {"label": "First message", "description": "Threads keep the place of the mail that started them."}]},
    {"question": "Where should the order be set?", "header": "Setting", "multiSelect": True, "options": [
        {"label": "Settings", "description": "Settings › Mail, for every account."},
        {"label": "Per folder", "description": "From the folder's menu, remembered for each folder."},
        {"label": "Nowhere", "description": "One order for all; no setting."}]},
]}
