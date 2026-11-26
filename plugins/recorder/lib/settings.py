#!/usr/bin/env python3
"""Recorder's settings, ~/.config/recorder/settings.json: read by the capture, the recordings' list and (later) the
transcription, and shown and changed in the window's Settings (⌘,) through `recorder config`, so all of them read one
file.

    settings.py get [--json]          every setting, the defaults filled in
    settings.py set KEY VALUE [--json] one changed; VALUE as the window gives it (on/off for a switch)

    get() -> dict      put(key, value) -> dict      recordings_dir() -> Path

folder: where recordings go (~/Recordings; RECORDINGS_DIR overrides it, for a test or a script). mic: the PipeWire
source's node name to record from, "" for the default input. model: "parakeet" (Parakeet int8 through voxtype-onnx,
fast, finds the language itself), "medium" (Whisper medium through voxtype: between the two) or "whisper" (Whisper
large-v3-turbo through voxtype: slower, more exact). language: Whisper's, "fi", "en" or "auto". transcribe_on_save: a saved recording is transcribed at once (Jari 5.11.: on).
"""

import json
import os
import sys
from pathlib import Path

CONFIG_DIR = Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config") / "recorder"
FILE = CONFIG_DIR / "settings.json"
DEFAULT_FOLDER = "~/Recordings"
DEFAULTS = {"folder": DEFAULT_FOLDER, "mic": "", "model": "parakeet", "language": "auto", "transcribe_on_save": True}
CHOICES = {"model": ("parakeet", "medium", "whisper"), "language": ("auto", "fi", "en")}
SWITCHES = ("transcribe_on_save",)


class SettingsError(Exception):
    pass


def get():
    try:
        data = json.loads(FILE.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        data = {}
    out = dict(DEFAULTS)
    if isinstance(data, dict):
        out.update({k: v for k, v in data.items() if k in DEFAULTS})
    for key, allowed in CHOICES.items():   # a hand-edited value the window couldn't show
        if out[key] not in allowed:
            out[key] = DEFAULTS[key]
    for key in SWITCHES:
        out[key] = bool(out[key])
    for key in ("folder", "mic"):
        if not isinstance(out[key], str):
            out[key] = DEFAULTS[key]
    out["folder"] = out["folder"].strip() or DEFAULT_FOLDER
    return out


def checked(key, value):
    """VALUE as typed (a string) made the setting's type, or SettingsError in plain words."""
    if key not in DEFAULTS:
        raise SettingsError(f"No setting {key}: there are {', '.join(DEFAULTS)}.")
    if key in SWITCHES:
        if isinstance(value, bool):
            return value
        if str(value).lower() in ("on", "true", "yes", "1"):
            return True
        if str(value).lower() in ("off", "false", "no", "0"):
            return False
        raise SettingsError(f"{key} is on or off.")
    value = str(value).strip()
    if key in CHOICES and value not in CHOICES[key]:
        raise SettingsError(f"{key} is one of {', '.join(CHOICES[key])}.")
    if key == "folder" and not value:
        value = DEFAULT_FOLDER
    return value


def put(key, value):
    data = get()
    data[key] = checked(key, value)
    FILE.parent.mkdir(parents=True, exist_ok=True)
    tmp = FILE.with_suffix(".tmp")
    tmp.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    tmp.replace(FILE)   # whole at once: the capture may read it at that moment
    return data


def recordings_dir():
    env = os.environ.get("RECORDINGS_DIR")
    return Path(os.path.expanduser(env or get()["folder"]))


def main(argv):
    as_json = "--json" in argv
    args = [a for a in argv if a != "--json"]
    try:
        if args[:1] == ["get"] and len(args) == 1:
            data = get()
        elif args[:1] == ["set"] and len(args) == 3:
            data = put(args[1], args[2])
        else:
            print(__doc__.split("\n\n")[1], file=sys.stderr)
            return 2
    except SettingsError as e:
        print(e, file=sys.stderr)
        return 1
    except OSError as e:
        print(f"The settings couldn't be saved: {e.strerror}.", file=sys.stderr)
        return 1
    data = dict(data, path=str(recordings_dir()))
    if as_json:
        print(json.dumps(data))
    else:
        for key, value in data.items():
            print(f"{key}: {'on' if value is True else 'off' if value is False else value}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
