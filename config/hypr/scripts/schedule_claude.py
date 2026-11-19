"""A scheduled line that is a message to Claude, not a command (Dashboard #3150): how schedule tells the two apart, which
session a message is for, and its delivery when its time comes. Imported by `schedule` (sys.path gets this folder, as
timers.py); `schedule send` runs deliver().

- **Command or message** (Jari 18.11.): a line is a command when its first word is a program in PATH (~/.local/bin
  too, as the run has it), a path to one, or `nightdrive`; anything else, a line sh can't parse among them ("don't
  forget"), is a message. `schedule --run` / `--claude` say it instead, and what was decided shows as it is added.
- **Where a message goes:** without --to, a new Claude Code session in a window of its own, opened as `nightdrive ask
  --background` opens one (Opus at medium, in ~/Projects, without the keyboard), the message as its first prompt. With
  --to SESSION (an id, or a name such as Nightdrive Project Manager: `nightdrive sessions`), that session: running, the
  message is typed into its window as Companion types (a warning's countdown first, as the window comes up and takes
  the keyboard); closed, it is resumed in a window of its own with the message as its prompt (claude --resume ID); gone
  altogether, a new session of that name gets it.
- **A name, not an id, is kept for a name:** the project manager starts a new conversation each time (ndpm), so the
  one running in the morning isn't the one that ran when the line was added in the evening.
- A session that waits for an answer (a permission, a question) isn't typed into: Enter there would answer it. It is
  waited on for WAIT_MINUTES, then the message fails with its notification, pinned, and nothing is sent.
"""
import json, os, re, shlex, shutil, subprocess, sys, time

HERE = os.path.dirname(os.path.realpath(__file__))
HISTORY = os.path.join(HERE, "../../topbar/scripts/claude-history")    # nightdrive sessions: running and closed
LIVE = os.path.join(HERE, "../../topbar/scripts/claude-sessions")      # the running ones' status (idle, busy, waiting)
NEW_SESSION = os.path.join(HERE, "terminal-or-claude")
NIGHTDRIVE = os.path.join(HERE, "../../../bin/nightdrive")
WARN = os.path.join(HERE, "agent-warn")
COMPANION_LIB = os.path.join(HERE, "../../companion/lib")             # control.py: typing into a session's window
SID = re.compile(r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$")
ASSIGN = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")                       # FOO=1 make: the command is make
WAIT_MINUTES = 10       # a session waiting for an answer is waited on this long before the message gives up
POLL = 5                # seconds between looks at its status
NAME_CHARS = 40         # of the message, in a new session's name


def search_path():
    """PATH as the run has it: ~/.local/bin added (schedule's run_command), so `ndpm` counts as a command."""
    path = os.environ.get("PATH", "/usr/bin:/bin")
    return os.path.expanduser("~/.local/bin") + ":" + path


def is_command(word):
    if word == "nightdrive":
        return True
    w = os.path.expanduser(word)
    if "/" in w:
        return os.path.isfile(w) and os.access(w, os.X_OK)
    return shutil.which(w, path=search_path()) is not None


def kind(words):
    """The words after WHEN → "run" or "claude". One word is a line as typed, read as sh would split it; several are
    the words as given. Variable assignments before the command are passed over."""
    words = [w for w in words if w.strip()]
    if not words:
        return "run"
    if len(words) == 1:
        try:
            words = shlex.split(words[0])
        except ValueError:          # an unclosed quote: an apostrophe in a sentence
            return "claude"
    first = next((w for w in words if not ASSIGN.match(w)), None)
    if first is None:
        return "run"                # only assignments: sh's to judge, as a command
    return "run" if is_command(first) else "claude"


def message(words):
    """The words after WHEN → the message: as written, without the quoting a command's words get."""
    return " ".join(w.strip() for w in words if w.strip())


def sessions():
    """Claude Code's sessions as `nightdrive sessions --json` gives them, running first, then the newest."""
    try:
        p = subprocess.run([HISTORY, "--json"], capture_output=True, text=True, timeout=120)
        return json.loads(p.stdout or "[]") if p.returncode == 0 else []
    except (OSError, subprocess.SubprocessError, ValueError):
        return []


class Ambiguous(ValueError):
    """A name that fits several sessions' names: asked again, never guessed."""


def target(given, found):
    """--to's session → what the row keeps: an id as it is, else the one name its sessions have (the same name, any
    case, else a part of one). ValueError, with what to say, when there is none or several names fit."""
    given = given.strip()
    if SID.match(given):
        if not any(s.get("id") == given for s in found):
            raise ValueError(f"No Claude Code session {given} (nightdrive sessions)")
        return given
    low = given.casefold()
    names = {s["name"] for s in found if s.get("name") and s["name"].casefold() == low}
    names = names or {s["name"] for s in found if s.get("name") and low in s["name"].casefold()}
    if not names:
        raise ValueError(f"No session named {given} (nightdrive sessions)")
    if len(names) > 1:
        raise Ambiguous(f"Several sessions fit {given}: " + ", ".join(sorted(names)) + ". Which one?")
    return names.pop()


def pick(key, found):
    """The session a message for key goes to: that id, or of those with that name the running one, else the newest."""
    if SID.match(key):
        fits = [s for s in found if s.get("id") == key]
    else:
        fits = [s for s in found if (s.get("name") or "").casefold() == key.casefold()]
    fits.sort(key=lambda s: (not (s.get("running") and s.get("address")), -(s.get("last") or 0)))
    return fits[0] if fits else None


def status(address):
    """A running session's status from claude-sessions: idle, busy, waiting; "" when its window is gone."""
    try:
        p = subprocess.run([LIVE], capture_output=True, text=True, timeout=30)
        live = json.loads(p.stdout or "[]")
    except (OSError, subprocess.SubprocessError, ValueError):
        return ""
    return next((s.get("status") or "idle" for s in live if s.get("address") == address), "")


def into_window(s, text):
    """Typed into a running session's window → (exit code, what happened). Not while it waits for an answer."""
    name = s.get("name") or s["id"]
    deadline = time.time() + WAIT_MINUTES * 60
    while (st := status(s["address"])) == "waiting" and time.time() < deadline:
        time.sleep(POLL)
    if st == "waiting":
        return 1, f"{name} was waiting for your answer: the message wasn't sent"
    if not st:
        return 1, f"{name}'s window closed: the message wasn't sent"
    # The window comes up and takes the keyboard: the same countdown an agent gives before opening a menu
    subprocess.run([WARN, f"{name}'s window"], env={**os.environ, "AGENT_NAME": "Schedule"},
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    if status(s["address"]) == "waiting":   # a question came during the countdown
        return 1, f"{name} was waiting for your answer: the message wasn't sent"
    if COMPANION_LIB not in sys.path:
        sys.path.insert(0, COMPANION_LIB)
    import control   # noqa: E402  Companion's typing: the clipboard, Shift+Insert, Enter, the clipboard back
    try:
        control.type_text(s["address"], text, True)
    except (ValueError, OSError, subprocess.SubprocessError) as e:
        return 1, f"Not sent to {name}: {e}"
    return 0, f"Sent to {name}, in its window"


def launch(argv):
    p = subprocess.run(argv, capture_output=True, text=True, stdin=subprocess.DEVNULL)
    return p.returncode, (p.stdout + p.stderr).strip()


def deliver(key, text, found=None):
    """The message to its session → (exit code, what happened, for the notification and the journal)."""
    s = pick(key, sessions() if found is None else found) if key else None
    if s and s.get("running") and s.get("address"):
        return into_window(s, text)
    if s:
        # Closed: on in a window of its own, in its folder on its account (Claude Code finds it by both), with the
        # model it had (nightdrive ask's Opus at medium is for new ones)
        code, out = launch([NEW_SESSION, "--background", "--dir", s["dir"], "--account", s.get("account") or "default",
                            "--resume", s["id"], "--", text])
        return code, out or f"{s.get('name') or s['id']} goes on in a new window"
    short = text if len(text) <= NAME_CHARS else text[:NAME_CHARS].rstrip() + "…"
    name = key if key and not SID.match(key) else "Scheduled: " + short
    code, out = launch([NIGHTDRIVE, "ask", "--background", "--name", name, "--", text])
    return code, out or f"A new session, {name}, in a window of its own"


def send_line(script, key, text):
    """The shell line schedule's run gives a message: `schedule send [--to KEY] -- TEXT`, run as a command is."""
    return shlex.join([script, "send", *(["--to", key] if key else []), "--", text])
