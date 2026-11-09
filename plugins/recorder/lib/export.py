#!/usr/bin/env python3
"""A recording exported beside its WAV in another format, for sending or keeping smaller (the window's Export, e).

    export.py [--json] NAME FORMAT      FORMAT: mp3, m4a, flac or opus
    export.py formats [--json]          those four, for the window's Export panel: [{format, label, about}]

The export is NAME.FORMAT in the recordings' folder, beside NAME.wav, so rename and trash take it along
(recordings.files_of). One there already is made again: the WAV is the recording, an export only a copy of it.
--json prints the recording after it (recordings.brief) with {format, export: its path,
export_size: its bytes}.
ffmpeg (ffmpeg-free is enough: these encoders are all in it) does the work.
"""

import json
import os
import subprocess
import sys

import recordings

FFMPEG = os.environ.get("RECORDER_FFMPEG", "ffmpeg")
# Speech in 48 kHz mono: 128 kbps MP3 and AAC as Jari chose (5.11.), Opus at 64 kbps sounds as good for a voice
FORMATS = {
    "mp3": {"label": "MP3", "about": "128 kbps, plays anywhere", "args": ["-c:a", "libmp3lame", "-b:a", "128k"]},
    "m4a": {"label": "M4A", "about": "AAC 128 kbps, Apple's devices", "args": ["-c:a", "aac", "-b:a", "128k"]},
    "flac": {"label": "FLAC", "about": "Lossless, about half the WAV", "args": ["-c:a", "flac"]},
    "opus": {"label": "Opus", "about": "64 kbps, the smallest", "args": ["-c:a", "libopus", "-b:a", "64k"]},
}


class ExportError(Exception):
    pass


def export(who, fmt):
    fmt = str(fmt).lower().lstrip(".")
    if fmt not in FORMATS:
        raise ExportError(f"Export as {', '.join(FORMATS)}, not {fmt}.")
    path = recordings.find(who)
    out = path.with_suffix("." + fmt)
    # Written under a hidden name and moved into place whole: the list (all_paths, files_of) never sees half a file,
    # and a failed export leaves the one before it as it was
    tmp = out.with_name("." + out.name + ".part")
    cmd = [FFMPEG, "-nostdin", "-hide_banner", "-loglevel", "error", "-y", "-i", str(path), "-vn"] + \
          FORMATS[fmt]["args"] + ["-f", {"m4a": "ipod"}.get(fmt, fmt), str(tmp)]
    try:
        done = subprocess.run(cmd, capture_output=True, text=True)
    except FileNotFoundError:
        raise ExportError("Exporting needs ffmpeg: sudo dnf install ffmpeg-free") from None
    if done.returncode != 0:
        tmp.unlink(missing_ok=True)
        why = done.stderr.strip().splitlines()
        raise ExportError(f"{FORMATS[fmt]['label']} export failed" + (f": {why[-1]}" if why else "."))
    tmp.replace(out)
    return dict(recordings.brief(path), format=fmt, export=str(out), export_size=out.stat().st_size)


def main(argv):
    as_json = "--json" in argv
    args = [a for a in argv if a != "--json"]
    if args[:1] == ["--"]:
        args = args[1:]
    if args == ["formats"]:
        out = [{"format": k, "label": v["label"], "about": v["about"]} for k, v in FORMATS.items()]
        print(json.dumps(out) if as_json else "\n".join(f"{o['format']:5} {o['about']}" for o in out))
        return 0
    if len(args) != 2:
        print(__doc__.split("\n\n")[1], file=sys.stderr)
        return 2
    try:
        out = export(*args)
    except (ExportError, recordings.RecordingError) as e:
        print(e, file=sys.stderr)
        return 1
    except OSError as e:
        print(f"{e.filename or 'The export'}: {e.strerror}.", file=sys.stderr)
        return 1
    print(json.dumps(out) if as_json else f"Exported {out['export']}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
