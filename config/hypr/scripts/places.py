"""Places (Dashboard #3275): a name the user gives to one or more Wi-Fi networks (work = "Feature"), for reminders and
scheduled commands that wait for arriving at or leaving one. This file holds the places and the Wi-Fi now; the
`places` command beside it is its CLI, and the detection of arriving and leaving builds on it (#3277).

- The file is ~/.config/nightdrive/places.json, {"places": [{"name": "work", "wifi": ["Feature"]}]}: the user's own,
  never in the repo, mode 600. It is read as it is and written back keeping what this code doesn't know (a later
  "wired" key, another top-level key), so a newer Nightdrive's fields survive an older one's write.
- A place is known by its SSID, not by NetworkManager's connection uuid: an SSID stays the same over a reinstall and
  on every computer. A spoofed SSID would only fire a reminder in the wrong place, and nothing secret goes with it.
- Names are free text compared without case ("Work" is work), and two places can't share one. One SSID may be in two
  places (eduroam at the office and at the campus, a chain café's network): each place is its own question, "am I
  there?", and both are true there. `add` says which others have it, so a slip is seen.

Imported by `places` and the scripts beside it (sys.path gets this folder, as remind does with timers.py).
"""
import contextlib, fcntl, json, os, re, subprocess

KEY = "places"
MAX_NAME = 40             # a word or two: it is said in a sentence ("when I arrive at work") and shown in lists
MAX_SSID = 32             # 802.11's limit, in bytes
WIFI_ENV = "NIGHTDRIVE_PLACES_WIFI"   # the Wi-Fi now, one SSID a line, in place of nmcli's (the tests, the sandbox)


class PlaceError(Exception):
    """A request that can't be done, said for the user (the command prints it, Claude reads it)."""


def path():
    # Read at each call, not at import: the tests point HOME elsewhere
    return os.path.expanduser("~/.config/nightdrive/places.json")


def _clean(rows):
    """The file's rows that are places: a name and a list of SSIDs. Others are dropped, as a hand-edit's slip would
    otherwise stop every command."""
    out = []
    for r in rows if isinstance(rows, list) else []:
        if isinstance(r, dict) and isinstance(r.get("name"), str) and r["name"].strip():
            wifi = r.get("wifi")
            r = dict(r, wifi=[s for s in wifi if isinstance(s, str) and s] if isinstance(wifi, list) else [])
            out.append(r)
    return out


def _read_file():
    try:
        with open(path()) as f:
            data = json.load(f)
    except (OSError, ValueError):
        return {}
    return data if isinstance(data, dict) else {}


def load():
    """The places as a list of {name, wifi, …}; empty when there is no file or it is broken."""
    return _clean(_read_file().get(KEY))


@contextlib.contextmanager
def editing():
    """The places as a list to change in place, under a lock (a command and Claude's tool may land together); written
    back atomically, mode 600, only if it changed. The file's other keys are kept as they were."""
    p = path()
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p + ".lock", "w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        data = _read_file()
        rows = _clean(data.get(KEY))
        before = json.dumps(rows)
        yield rows
        if json.dumps(rows) != before:
            data[KEY] = rows
            tmp = p + ".tmp"
            fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
            with os.fdopen(fd, "w") as f:
                json.dump(data, f, ensure_ascii=False, indent=1)
                f.write("\n")
            os.replace(tmp, p)


def same(a, b):
    return a.strip().casefold() == b.strip().casefold()


def find(rows, name):
    """The place called name (any case), or None."""
    return next((r for r in rows if same(r["name"], name)), None)


def check_name(name):
    """name, trimmed, if it can be a place's: else PlaceError. Not starting with - so it never reads as an option."""
    name = (name or "").strip()
    if not name:
        raise PlaceError("A place needs a name, such as work or home.")
    if len(name) > MAX_NAME:
        raise PlaceError(f"A place's name is at most {MAX_NAME} characters.")
    if name.startswith("-") or re.search(r"[\x00-\x1f\x7f]", name):
        raise PlaceError(f"{name!r} can't be a place's name: no control characters, and not starting with -.")
    return name


def check_ssid(ssid):
    if not ssid or len(ssid.encode()) > MAX_SSID or re.search(r"[\x00-\x1f\x7f]", ssid):
        raise PlaceError(f"{ssid!r} isn't a Wi-Fi network's name (SSID: 1–{MAX_SSID} bytes, no control characters).")
    return ssid


def _nmcli_fields(line):
    """nmcli -t's line split on its unescaped colons, with \\: and \\\\ undone (an SSID may hold a colon)."""
    fields, cur, i = [], "", 0
    while i < len(line):
        c = line[i]
        if c == "\\" and i + 1 < len(line):
            cur += line[i + 1]
            i += 2
            continue
        if c == ":":
            fields.append(cur)
            cur = ""
        else:
            cur += c
        i += 1
    return fields + [cur]


def current_wifi():
    """The SSIDs this computer is connected to now (usually one; none without Wi-Fi). From nmcli's cached scan, no
    rescan: the active network is always in it. WIFI_ENV, when set, is used instead."""
    if WIFI_ENV in os.environ:
        return [s for s in os.environ[WIFI_ENV].splitlines() if s]
    try:
        p = subprocess.run(["nmcli", "-t", "-f", "ACTIVE,SSID", "device", "wifi", "list", "--rescan", "no"],
                           capture_output=True, text=True, timeout=10)
    except (OSError, subprocess.TimeoutExpired):
        return []
    found = []
    for line in p.stdout.splitlines():
        f = _nmcli_fields(line)
        if len(f) >= 2 and f[0] == "yes" and f[1] and f[1] not in found:
            found.append(f[1])
    return found


def here(rows, wifi):
    """The places whose networks include one of wifi (the SSIDs now): every one, as one SSID may be in two."""
    return [r for r in rows if set(r["wifi"]) & set(wifi)]


def view(r, wifi):
    return {"name": r["name"], "wifi": list(r["wifi"]), "here": bool(set(r["wifi"]) & set(wifi))}


def add(rows, name, ssids):
    """Adds the SSIDs to the place called name, creating it if there is none. → (place, added, created, shared):
    added the SSIDs it didn't have, shared {ssid: [other places that have it]}."""
    name = check_name(name)
    ssids = [check_ssid(s) for s in ssids]
    if not ssids:
        raise PlaceError("No Wi-Fi network to add: this computer isn't on Wi-Fi now. Name the network (SSID).")
    place = find(rows, name)
    created = place is None
    if created:
        place = {"name": name, "wifi": []}
        rows.append(place)
    added = [s for s in dict.fromkeys(ssids) if s not in place["wifi"]]
    place["wifi"] += added
    shared = {s: [r["name"] for r in rows if r is not place and s in r["wifi"]] for s in added}
    return place, added, created, {s: v for s, v in shared.items() if v}


def remove(rows, name):
    """Takes the place called name away. → the place as it was."""
    place = find(rows, name)
    if place is None:
        raise PlaceError(unknown(rows, name))
    rows.remove(place)
    return place


def forget(rows, name, ssid):
    """Takes one network off a place; the place stays, even with none left (it can be given one again). → the place."""
    place = find(rows, name)
    if place is None:
        raise PlaceError(unknown(rows, name))
    if ssid not in place["wifi"]:
        raise PlaceError(f"{place['name']} has no network {ssid!r}: it has {', '.join(place['wifi']) or 'none'}.")
    place["wifi"].remove(ssid)
    return place


def put(rows, name, previous):
    """Sets the place called name back to previous (a place's dict as `snapshot` gave it), or takes it away when
    previous is None: the undo of Claude's add and remove, which restores exactly what was there."""
    place = find(rows, name)
    if previous is None:
        if place is not None:
            rows.remove(place)
        return None
    if not isinstance(previous, dict):
        raise PlaceError("put takes a place as JSON, or null.")
    new = _clean([dict(previous, name=check_name(previous.get("name", name)))])
    if not new:
        raise PlaceError("put takes a place as JSON, or null.")
    if place is None:
        rows.append(new[0])
    else:
        rows[rows.index(place)] = new[0]
    return new[0]


def snapshot(rows, name):
    """{name, previous}: the place's name as stored (or as given, when there is none) and the place as a JSON string,
    "null" for none. What Claude's add and remove keep first, for their undo."""
    place = find(rows, name)
    return {"name": place["name"] if place else name.strip(),
            "previous": json.dumps(place, ensure_ascii=False) if place else "null"}


def unknown(rows, name):
    names = ", ".join(r["name"] for r in rows)
    return (f"No place called {name!r}. " + (f"The places: {names}. " if names else "There are no places yet. ")
            + "Add one with: nightdrive places add NAME [SSID…]")
