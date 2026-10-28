#!/usr/bin/env python3
"""Deck's playback for Claude's tools (mcp.json): what each change does, and the state its undo goes back to.

Deck's own commands do the work (`deck ctl …`, `deck status --json`); this adds what an undo needs:
- snapshot: before a change, the state it changes as one JSON object (the playing album, track and position in a
  file `deck ctl save` writes, the queue's length, the like), which the undo's {name}s come from.
- restore SNAPSHOT PLAYING: back to that state (`deck ctl restore`, which loads it paused, then play if it played);
  with no snapshot, nothing played before, so it pauses.
- unqueue LENGTH: what was queued after the queue had LENGTH tracks comes off it.
- control ACTION / undo-control ACTION SNAPSHOT PLAYING: play, pause, next, previous, and back.
- like true|false: the like as asked (Deck's own `like` toggles it).
- play-album, play-song, queue-album, queue-song, pick: Deck's, started first if no Deck runs, waiting a moment for
  the new track so the answer (and the notification) can name it.

Errors go to stderr in words for a reader, with exit status 1: Claude reads them.
"""

import json
import subprocess
import sys
import time
from pathlib import Path

SNAPSHOTS = Path.home() / ".local/state/nightdrive/deck-undo"
SNAPSHOT_AGE = 6 * 3600   # seconds; the undo log offers Undo for an hour, so older copies are only clutter
WAIT = 4.0                # seconds to wait for Deck to start what it was told, before answering without it
HERE = Path(__file__).resolve().parent


class Failed(Exception):
    pass


def deck(*args, check=True):
    """`deck ARGS`; its stdout. A failure raises Failed with Deck's own message."""
    try:
        res = subprocess.run(["deck", *args], capture_output=True, text=True, timeout=20)
    except FileNotFoundError:
        raise Failed("Deck isn't installed (no deck command).")
    if check and res.returncode != 0:
        raise Failed((res.stderr.strip() or res.stdout.strip() or f"deck {args[0]} failed").removeprefix("deck: "))
    return res.stdout


def status():
    out = deck("status", "--json")
    try:
        return json.loads(out)
    except ValueError:
        raise Failed("This Deck can't tell what plays (deck status --json): update Deck.")


def start_player():
    """Deck's player without its window, when no Deck runs (as the launcher's Music level does)."""
    if status().get("running"):
        return
    window = HERE.parent / "bin/deck-window"
    if subprocess.run([str(window), "player"], capture_output=True).returncode != 0 or not status().get("running"):
        raise Failed("Deck didn't start: is it signed in? (open Deck once with Hyper+M)")


def ctl(*args):
    deck("ctl", *args)


def wait_for(test):
    """The status once test(status) holds, or the last one after WAIT seconds."""
    end = time.monotonic() + WAIT
    while True:
        st = status()
        if test(st) or time.monotonic() > end:
            return st
        time.sleep(0.2)


def playing(st):
    """What the answer says of the status: the track, and whether it plays."""
    keys = ("playing", "title", "artist", "album", "track_uri", "album_uri")
    return {k: st[k] for k in keys if k in st}


def snapshot():
    """The state a change replaces. snapshot is "" when nothing was loaded (the undo then pauses)."""
    SNAPSHOTS.mkdir(parents=True, exist_ok=True)
    now = time.time()
    for old in SNAPSHOTS.glob("*.json"):
        if now - old.stat().st_mtime > SNAPSHOT_AGE:
            old.unlink(missing_ok=True)
    st = status()
    state = {"snapshot": "", "playing": bool(st.get("playing")), "queue_length": len(st.get("queue") or []),
             "liked": st.get("liked")}
    if not st.get("track_uri"):
        return state
    # The running Deck writes it, with the position now: its own playback.json is saved only when the track
    # changes, and not after a restore from a copy.
    path = SNAPSHOTS / f"{int(now * 1000)}.json"
    ctl("save", str(path))
    end = time.monotonic() + WAIT
    while not path.is_file():
        if time.monotonic() > end:
            raise Failed("Deck didn't save what plays (deck ctl save: update Deck), so the change couldn't be undone.")
        time.sleep(0.1)
    state["snapshot"] = str(path)
    return state


def restore(path, was_playing):
    if not path:
        if status().get("running"):
            ctl("pause")
        return {"restored": False}
    if not Path(path).is_file():
        raise Failed("What played before is gone (its copy was cleared), so it can't be brought back.")
    try:
        track = (json.loads(Path(path).read_text()).get("now_playing") or {}).get("uri")
    except (OSError, ValueError):
        track = None
    start_player()
    ctl("restore", path)
    if was_playing != "true":
        return {"restored": True}
    # restore loads the track paused, and a play that comes while it still loads is lost: wait for the track, then
    # play until it plays
    wait_for(lambda st: st.get("track_uri") == track)
    for _ in range(3):
        ctl("play")
        if wait_for(lambda st: st.get("playing")).get("playing"):
            break
    return {"restored": True}


def unqueue(length):
    st = status()
    for _ in range(max(0, len(st.get("queue") or []) - int(length))):
        ctl("unqueue", str(length))   # each one removes the track at that position, so the next moves up into it
    return {}


def control(action):
    if not status().get("running"):
        raise Failed("Deck isn't running, so nothing plays.")
    before = status().get("track_uri")
    ctl(action)
    if action in ("next", "previous"):
        return playing(wait_for(lambda st: st.get("track_uri") != before))
    return playing(wait_for(lambda st: st.get("playing") == (action == "play")))


def undo_control(action, path, was_playing):
    if action in ("play", "pause"):
        ctl("pause" if action == "play" else "play")
        return {}
    return restore(path, was_playing)


def like(value):
    st = status()
    if not st.get("track_uri"):
        raise Failed("Nothing plays in Deck, so there's nothing to like.")
    if st.get("liked") is None:
        raise Failed("Likes aren't available in this Deck (it needs to be signed in to Spotify's Web API).")
    want = value == "true"
    if st["liked"] != want:
        ctl("like")
    return {"liked": want, "title": st.get("title"), "artist": st.get("artist")}


def play(kind, *uris):
    start_player()
    st = status()
    album, track, queued = st.get("album_uri"), st.get("track_uri"), len(st.get("queue") or [])
    ctl(kind, *uris)
    if kind == "play-album":
        # the album's uri changes first, the track's details a moment later
        return playing(wait_for(lambda st: st.get("album_uri") == uris[0] and st.get("track_uri") != track
                                and st.get("playing")))
    if kind == "play-song":
        return playing(wait_for(lambda st: st.get("track_uri") == uris[0] and st.get("playing")))
    if kind == "pick":
        return playing(wait_for(lambda st: st.get("album_uri") != album and st.get("track_uri") != track
                                and st.get("playing")))
    st = wait_for(lambda st: len(st.get("queue") or []) > queued)
    return {"queue_length": len(st.get("queue") or [])}


COMMANDS = {
    "snapshot": (0, snapshot),
    "restore": (2, restore),
    "unqueue": (1, unqueue),
    "control": (1, control),
    "undo-control": (3, undo_control),
    "like": (1, like),
    "play-album": (1, lambda uri: play("play-album", uri)),
    "play-song": (2, lambda track, album: play("play-song", track, album)),
    "queue-album": (1, lambda uri: play("queue-album", uri)),
    "queue-song": (2, lambda track, album: play("queue-song", track, album)),
    "pick": (1, lambda source: play("pick", *([source] if source != "any" else []))),
}


def main(argv):
    if not argv or argv[0] not in COMMANDS or len(argv) - 1 != COMMANDS[argv[0]][0]:
        print("usage: playback.py " + " | ".join(COMMANDS), file=sys.stderr)
        return 2
    try:
        print(json.dumps(COMMANDS[argv[0]][1](*argv[1:]), ensure_ascii=False))
    except Failed as e:
        print(e, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
