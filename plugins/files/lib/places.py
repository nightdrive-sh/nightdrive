"""What Files' sidebar lists but its own first group (pinned.py): the bookmarks, the disks, and the trash's count;
and home's own folders (xdg-user-dirs), which that group starts with.

The bookmarks are GTK's (~/.config/gtk-3.0/bookmarks: "file:///path Optional name" a line), the same Nautilus and every
app's Open dialog show, so one added here is there too and theirs are here. Only local folders are listed; a line for
anything else (sftp://, a network share) is kept in the file as it is.

The disks come from UDisks2 (udisks.py, not Gio's volume monitor: that touches network drives, #3707): a mounted one
with its folder, one that can be mounted without it. Network Drives' drives come after them, from netdrives.py, which
mounts and unmounts them too. A folder in a mounted network drive isn't looked at (missing stays false): finding it
would make the drive connect, and ask for its key, before the user goes there.
"""
import os, re
from pathlib import Path
from urllib.parse import quote, unquote, urlparse

import netdrives
import trash
import udisks

# Home's own folders in the sidebar's order, by xdg-user-dirs' names, and each one's glyph
XDG = [("DOCUMENTS", "file-text"), ("DOWNLOAD", "download"), ("PICTURES", "image"), ("MUSIC", "music"),
       ("VIDEOS", "clapperboard"), ("DESKTOP", "monitor")]


def config_home():
    return Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config")


def bookmarks_file():
    return config_home() / "gtk-3.0" / "bookmarks"


def user_dirs():
    """{NAME: path} from user-dirs.dirs; a folder set to home itself (the spec's way of turning one off) is left out."""
    home = Path.home()
    out = {}
    try:
        text = (config_home() / "user-dirs.dirs").read_text()
    except OSError:
        text = ""
    for m in re.finditer(r'^XDG_(\w+)_DIR="([^"]*)"', text, re.M):
        p = Path(m.group(2).replace("$HOME", str(home)))
        if p != home:
            out[m.group(1)] = p
    # Without the file, the English defaults that exist
    for name, folder in (("DOCUMENTS", "Documents"), ("DOWNLOAD", "Downloads"), ("PICTURES", "Pictures"),
                         ("MUSIC", "Music"), ("VIDEOS", "Videos")):
        out.setdefault(name, home / folder)
    return out


def standard():
    """[{name, path, glyph}]: Home, then home's folders that exist"""
    rows = [{"name": "Home", "path": str(Path.home()), "glyph": "house"}]
    dirs = user_dirs()
    for key, glyph in XDG:
        p = dirs.get(key)
        if p and p.is_dir():
            rows.append({"name": p.name, "path": str(p), "glyph": glyph})
    return rows


def _lines():
    try:
        return bookmarks_file().read_text().splitlines()
    except OSError:
        return []


def bookmarks():
    """[{name, path, missing}]: the local folders of GTK's bookmarks, in their order"""
    rows = []
    for line in _lines():
        uri, _, label = line.partition(" ")
        u = urlparse(uri)
        if u.scheme != "file":
            continue
        path = unquote(u.path)
        rows.append({"name": label.strip() or Path(path).name or path, "path": path, "missing": missing(path)})
    return rows


def _uri(path):
    return "file://" + quote(str(path), safe="/")


def _write(lines):
    f = bookmarks_file()
    f.parent.mkdir(parents=True, exist_ok=True)
    tmp = f.with_suffix(".tmp")
    tmp.write_text("".join(line + "\n" for line in lines))
    os.replace(tmp, f)


def _path_of(line):
    u = urlparse(line.partition(" ")[0])
    return unquote(u.path) if u.scheme == "file" else None


def bookmark_at(path, before=""):
    """Puts path among the bookmarks before before (one of them) or at the end; a line it had already moves there with
    its name. Lines for anything but a local folder stay where they are."""
    path = str(Path(path))
    lines = _lines()
    entry = next((line for line in lines if _path_of(line) == path), _uri(path))
    lines = [line for line in lines if _path_of(line) != path]
    at = next((i for i, line in enumerate(lines) if before and _path_of(line) == before), len(lines))
    lines.insert(at, entry)
    _write(lines)
    return {"bookmarked": True, "path": path}


def bookmark(path, on):
    """Adds path at the end of the bookmarks (on), or takes it away; {bookmarked: on, path}"""
    path = str(Path(path))
    lines = [line for line in _lines() if unquote(urlparse(line.partition(" ")[0]).path) != path
             or urlparse(line).scheme != "file"]
    if on:
        lines.append(_uri(path))
    _write(lines)
    return {"bookmarked": on, "path": path}


def devices():
    """[{name, path (its folder, "" unmounted), device, glyph, unmount}]: the disks the user can use, then the network
    drives"""
    return local_devices() + netdrives.rows()


def local_devices():
    return udisks.devices()


def missing(path, drives=None):
    """True when a folder of the sidebar isn't there; one in a mounted network drive is taken to be (above)"""
    drives = netdrives.mounted() if drives is None else drives
    if any(path == m or path.startswith(m.rstrip("/") + "/") for m in drives):
        return False
    return not Path(path).is_dir()


def mount(device):
    """Mounts a disk by its device (/dev/sdb1), or a network drive (netdrive:NAME); {path} where it went"""
    if device.startswith(netdrives.PREFIX):
        return netdrives.mount(device)
    return udisks.mount(device)


def unmount(path):
    """Unmounts (and, for a stick, powers off) the disk at path, or stops the network drive there; {unmounted: path}"""
    if path in netdrives.mounted():
        return netdrives.unmount(path)
    return udisks.unmount(path)


def all_places():
    """The sidebar's groups but the first (pinned.rows, which cli.py adds), Downloads' folder for gd, and home's own
    folders, which the window asks about before they go to the trash"""
    return {"bookmarks": bookmarks(), "devices": devices(), "trash": trash.count(),
            "downloads": str(user_dirs()["DOWNLOAD"]), "standard": [r["path"] for r in standard()]}
