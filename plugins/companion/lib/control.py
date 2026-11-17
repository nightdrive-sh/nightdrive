"""What the companion does on the desktop: types into a session or the window with the keyboard, stops a session, brings
a window up, starts a new session, and runs the five action slots (protocol.md › Sessions, Actions).

Typing goes the way Send to Claude pastes (hypr/scripts/claude-send-paste): the text on the clipboard, Shift+Insert in
the window, and the clipboard's old text back after the terminal has read it.
"""
import json
import os
import re
import subprocess
import time

HOME = os.path.expanduser("~")
SCRIPTS = f"{HOME}/.config/hypr/scripts"
CONFIG = f"{HOME}/.config/nightdrive/companion.json"
SLOTS = 5
FOCUS_WAIT = 0.25       # seconds for a window brought up to get the keyboard
RESTORE_DELAY = 0.8     # seconds before the clipboard gets its old text back: the terminal reads it when it pastes
MAX_TEXT = 8000         # characters a send takes

# The actions a slot can be without writing a command: id → (label, icon, argv)
PRESETS = {
    "lock": ("Lock", "lock", ["loginctl", "lock-session"]),
    "mic": ("Mute mic", "mic-off", ["wpctl", "set-mute", "@DEFAULT_AUDIO_SOURCE@", "toggle"]),
    "dnd": ("Do not disturb", "bell-off", [f"{SCRIPTS}/dnd"]),
    "play": ("Play / pause", "play", [f"{SCRIPTS}/media", "play"]),
    "next": ("Next track", "skip-forward", [f"{SCRIPTS}/media", "next"]),
    "claude": ("New Claude", "bot", [f"{SCRIPTS}/terminal-or-claude"]),
}


def _detach(argv):
    subprocess.Popen(argv, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                     start_new_session=True)


def _hypr(dispatch):
    subprocess.run(["hyprctl", "dispatch", dispatch], capture_output=True, timeout=5)


def _key(key, mods=""):
    _hypr(f'hl.dsp.send_shortcut({{ mods = "{mods}", key = "{key}" }})')


def focus(addr):
    if not re.fullmatch(r"0x[0-9a-f]+", addr):
        raise ValueError("Not a window")
    _hypr(f'hl.dsp.focus({{ window = "address:{addr}" }})')


def clean(text):
    """No control codes (an escape could end the terminal's bracketed paste, a carriage return send the prompt), and
    dictation's line breaks as spaces: one prompt, sent only by submit."""
    text = re.sub(r"[\x00-\x08\x0b-\x1f\x7f]", "", text)
    return re.sub(r"\s*\n\s*", " ", text).strip()[:MAX_TEXT]


def type_text(addr, text, submit):
    text = clean(text)
    if not text:
        raise ValueError("Nothing to send")
    if addr:
        focus(addr)
        time.sleep(FOCUS_WAIT)
    try:
        old = subprocess.run(["wl-paste", "--no-newline", "--type", "text"], capture_output=True, timeout=2)
        old = old.stdout if old.returncode == 0 else None
    except (OSError, subprocess.SubprocessError):
        old = None
    subprocess.run(["wl-copy", "--sensitive"], input=text.encode(), timeout=5)
    _key("Insert", "SHIFT")
    if submit:
        time.sleep(0.15)
        _key("Return")
    time.sleep(RESTORE_DELAY)
    if old is not None:
        subprocess.run(["wl-copy"], input=old, timeout=5)
    else:
        subprocess.run(["wl-copy", "--clear"], timeout=5)


def stop(addr):
    focus(addr)
    time.sleep(FOCUS_WAIT)
    _key("Escape")


def new_session(text):
    text = clean(text or "")
    _detach([f"{SCRIPTS}/terminal-or-claude", "--", text] if text else [f"{SCRIPTS}/terminal-or-claude"])


# The slots

def presets():
    return [{"id": k, "label": v[0], "icon": v[1]} for k, v in PRESETS.items()]


def load_actions():
    try:
        with open(CONFIG) as f:
            slots = json.load(f).get("actions", [])
    except (OSError, ValueError):
        slots = []
    slots = [s if isinstance(s, dict) else None for s in slots[:SLOTS]]
    return slots + [None] * (SLOTS - len(slots))


def public_actions():
    """The slots as the page shows them: a preset's label and icon filled in, a command not sent back."""
    out = []
    for s in load_actions():
        if s and s.get("preset") in PRESETS:
            label, icon, _ = PRESETS[s["preset"]]
            out.append({"label": label, "icon": icon, "preset": s["preset"]})
        elif s and s.get("command"):
            out.append({"label": s.get("label") or "Action", "icon": s.get("icon") or "zap", "custom": True})
        else:
            out.append(None)
    return out


def set_action(n, slot):
    if not 0 <= n < SLOTS:
        raise ValueError("No such slot")
    if slot is not None:
        if slot.get("preset"):
            if slot["preset"] not in PRESETS:
                raise ValueError("No such preset")
            slot = {"preset": slot["preset"]}
        elif str(slot.get("command", "")).strip():
            slot = {"label": str(slot.get("label") or "Action")[:40], "icon": str(slot.get("icon") or "zap")[:40],
                    "command": str(slot["command"])}
        else:
            raise ValueError("A slot needs a preset or a command")
    slots = load_actions()
    slots[n] = slot
    os.makedirs(os.path.dirname(CONFIG), exist_ok=True)
    try:
        with open(CONFIG) as f:
            data = json.load(f)
    except (OSError, ValueError):
        data = {}
    data["actions"] = slots
    tmp = CONFIG + ".tmp"
    with open(tmp, "w") as f:
        json.dump(data, f, indent=2)
    os.replace(tmp, CONFIG)


def run_action(n):
    slot = load_actions()[n] if 0 <= n < SLOTS else None
    if not slot:
        raise ValueError("The slot is empty")
    if slot.get("preset") in PRESETS:
        _detach(PRESETS[slot["preset"]][2])
    else:
        _detach(["bash", "-c", slot["command"]])
