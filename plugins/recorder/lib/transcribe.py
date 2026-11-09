#!/usr/bin/env python3
"""A recording made into text, NAME.txt beside its WAV: a paragraph for each minute or so, each with its time,
"[mm:ss] text". The work is a process of its own (run), so it goes on with the window closed; one runs at a time (the
CPU is the model's), the others wait in turn.

    transcribe.py start [--json] NAME     transcribe it in the background ("queued", then "running")
    transcribe.py run NAME                transcribe it here and now (start's process; a terminal's --wait)
    transcribe.py cancel [--json] NAME    stop it, or forget one that failed; the transcript before it stays
    transcribe.py status [--json]         the transcriptions under way, and those that failed

--json gives a job as {name, state: queued|running|failed, done, total (pieces), model, started (ISO), error}; status
as {jobs: [...]}. The recording is cut at its quiet moments (voxtype.cut_points), each piece made into text by the model
Settings picked (voxtype.py) and put through the user's own corrections (~/.config/voxtype/post-process), as dictation
is. The transcript is written whole at the end: one cancelled or failed leaves the one before it as it was. A
recording renamed or trashed meanwhile gets none (it is no longer where it was): transcribe it again.
"""

import fcntl
import json
import os
import shutil
import signal
import subprocess
import sys
import tempfile
import time
from datetime import datetime
from pathlib import Path

import recordings
import settings
import voxtype
import wav

RUNTIME = Path(os.environ.get("XDG_RUNTIME_DIR") or f"/tmp/recorder-{os.getuid()}") / "recorder"
JOBS = RUNTIME / "transcribe"
LOCK = RUNTIME / "transcribe.lock"   # held by the job that runs: the rest wait on it
LOG = Path(os.environ.get("XDG_STATE_HOME") or Path.home() / ".local/state") / "recorder/transcribe.log"
SPAWN_GRACE = 10   # seconds a job may be on file before its process has written its pid


class TranscribeError(Exception):
    pass


# --- the jobs: one file each in JOBS, which a logout clears ----------------------------------------------------------

def job_file(name):
    return JOBS / (name + ".json")


def read_job(name):
    try:
        return json.loads(job_file(name).read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None


def write_job(job):
    JOBS.mkdir(parents=True, exist_ok=True)
    tmp = JOBS / f".{job['name']}.{os.getpid()}.tmp"
    tmp.write_text(json.dumps(job), encoding="utf-8")
    tmp.replace(job_file(job["name"]))   # whole at once: the window reads it every second


def alive(pid):
    try:
        os.kill(pid, 0)
        return True
    except (OSError, TypeError):
        return False


def status():
    """The jobs on file, oldest first. One whose process is gone without a word (killed, a crash) counts as failed."""
    jobs = []
    for f in sorted(JOBS.glob("*.json")) if JOBS.is_dir() else []:
        job = read_job(f.stem)
        if not job:
            continue
        if job["state"] != "failed" and not alive(job.get("pid")):
            if job.get("pid") or time.time() - job.get("spawned", 0) > SPAWN_GRACE:
                job = dict(job, state="failed", error="The transcription stopped unexpectedly.")
                write_job(job)
        jobs.append({k: v for k, v in job.items() if k not in ("pid", "spawned")})
    return sorted(jobs, key=lambda j: j.get("started", ""))


def public(job):
    return {k: v for k, v in job.items() if k not in ("pid", "spawned")}


def start(who):
    path = recordings.find(who)
    name = path.stem
    job = read_job(name)
    if job and job["state"] != "failed" and (alive(job.get("pid")) or time.time() - job.get("spawned", 0) < SPAWN_GRACE):
        return public(job)   # under way already
    model = settings.get()["model"]
    need = voxtype.missing(model)
    if need:
        raise TranscribeError(need)
    job = {"name": name, "state": "queued", "done": 0, "total": 0, "model": model, "error": None,
           "started": datetime.now().astimezone().isoformat(timespec="seconds"), "spawned": time.time()}
    write_job(job)
    LOG.parent.mkdir(parents=True, exist_ok=True)
    with open(LOG, "a", encoding="utf-8") as log:
        # A session of its own: cancel stops it with ffmpeg and voxtype under it (killpg), and the window closing
        # doesn't
        subprocess.Popen([sys.executable, str(Path(__file__).resolve()), "run", name], start_new_session=True,
                         stdin=subprocess.DEVNULL, stdout=log, stderr=log, cwd="/")
    return public(job)


def cancel(who):
    name = recordings.clean_name(Path(str(who)).name)   # a name, or the WAV's path
    job = read_job(name)
    if not job:
        raise TranscribeError(f"{name} isn't being transcribed.")
    job_file(name).unlink(missing_ok=True)   # first: a queued one sees it gone and doesn't begin
    if job["state"] != "failed" and alive(job.get("pid")):
        try:
            os.killpg(job["pid"], signal.SIGTERM)
        except OSError:
            pass
    return dict(public(job), state="cancelled")


# --- the work --------------------------------------------------------------------------------------------------------

def stamp(seconds):
    s = int(seconds)
    return f"[{s // 60:02}:{s % 60:02}]"


def run(name, progress=None):
    """Transcribe the recording now; the job's file says how far it is. progress(done, total) for a terminal."""
    def stopped(*_):
        raise SystemExit(143)
    signal.signal(signal.SIGTERM, stopped)
    job = read_job(name) or {"name": name, "model": settings.get()["model"], "error": None, "done": 0, "total": 0,
                              "started": datetime.now().astimezone().isoformat(timespec="seconds")}
    job.update(state="queued", pid=os.getpid())
    write_job(job)
    RUNTIME.mkdir(parents=True, exist_ok=True)
    with open(LOCK, "w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)   # one at a time
        if not job_file(name).exists():
            return None                    # cancelled while it waited
        tmp = Path(tempfile.mkdtemp(prefix="transcribe-", dir=RUNTIME))
        try:
            job["state"] = "running"
            write_job(job)
            path = recordings.find(name)
            language = settings.get()["language"]
            points = voxtype.cut_points(wav.duration(path), voxtype.silences(path))
            pieces = voxtype.split(path, points, tmp)
            job["total"] = len(pieces)
            write_job(job)
            paragraphs = []
            for i, (at, piece) in enumerate(pieces):
                text = voxtype.post_process(voxtype.recognize(piece, job["model"], language))
                if text:
                    paragraphs.append(f"{stamp(at)} {text}")
                job["done"] = i + 1
                if job_file(name).exists():
                    write_job(job)
                if progress:
                    progress(i + 1, len(pieces))
            if not path.exists():
                raise TranscribeError(f"{name} was renamed or trashed meanwhile: transcribe it again.")
            out = path.with_suffix(".txt")
            part = out.with_name("." + out.name + ".part")   # hidden, and moved into place whole
            part.write_text("\n\n".join(paragraphs) + ("\n" if paragraphs else ""), encoding="utf-8")
            part.replace(out)
            job_file(name).unlink(missing_ok=True)
            # Which model made it: the log (start's stderr) and a terminal's --wait say so
            print(f"{datetime.now():%Y-%m-%d %H:%M} {name}: {job['model']}, {len(pieces)} pieces", file=sys.stderr)
            return out
        except (TranscribeError, voxtype.VoxtypeError, recordings.RecordingError, wav.WavError, OSError) as e:
            why = str(e) if not isinstance(e, OSError) else f"{e.filename or name}: {e.strerror}."
            if job_file(name).exists():
                write_job(dict(job, state="failed", error=why))
            raise TranscribeError(why) from None
        finally:
            shutil.rmtree(tmp, ignore_errors=True)


# --- the command line ------------------------------------------------------------------------------------------------

def main(argv):
    as_json = "--json" in argv
    args = [a for a in argv if a != "--json"]
    cmd, rest = (args[0], args[1:]) if args else ("", [])
    try:
        if cmd == "status" and not rest:
            out = {"jobs": status()}
            if not as_json:
                for j in out["jobs"]:
                    print(f"{j['name']}: {j['state']}" + (f" {j['done']}/{j['total']}" if j["total"] else "")
                          + (f": {j['error']}" if j["error"] else ""))
                if not out["jobs"]:
                    print("Nothing is being transcribed.")
        elif cmd in ("start", "cancel") and len(rest) == 1:
            out = (start if cmd == "start" else cancel)(rest[0])
            if not as_json:
                print({"queued": f"Transcribing {out['name']}: recorder transcriptions shows how far it is.",
                       "running": f"{out['name']} is being transcribed already.",
                       "cancelled": f"Stopped transcribing {out['name']}."}[out["state"]])
        elif cmd == "run" and len(rest) == 1:
            tty = sys.stderr.isatty()
            done = run(recordings.find(rest[0]).stem,
                       (lambda d, t: print(f"\r{d}/{t} pieces", end="", file=sys.stderr, flush=True)) if tty else None)
            if tty:
                print(file=sys.stderr)
            out = {"transcript": str(done) if done else None}
            if not as_json:
                print(f"Wrote {done}" if done else "Cancelled.")
        else:
            print(__doc__.split("\n\n")[1], file=sys.stderr)
            return 2
    except (TranscribeError, recordings.RecordingError) as e:
        print(e, file=sys.stderr)
        return 1
    except OSError as e:
        print(f"{e.filename or 'Transcribing'}: {e.strerror}.", file=sys.stderr)
        return 1
    if as_json:
        print(json.dumps(out))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
