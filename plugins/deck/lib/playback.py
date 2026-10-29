#!/usr/bin/env python3
"""Deck's playback for Claude's tools (mcp.json): what each change does, and the state its undo goes back to.

Deck's own commands do the work (`deck ctl …`, `deck status --json`); this adds what an undo needs:
- snapshot: before a change, the state it changes as one JSON object (the playing album, track and position in a
  file `deck ctl save` writes, the queue's length, the like), which the undo's {name}s come from.
- restore SNAPSHOT PLAYING: back to that state (`deck ctl restore`, which loads it paused, then play if it played);
  with no snapshot, nothing played before, so it pauses.
- unqueue LENGTH URI…: the tracks a queue-album or queue-song put at the end of a queue LENGTH long come off it, and
  nothing else: not one the user queued since, nor one already played (#1860).
- control ACTION / undo-control ACTION SNAPSHOT PLAYING: play, pause, next, previous, and back.
- like true|false: the like as asked (Deck's own `like` toggles it).
- play-album, play-song, queue-album, queue-song, pick: Deck's, started first if no Deck runs, waiting a moment for
  the new track so the answer (and the notification) can name it.

Errors go to stderr in words for a reader, with exit status 1: Claude reads them.
"""

import json
import re
import subprocess
import sys
import time
from pathlib import Path

SNAPSHOTS = Path.home() / ".local/state/nightdrive/deck-undo"
SNAPSHOT_AGE = 6 * 3600   # seconds; the undo log offers Undo for an hour, so older copies are only clutter
WAIT = 4.0                # seconds to wait for Deck to start what it was told, before answering without it
HERE = Path(__file__).resolve().parent
# What Claude's uris must be before they go to Deck (#1862): one that starts with - would be an option of its CLI
URI = re.compile(r"spotify:(album|track):[A-Za-z0-9]+")
URIS = {"play-album": ("album",), "queue-album": ("album",), "play-song": ("track", "album"),
        "queue-song": ("track", "album")}   # pick takes a source, which the tool's enum keeps


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


def unqueue(length, *queued):
    """The run of queued tracks where it is now: from LENGTH, or nearer the front as the queue has played on (what
    has played of it is gone already, so its tail at the front counts too). Nothing is removed unless it is found."""
    queued, length = list(queued), int(length)
    if not queued:
        raise Failed("This undo doesn't say which tracks were queued, so nothing was taken off the queue.")
    uris = [t.get("uri") for t in status().get("queue") or []]
    for at in sorted(range(len(uris)), key=lambda i: (i > length, abs(i - length))):
        if uris[at:at + len(queued)] == queued:
            start, count = at, len(queued)
            break
    else:
        tail = next((n for n in range(len(queued) - 1, 0, -1) if uris[:n] == queued[-n:]), 0)
        if not tail:
            raise Failed("The tracks Claude queued aren't in the queue any more (played, or changed since), so "
                         "nothing was taken off.")
        start, count = 0, tail
    for _ in range(count):
        ctl("unqueue", str(start))   # each one removes the track at that position, so the next moves up into it
    return {"unqueued": count}


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
    for uri, want in zip(uris, URIS.get(kind, ())):
        m = URI.fullmatch(uri)
        if not m or m.group(1) != want:
            raise Failed(f"{uri!r} isn't a Spotify {want}'s uri (spotify:{want}:…).")
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
    queue = st.get("queue") or []
    # What the undo takes off: these tracks, found by their uris, not whatever stands after the old length then
    return {"queue_length": len(queue), "queued": [t.get("uri") for t in queue[queued:]]}


COMMANDS = {
    "snapshot": (0, snapshot),
    "restore": (2, restore),
    "unqueue": (-1, unqueue),   # LENGTH, then the URIs (an undo logged before them has none: it refuses)
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
    want = COMMANDS.get(argv[0], (None,))[0] if argv else None
    if want is None or (len(argv) - 1 < -want if want < 0 else len(argv) - 1 != want):
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
