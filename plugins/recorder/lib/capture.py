#!/usr/bin/env python3
"""The recording being made: pw-record as a process of its own, so it goes on with the window closed, and the keys and
the top bar can pause and save it too (`recorder toggle|pause|save|new`).

    capture.py status [--json]
    capture.py record [--json] [--mic NODE] [--name NAME]   start one, or go on with a paused one
    capture.py pause [--json]
    capture.py toggle [--json]                              record, pause or go on: what a single key does
    capture.py save [--json] [--name NAME]                  the pieces joined into NAME.wav in the recordings' folder
    capture.py new [--json] [--mic NODE] [--name NAME]      save, then start the next one at once

pw-record can't pause, so a recording is made of pieces: a pause ends the piece (SIGINT, so pw-record finishes its
header) and going on starts the next one. Save joins them (wav.join) into one WAV, 48 kHz mono 16-bit.

Where things are kept:
- the pieces and the recording's name, on disk: ~/.local/state/recorder/session/ (meta.json, piece-NNN.wav), so a
  crash or a power cut loses nothing;
- what is going on now (pw-record's pid, when the piece began, the seconds of the pieces before it), in
  $XDG_RUNTIME_DIR/recorder/state.json, which a reboot or a logout clears.
A Bluetooth headset (bluetooth.py) is recorded from by its card: the first piece switches it to its headset profile,
and meta.json keeps the profile it was in ("bt"), which save, a mic picked instead, or recover put back.
Pieces on disk without that state are a recording that was cut off: the next command joins them into
"NAME (recovered).wav" (recover). --json prints the state after the command: {state: idle|recording|paused, name,
mic, elapsed (seconds), started (ISO), saved: the recording save wrote, recovered: the one recover wrote}.
"""

import json
import os
import shutil
import signal
import subprocess
import sys
import time
import fcntl
from contextlib import contextmanager
from datetime import datetime
from pathlib import Path

import bluetooth
import recordings
import settings
import wav

STATE_HOME = Path(os.environ.get("XDG_STATE_HOME") or Path.home() / ".local/state")
SESSION = Path(os.environ.get("RECORDER_SESSION_DIR") or STATE_HOME / "recorder/session")
RUNTIME = Path(os.environ.get("XDG_RUNTIME_DIR") or f"/tmp/recorder-{os.getuid()}") / "recorder"
STATE = RUNTIME / "state.json"
PW_RECORD = os.environ.get("RECORDER_PW_RECORD", "pw-record")   # a test gives a fake one
RATE, CHANNELS, FORMAT = 48000, 1, "s16"   # speech: mono is enough, and half the size of stereo
NAME_FORMAT = "%Y-%m-%d %H.%M"             # a new recording's name: its day and time (no colons: USB sticks, Windows)
STOP_WAIT = 3.0                            # seconds pw-record gets to finish its header before it is killed
START_WAIT = 0.3                           # seconds a just-started pw-record must live, else it failed


class CaptureError(Exception):
    pass


# --- the state ------------------------------------------------------------------------------------------------------

def read_json(path):
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        return data if isinstance(data, dict) else None
    except (OSError, ValueError):
        return None


def write_json(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + ".tmp")
    tmp.write_text(json.dumps(data) + "\n", encoding="utf-8")
    tmp.replace(path)   # the bar's status reads it every second: never half a file


@contextmanager
def locked():
    """One command at a time: a key pressed twice quickly mustn't start two pw-records."""
    RUNTIME.mkdir(parents=True, exist_ok=True)
    with (RUNTIME / "lock").open("w") as f:
        fcntl.flock(f, fcntl.LOCK_EX)
        yield


def pieces():
    return sorted(SESSION.glob("piece-*.wav"))


def alive(pid, piece):
    """pid is still the pw-record writing piece (not a pid the system has since given to something else)."""
    try:
        cmdline = Path(f"/proc/{pid}/cmdline").read_bytes().split(b"\0")
    except (OSError, TypeError):
        return False
    return str(piece).encode() in cmdline


def current():
    """The runtime state, true to what is running: a pw-record that died by itself (a device gone) is a pause."""
    state = read_json(STATE)
    if not state or not read_json(SESSION / "meta.json"):
        return None
    if state.get("state") == "recording" and not alive(state.get("pid"), state.get("piece")):
        state.update(state="paused", pid=None, done=state.get("done", 0) + wav.duration(state.get("piece", "")))
        write_json(STATE, state)
    return state


def recover():
    """Pieces left by a recording that was cut off (no runtime state: a reboot, a logout) joined into a recording of
    their own, "NAME (recovered)"; its path, or None. Pieces with no sound are dropped."""
    if read_json(STATE) or not SESSION.exists():
        return None
    meta = read_json(SESSION / "meta.json") or {}
    give_back(meta)
    saved = None
    if pieces():
        name = recordings.clean_name(f"{meta.get('name') or 'Recording'} (recovered)")
        try:
            saved = write_recording(name)
        except wav.WavError:
            saved = None
    shutil.rmtree(SESSION, ignore_errors=True)
    return saved


# --- the microphone -------------------------------------------------------------------------------------------------

def target_of(mic, meta):
    """pw-record's --target for the mic: a Bluetooth card switched to its headset profile and its source, else the mic
    itself. meta (the session's, written back) keeps the profile to put back, from the first switch only."""
    if not bluetooth.is_card(mic):
        return mic
    try:
        source, previous = bluetooth.use(mic)
    except bluetooth.BluetoothError as e:
        raise CaptureError(str(e)) from None
    if previous and not meta.get("bt"):
        meta["bt"] = {"card": mic, "profile": previous}
        write_json(SESSION / "meta.json", meta)
    return source


def give_back(meta, keep=None):
    """The headset back in the profile it was in (A2DP), unless it is still the mic (keep)."""
    bt = meta.get("bt")
    if bt and bt.get("card") != keep:
        bluetooth.restore(bt.get("card"), bt.get("profile"))
        meta.pop("bt", None)
        if (SESSION / "meta.json").exists():
            write_json(SESSION / "meta.json", meta)


# --- pw-record --------------------------------------------------------------------------------------------------------

def start_piece(mic, done):
    piece = SESSION / f"piece-{len(pieces()) + 1:03}.wav"
    cmd = [PW_RECORD, "--rate", str(RATE), "--channels", str(CHANNELS), "--format", FORMAT,
           "-P", '{ "application.name": "Recorder", "node.description": "Recorder" }']
    if mic:
        cmd += ["--target", mic]
    log = (RUNTIME / "pw-record.log").open("w")
    since = time.time()   # before the start, so the clock shows what the file holds, START_WAIT included
    # Its own session: closing the window or the terminal that ran this doesn't stop it
    proc = subprocess.Popen(cmd + [str(piece)], stdin=subprocess.DEVNULL, stdout=log, stderr=log,
                            start_new_session=True)
    time.sleep(START_WAIT)
    if proc.poll() is not None:
        piece.unlink(missing_ok=True)
        why = (RUNTIME / "pw-record.log").read_text(errors="replace").strip().splitlines()
        raise CaptureError("Recording didn't start" + (f": {why[-1]}" if why else "."))
    state = {"state": "recording", "pid": proc.pid, "piece": str(piece), "since": since, "done": done}
    write_json(STATE, state)
    return state


def stop_piece(state):
    """SIGINT, as Ctrl+C would: pw-record writes its header's sizes and exits. Killed if it doesn't in STOP_WAIT."""
    pid, piece = state.get("pid"), state.get("piece")
    if alive(pid, piece):
        os.kill(pid, signal.SIGINT)
        end = time.time() + STOP_WAIT
        while alive(pid, piece) and time.time() < end:
            try:   # our own child (save then record in one `new`) would stay a zombie without this
                os.waitpid(pid, os.WNOHANG)
            except ChildProcessError:
                pass
            time.sleep(0.05)
        if alive(pid, piece):
            os.kill(pid, signal.SIGKILL)   # its header is then wrong; wav.read takes the length from the file
    state.update(state="paused", pid=None, done=state.get("done", 0) + wav.duration(piece or ""))
    write_json(STATE, state)
    return state


# --- the commands -----------------------------------------------------------------------------------------------------

def status(state=None):
    state = state if state is not None else current()
    if not state:
        return {"state": "idle", "name": None, "mic": None, "elapsed": 0, "started": None}
    meta = read_json(SESSION / "meta.json") or {}
    elapsed = state.get("done", 0) + (time.time() - state["since"] if state["state"] == "recording" else 0)
    return {"state": state["state"], "name": meta.get("name"), "mic": meta.get("mic") or "",
            "elapsed": round(elapsed, 1), "started": meta.get("started")}


def record(mic=None, name=None):
    state = current()
    if state and state["state"] == "recording":
        return state
    if state:   # paused: go on, from another mic if one is given
        meta = read_json(SESSION / "meta.json")
        if mic is not None and mic != meta.get("mic"):
            meta["mic"] = mic
            write_json(SESSION / "meta.json", meta)
        mic = meta.get("mic", "")
        give_back(meta, keep=mic)   # a headset left for another mic plays music well again
        return start_piece(target_of(mic, meta), state.get("done", 0))
    mic = settings.get()["mic"] if mic is None else mic
    now = datetime.now().astimezone()
    shutil.rmtree(SESSION, ignore_errors=True)
    SESSION.mkdir(parents=True)
    meta = {"name": recordings.clean_name(name or now.strftime(NAME_FORMAT)), "mic": mic,
            "started": now.isoformat(timespec="seconds")}
    write_json(SESSION / "meta.json", meta)
    try:
        return start_piece(target_of(mic, meta), 0)
    except CaptureError:
        give_back(meta)
        shutil.rmtree(SESSION, ignore_errors=True)
        raise


def pause():
    state = current()
    if not state:
        raise CaptureError("Nothing is being recorded.")
    return stop_piece(state) if state["state"] == "recording" else state


def toggle():
    state = current()
    return pause() if state and state["state"] == "recording" else record()


def write_recording(name):
    folder = settings.recordings_dir()
    folder.mkdir(parents=True, exist_ok=True)
    path = folder / (recordings.unique(folder, name) + ".wav")
    wav.join(pieces(), path)
    return recordings.brief(path)


def save(name=None):
    state = current()
    if not state:
        raise CaptureError("Nothing is being recorded.")
    if state["state"] == "recording":
        stop_piece(state)
    meta = read_json(SESSION / "meta.json") or {}
    give_back(meta)
    try:
        saved = write_recording(recordings.clean_name(name or meta.get("name") or "Recording"))
    except wav.WavError:
        saved = None   # nothing was heard: there is no recording to keep, and the session goes all the same
    shutil.rmtree(SESSION, ignore_errors=True)
    STATE.unlink(missing_ok=True)
    return saved


# --- the command line -------------------------------------------------------------------------------------------------

def option(args, flag):
    if flag not in args:
        return None
    i = args.index(flag)
    if i + 1 >= len(args):
        raise CaptureError(f"{flag} takes a value.")
    value = args[i + 1]
    del args[i:i + 2]
    return value


def clock(seconds):
    s = int(seconds)
    return f"{s // 3600}:{s // 60 % 60:02}:{s % 60:02}" if s >= 3600 else f"{s // 60}:{s % 60:02}"


def main(argv):
    as_json = "--json" in argv
    args = [a for a in argv if a != "--json"]
    out = {}
    try:
        mic, name = option(args, "--mic"), option(args, "--name")
        cmd = args[0] if len(args) == 1 else ""
        with locked():
            recovered = recover()
            if recovered:
                out["recovered"] = recovered
            if cmd == "status":
                pass
            elif cmd == "record":
                record(mic, name)
            elif cmd == "pause":
                pause()
            elif cmd == "toggle":
                toggle()
            elif cmd == "save":
                out["saved"] = save(name)
            elif cmd == "new":
                if current():
                    out["saved"] = save()
                record(mic, name)
            else:
                print(__doc__.split("\n\n")[1], file=sys.stderr)
                return 2
            out = dict(status(), **out)
    except (CaptureError, recordings.RecordingError) as e:
        print(e, file=sys.stderr)
        return 1
    except OSError as e:
        print(f"{e.filename or 'Recording'}: {e.strerror}.", file=sys.stderr)
        return 1
    if as_json:
        print(json.dumps(out))
        return 0
    if out.get("recovered"):
        print(f"Recovered a recording that was cut off: {out['recovered']['path']}")
    if "saved" in out:
        print(f"Saved {out['saved']['path']}" if out["saved"] else "Nothing was heard, so nothing was saved.")
    if out["state"] != "idle":
        print(f"{out['state'].capitalize()}: {out['name']}, {clock(out['elapsed'])}")
    elif cmd == "status":
        print("Not recording.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
