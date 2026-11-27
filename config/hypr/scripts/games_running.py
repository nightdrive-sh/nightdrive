"""Which games are running now, and their windows (#3632): starting a game that is already open switches to it instead
of a cold start, and Games marks it on its cover.

A window is a game's when
- its class is the game's own: a .desktop file's StartupWMClass or file id (a Flatpak names its windows by its id), or
  steam_app_<appid>, the class Steam's games get under Proton and often natively. The class is compared whole, never
  split on spaces ("Cold Start '74" holds two).
- or its process, or a parent of it, was started for the game: `gio launch` (the Launcher, Games) puts the .desktop
  file's path in GIO_LAUNCHED_DESKTOP_FILE, and Steam puts the appid in SteamAppId / SteamGameId. That finds a native
  game whose class says nothing (a Godot or Unity game's own name), whatever starts it in between (a play script).

Paths and the window list come in as arguments so the tests can give their own."""

import json
import os
import subprocess

import games_library

PROC = "/proc"
# How far up the process tree to look for the launch's environment: game, its wrapper, Steam's reaper, …
MAX_PARENTS = 6
STEAM_VARS = (b"SteamAppId", b"SteamGameId")


def hypr_clients():
    """Hyprland's windows, or [] without Hyprland (a test, a tty)."""
    try:
        out = subprocess.run(["hyprctl", "-j", "clients"], capture_output=True, text=True, timeout=5).stdout
        return [c for c in json.loads(out or "[]") if c.get("mapped", True)]
    except (OSError, ValueError, subprocess.SubprocessError):
        return []


def environ(pid, proc=PROC):
    """A process's environment as {name: value} in bytes; {} when it can't be read (gone, another user's)."""
    try:
        with open(os.path.join(proc, str(pid), "environ"), "rb") as f:
            pairs = (e.split(b"=", 1) for e in f.read().split(b"\0") if b"=" in e)
            return dict(pairs)
    except OSError:
        return {}


def parent(pid, proc=PROC):
    """The parent's pid, or 0. The command name in stat may hold spaces and brackets, so read after its last ')'."""
    try:
        with open(os.path.join(proc, str(pid), "stat"), "rb") as f:
            return int(f.read().rsplit(b")", 1)[1].split()[1])
    except (OSError, IndexError, ValueError):
        return 0


def lineage(pid, proc=PROC):
    """The process and its parents' environments, nearest first, up to MAX_PARENTS (never init's)."""
    out = []
    while pid > 1 and len(out) < MAX_PARENTS:
        out.append(environ(pid, proc))
        pid = parent(pid, proc)
    return out


def classes(game):
    """The window classes that are the game's own, lower case."""
    if game["source"] == "steam":
        return {"steam_app_" + game["id"].split(":", 1)[1]}
    names = {game["id"].split(":", 1)[1]}
    entry = games_library.read_desktop(game["path"]) if game.get("path") else None
    if entry and entry.get("StartupWMClass"):
        names.add(entry["StartupWMClass"])
    return {n.lower() for n in names}


def launched_for(game, envs):
    """Whether one of the environments was a launch of this game."""
    if game["source"] == "steam":
        appid = game["id"].split(":", 1)[1].encode()
        return any(e.get(v) == appid for e in envs for v in STEAM_VARS)
    path = os.fsencode(game.get("path", ""))
    return bool(path) and any(e.get(b"GIO_LAUNCHED_DESKTOP_FILE") == path for e in envs)


def window_of(game, clients, proc=PROC, cache=None):
    """The game's window, the most recently used of them, or None. cache keeps each window's lineage between games."""
    cache = {} if cache is None else cache
    own = classes(game)
    order = sorted(clients, key=lambda c: c.get("focusHistoryID", 99))
    for c in order:
        if {c.get("class", "").lower(), c.get("initialClass", "").lower()} & own:
            return c
    for c in order:
        pid = c.get("pid", 0)
        if pid > 1:
            if pid not in cache:
                cache[pid] = lineage(pid, proc)
            if launched_for(game, cache[pid]):
                return c
    return None


def mark_running(games, clients=None, proc=PROC):
    """Sets each game's running (true while it has a window). Reads the windows once for all of them."""
    clients = hypr_clients() if clients is None else clients
    cache = {}
    for g in games:
        g["running"] = bool(clients) and window_of(g, clients, proc, cache) is not None
    return games
