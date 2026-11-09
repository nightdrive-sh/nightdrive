#!/usr/bin/env python3
"""Voxtype for the transcription (transcribe.py): which of its programs and models are installed, a recording cut into
pieces at its quietest moments, and one piece made into text.

    voxtype.py check [--json]     what each model needs, for the window's Settings and `recorder config`

The models (settings.py's model): "parakeet" is Parakeet int8 through voxtype-onnx: fast (about 1.4 s for 6 s of speech
on an M2 Max's CPU), and finds the language itself; the full Parakeet writes short Finnish words in Cyrillic, so it is
never used (docs/dictation.md). "whisper" is Whisper large-v3-turbo through voxtype: more exact, and about as slow as
the recording is long (51 s for 46 s of Finnish on an M2 Max; Parakeet 3 s); "medium", Whisper medium, sits between: nearly as exact (46 s of Finnish: 33 s).
Whisper's language is settings.py's language (auto, fi, en).

Voxtype is installed by hand (docs/dictation.md), into ~/.local/bin, so that is looked in before PATH: the window's
PATH may not have it. RECORDER_VOXTYPE_DIR points elsewhere, for a test's fake one.
"""

import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

DATA_HOME = Path(os.environ.get("XDG_DATA_HOME") or Path.home() / ".local/share")
MODELS = DATA_HOME / "voxtype/models"
BIN_DIR = Path(os.environ.get("RECORDER_VOXTYPE_DIR") or Path.home() / ".local/bin")
POST_PROCESS = Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config") / "voxtype/post-process"
FFMPEG = os.environ.get("RECORDER_FFMPEG", "ffmpeg")
DOCS = "Nightdrive's docs › Dictation"

ENGINES = {
    "parakeet": {"program": "voxtype-onnx", "engine": "parakeet", "model": "parakeet-tdt-0.6b-v3-int8",
                 "file": "parakeet-tdt-0.6b-v3-int8", "label": "Fast", "about": "Parakeet: finds the language itself"},
    "medium": {"program": "voxtype", "engine": "whisper", "model": "medium", "file": "ggml-medium.bin",
               "label": "Medium", "about": "Whisper medium: nearly as exact, a third faster"},
    "whisper": {"program": "voxtype", "engine": "whisper", "model": "large-v3-turbo",
                "file": "ggml-large-v3-turbo.bin", "label": "More exact", "about": "Whisper large-v3-turbo: about as long as the recording"},
}

# Where a piece is cut: at the quietest moment between CUT_MIN and CUT_MAX seconds from the last cut (the longest
# silence there), else at CUT_AT. A cut in the middle of a word loses it; one every minute or so keeps a long recording
# from going to the model whole, and gives each paragraph its time.
CUT_MIN, CUT_AT, CUT_MAX = 45.0, 60.0, 75.0
SILENCE = "silencedetect=noise=-35dB:d=0.25"
PIECE_TIMEOUT = 900   # seconds one piece may take (Whisper on a slow CPU) before it counts as hung
POST_TIMEOUT = 15

# What voxtype prints besides the text: its progress lines and the onnxruntime warnings
NOISE = re.compile(r"^(Loading audio file|Audio format|Processing \d+ samples)|\bWARN\b|cpuid_info|^\s*$")
ANSI = re.compile(r"\x1b\[[0-9;]*m")


class VoxtypeError(Exception):
    pass


def program(name):
    own = BIN_DIR / name
    if own.is_file() and os.access(own, os.X_OK):
        return str(own)
    return shutil.which(name)


def missing(model):
    """What the model still needs, in plain words with the command to run, or None when it is ready."""
    e = ENGINES[model]
    if not program(e["program"]):
        return f"Transcribing needs Voxtype's {e['program']} in ~/.local/bin: see {DOCS}."
    if not (MODELS / e["file"]).exists():
        return f"Transcribing needs the {e['model']} model: {e['program']} setup --download --model {e['model']}"
    return None


def check(model=None):
    """{model: {label, about, ready, missing}} for both, or the one asked for."""
    names = [model] if model else list(ENGINES)
    return {m: {"label": ENGINES[m]["label"], "about": ENGINES[m]["about"], "ready": not missing(m),
                "missing": missing(m)} for m in names}


def silences(path):
    """[(start, end)] of the recording's silences, as ffmpeg's silencedetect finds them."""
    done = subprocess.run([FFMPEG, "-nostdin", "-hide_banner", "-i", str(path), "-af", SILENCE, "-f", "null", "-"],
                          capture_output=True, text=True)
    if done.returncode != 0:
        raise VoxtypeError("The recording couldn't be read for transcribing.")
    starts = [float(x) for x in re.findall(r"silence_start: (-?[\d.]+)", done.stderr)]
    ends = [float(x) for x in re.findall(r"silence_end: ([\d.]+)", done.stderr)]
    return list(zip(starts, ends))   # a silence still on at the end has no end: it is no place to cut anyway


def cut_points(duration, quiet):
    """The seconds to cut at: each at the middle of the longest silence CUT_MIN…CUT_MAX after the one before."""
    points, at = [], 0.0
    while duration - at > CUT_MAX:
        best = None
        for start, end in quiet:
            middle = (start + end) / 2
            if at + CUT_MIN <= middle <= at + CUT_MAX and (best is None or end - start > best[1] - best[0]):
                best = (start, end)
        at = (best[0] + best[1]) / 2 if best else at + CUT_AT
        points.append(round(at, 3))
    return points


def split(path, points, folder):
    """The recording as 16 kHz mono pieces (what Voxtype takes) in folder: [(start seconds, piece path)]."""
    cmd = [FFMPEG, "-nostdin", "-hide_banner", "-loglevel", "error", "-i", str(path), "-ar", "16000", "-ac", "1",
           "-c:a", "pcm_s16le", "-f", "segment", "-reset_timestamps", "1"]
    if points:
        cmd += ["-segment_times", ",".join(str(p) for p in points)]
    else:
        cmd += ["-segment_time", "100000"]   # one piece
    done = subprocess.run(cmd + [str(Path(folder) / "%05d.wav")], capture_output=True, text=True)
    if done.returncode != 0:
        why = done.stderr.strip().splitlines()
        raise VoxtypeError("The recording couldn't be cut into pieces" + (f": {why[-1]}" if why else "."))
    pieces = sorted(Path(folder).glob("*.wav"))
    return list(zip([0.0] + points, pieces))


def recognize(piece, model, language="auto"):
    """One piece's text, as the model hears it ("" for silence)."""
    e = ENGINES[model]
    cmd = [program(e["program"]) or e["program"], "-q", "--engine", e["engine"], "--model", e["model"]]
    if e["engine"] == "whisper":
        cmd += ["--language", language]
    try:
        done = subprocess.run(cmd + ["transcribe", str(piece)], capture_output=True, text=True,
                              timeout=PIECE_TIMEOUT)
    except FileNotFoundError:
        raise VoxtypeError(missing(model) or f"{e['program']} couldn't be started.") from None
    except subprocess.TimeoutExpired:
        raise VoxtypeError(f"{e['program']} took over {PIECE_TIMEOUT // 60} minutes for one piece.") from None
    if done.returncode != 0:
        why = [ANSI.sub("", ln) for ln in done.stderr.strip().splitlines() if "error" in ln.lower()]
        raise VoxtypeError(f"{e['program']} failed" + (f": {why[-1].strip()}" if why else "."))
    lines = [ANSI.sub("", ln).strip() for ln in done.stdout.splitlines()]
    return " ".join(ln for ln in lines if not NOISE.search(ln))


def post_process(text):
    """The user's own corrections (docs/dictation.md › Your own corrections), as dictation gets them; without the
    script, or when it fails, the text as it was."""
    if not text or not (POST_PROCESS.is_file() and os.access(POST_PROCESS, os.X_OK)):
        return text
    try:
        done = subprocess.run([str(POST_PROCESS)], input=text, capture_output=True, text=True, timeout=POST_TIMEOUT)
    except (OSError, subprocess.TimeoutExpired):
        return text
    return done.stdout.strip() if done.returncode == 0 and done.stdout.strip() else text


def main(argv):
    as_json = "--json" in argv
    args = [a for a in argv if a != "--json"]
    if args != ["check"]:
        print(__doc__.split("\n\n")[1], file=sys.stderr)
        return 2
    out = check()
    if as_json:
        print(json.dumps(out))
    else:
        for m, v in out.items():
            print(f"{m}: {'ready' if v['ready'] else v['missing']}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
