#!/usr/bin/env python3
"""The recordings in ~/Recordings (settings.recordings_dir()): NAME.wav, its transcript NAME.txt and its exports
(NAME.mp3, .m4a, .flac, .opus) beside it, one recording to the window, a terminal and Claude's tools.

    recordings.py list [--json] [--limit N]    newest first (N: 0, the default, for all)
    recordings.py info [--json] NAME           one recording
    recordings.py rename [--json] NAME NEW     a new name for the recording and every file of it
    recordings.py trash [--json] NAME          the recording and every file of it to the desktop's trash (Files puts
                                               them back; `recorder restore` is its undo)

NAME is the recording's name (its file's without .wav) or its path. --json gives a recording as {name, path, duration
(seconds), size (bytes, the WAV's), modified (ISO time), transcript (the .txt's path, or null), exports ([paths])}.
Without --json they print text for a terminal. An error goes to stderr in plain words, with exit status 1.
"""

import json
import os
import subprocess
import sys
from datetime import datetime
from pathlib import Path

import settings
import wav

EXPORTS = (".mp3", ".m4a", ".flac", ".opus")
NIGHTDRIVE = Path(__file__).resolve().parents[3] / "bin/nightdrive"   # this checkout's, for its files trash
NAME_MAX = 120   # characters: a name stays a file name with " (2).recovered.flac" room after it


class RecordingError(Exception):
    pass


def clean_name(name):
    """A name typed by someone, made a file name: no slashes or control characters, no leading dot (hidden), no .wav."""
    name = "".join(" " if c in "/\\" or ord(c) < 32 else c for c in str(name)).strip()
    if name.lower().endswith(".wav"):
        name = name[:-4].rstrip()
    name = name.lstrip(".").strip()[:NAME_MAX].strip()
    if not name:
        raise RecordingError("A recording needs a name.")
    return name


def taken(folder, name):
    return any((folder / (name + ext)).exists() for ext in (".wav", ".txt") + EXPORTS)


def unique(folder, name):
    """name, or "name (2)", "name (3)" … the first that no file of a recording has: a new one never overwrites."""
    n, candidate = 1, name
    while taken(folder, candidate):
        n += 1
        candidate = f"{name} ({n})"
    return candidate


def files_of(path):
    """The WAV and every file beside it that belongs to it, the transcript and exports."""
    return [path] + [p for p in (path.with_suffix(ext) for ext in (".txt",) + EXPORTS) if p.exists()]


def brief(path):
    st = path.stat()
    txt = path.with_suffix(".txt")
    return {
        "name": path.stem,
        "path": str(path),
        "duration": round(wav.duration(path), 2),
        "size": st.st_size,
        "modified": datetime.fromtimestamp(st.st_mtime).astimezone().isoformat(timespec="seconds"),
        "transcript": str(txt) if txt.exists() else None,
        "exports": [str(p) for p in files_of(path)[1:] if p.suffix != ".txt"],
    }


def all_paths():
    folder = settings.recordings_dir()
    if not folder.is_dir():
        return []
    paths = [p for p in folder.glob("*.wav") if p.is_file() and not p.name.startswith(".")]
    return sorted(paths, key=lambda p: p.stat().st_mtime, reverse=True)


def find(who):
    """A recording by its name or path; only one in the recordings' folder (a path elsewhere isn't Recorder's)."""
    folder = settings.recordings_dir().resolve()
    who = str(who).strip()
    if not who:
        raise RecordingError("Which recording? Give its name.")
    p = Path(os.path.expanduser(who))
    if p.is_absolute():
        p = p.resolve()
        if p.parent != folder:
            raise RecordingError(f"{p} isn't in your recordings' folder, {folder}.")
        if p.suffix.lower() != ".wav":
            p = p.with_suffix(".wav")
    else:
        p = folder / (clean_name(who) + ".wav")
    if not p.is_file():
        raise RecordingError(f"No recording {p.stem} in {folder}.")
    return p


def rename(who, new):
    path = find(who)
    new = clean_name(new)
    if new == path.stem:
        return brief(path)
    if taken(path.parent, new):
        raise RecordingError(f"There is a recording {new} already.")
    for p in files_of(path):
        p.rename(p.with_name(new + p.suffix))
    return dict(brief(path.with_name(new + ".wav")), was=path.stem)


def trash(who):
    path = find(who)
    rec = brief(path)
    # Without the MCP server's variables: files would hold the paths to the folders Access gives Claude's file tools,
    # which ~/Recordings needn't be among (as Notes' trash, #1863). find has kept the path in the recordings' folder
    env = {k: v for k, v in os.environ.items() if not k.startswith("NIGHTDRIVE_MCP")}
    done = subprocess.run([str(NIGHTDRIVE), "files", "trash", "--json", "--"] + [str(p) for p in files_of(path)],
                          capture_output=True, text=True, env=env)
    if done.returncode != 0:
        raise RecordingError(done.stderr.strip() or "The recording couldn't be moved to the trash.")
    return dict(json.loads(done.stdout), name=rec["name"])


def clock(seconds):
    s = int(round(seconds))
    return f"{s // 3600}:{s // 60 % 60:02}:{s % 60:02}" if s >= 3600 else f"{s // 60}:{s % 60:02}"


def line(rec):
    marks = " ".join(filter(None, ["transcribed" if rec["transcript"] else "",
                                   " ".join(Path(e).suffix[1:] for e in rec["exports"])]))
    return f"{rec['modified'][:16].replace('T', ' ')}  {clock(rec['duration']):>7}  {rec['name']}" + \
           (f"  ({marks})" if marks else "")


def main(argv):
    as_json = "--json" in argv
    args = [a for a in argv if a != "--json"]
    limit = 0
    if "--limit" in args:
        i = args.index("--limit")
        try:
            limit = max(0, int(args[i + 1]))
        except (IndexError, ValueError):
            print("--limit takes a number.", file=sys.stderr)
            return 2
        del args[i:i + 2]
    if args[1:2] == ["--"]:
        del args[1]
    cmd, rest = (args[0], args[1:]) if args else ("", [])
    try:
        if cmd == "list" and not rest:
            paths = all_paths()
            recs = [brief(p) for p in (paths[:limit] if limit else paths)]
            out = {"folder": str(settings.recordings_dir()), "total": len(paths), "recordings": recs}
            text = "\n".join(line(r) for r in recs) or f"No recordings in {out['folder']} yet."
        elif cmd == "info" and len(rest) == 1:
            out = brief(find(rest[0]))
            text = "\n".join(f"{k}: {v}" for k, v in out.items())
        elif cmd == "rename" and len(rest) == 2:
            out = rename(*rest)
            text = f"Renamed to {out['name']}."
        elif cmd == "trash" and len(rest) == 1:
            out = trash(rest[0])
            text = f"{out['name']} is in the trash."
        else:
            print(__doc__.split("\n\n")[1], file=sys.stderr)
            return 2
    except RecordingError as e:
        print(e, file=sys.stderr)
        return 1
    except OSError as e:
        print(f"{e.filename or 'The recording'}: {e.strerror}.", file=sys.stderr)
        return 1
    print(json.dumps(out) if as_json else text)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
