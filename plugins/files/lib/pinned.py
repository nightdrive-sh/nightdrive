"""Files' own places, the sidebar's first group: folders in the order the user put them, kept in
~/.config/nightdrive/files/places.json ({"places": [path, ...]}). Until it is written, home and home's own folders
(places.standard). The second group, the bookmarks, stays GTK's (places.bookmarks), so the apps' Open dialogs list
them too: a quick place for a project's folders. A folder is dragged within a group or from one to the other (move).
"""
import json, os
from pathlib import Path

import places


def places_file():
    return places.config_home() / "nightdrive" / "files" / "places.json"


def paths():
    try:
        d = json.loads(places_file().read_text())
        if isinstance(d.get("places"), list):
            return [str(p) for p in d["places"] if isinstance(p, str) and p]
    except (OSError, ValueError, AttributeError):
        pass
    return [r["path"] for r in places.standard()]


def _save(ps):
    f = places_file()
    f.parent.mkdir(parents=True, exist_ok=True)
    tmp = f.with_suffix(".tmp")
    tmp.write_text(json.dumps({"places": ps}, indent=2) + "\n")
    os.replace(tmp, f)


def rows():
    """[{name, path, glyph, missing}]: home is "Home", home's own folders keep their glyphs, any other a folder's"""
    home = str(Path.home())
    glyphs = {home: "house"}
    dirs = places.user_dirs()
    for key, glyph in places.XDG:
        if key in dirs:
            glyphs[str(dirs[key])] = glyph
    out = []
    drives = places.netdrives.mounted()   # a folder in one isn't looked at (places.missing)
    for p in paths():
        missing = places.missing(p, drives)
        out.append({"name": "Home" if p == home else Path(p).name or p, "path": p,
                    "glyph": "folder-x" if missing else glyphs.get(p, "folder"), "missing": missing})
    return out


def remove(path):
    """Takes path out of the first group; {removed: path}"""
    path = str(Path(path))
    _save([p for p in paths() if p != path])
    return {"removed": path}


def move(path, to, before=""):
    """Puts path in group to ("places" or "bookmarks") before before (a folder of that group), or at its end, and out of
    the other group; {placed: path, to, before}. A bookmark keeps the name GTK's line gave it."""
    path = str(Path(path))
    before = str(Path(before)) if before else ""
    own = [p for p in paths() if p != path]
    if to == "places":
        places.bookmark(path, False)
        own.insert(own.index(before) if before in own else len(own), path)
    elif to == "bookmarks":
        places.bookmark_at(path, before)
    else:
        raise places.trash.Refused(f"No group {to}.")
    _save(own)
    return {"placed": path, "to": to, "before": before}
