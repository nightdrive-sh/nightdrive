"""What Files' sidebar lists but its own first group (pinned.py): the bookmarks, the disks, and the trash's count;
and home's own folders (xdg-user-dirs), which that group starts with.

The bookmarks are GTK's (~/.config/gtk-3.0/bookmarks: "file:///path Optional name" a line), the same Nautilus and every
app's Open dialog show, so one added here is there too and theirs are here. Only local folders are listed; a line for
anything else (sftp://, a network share) is kept in the file as it is.

The disks come from Gio's volume monitor (udisks2 through gvfs): a mounted one with its folder, one that can be
mounted without it. Without Gio (python3-gobject) there are none, and the rest still works.
"""
import os, re, subprocess
from pathlib import Path
from urllib.parse import quote, unquote, urlparse

import trash

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
        rows.append({"name": label.strip() or Path(path).name or path, "path": path, "missing": not Path(path).is_dir()})
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
    """[{name, path (its folder, "" unmounted), device, glyph, unmount}]: the disks the user can use"""
    try:
        import gi
        gi.require_version("Gio", "2.0")
        from gi.repository import Gio
    except (ImportError, ValueError):
        return []
    mon = Gio.VolumeMonitor.get()
    rows, seen = [], set()
    for m in mon.get_mounts():
        if m.is_shadowed():
            continue
        root = m.get_root().get_path()
        if not root or root == "/":
            continue
        seen.add(root)
        vol = m.get_volume()
        rows.append({"name": m.get_name(), "path": root,
                     "device": vol.get_identifier("unix-device") or "" if vol else "",
                     "glyph": "usb" if m.can_eject() else "hard-drive", "unmount": bool(m.can_unmount())})
    for v in mon.get_volumes():
        if v.get_mount() is not None or not v.can_mount():
            continue
        dev = v.get_identifier("unix-device") or ""
        if not dev:
            continue
        rows.append({"name": v.get_name(), "path": "", "device": dev,
                     "glyph": "usb" if v.can_eject() else "hard-drive", "unmount": False})
    return rows


def mount(device):
    """Mounts a disk by its device (/dev/sdb1) with gio; {path} where it went"""
    r = subprocess.run(["gio", "mount", "-d", device], capture_output=True, text=True, timeout=60)
    if r.returncode != 0:
        raise trash.Refused(r.stderr.strip().split("\n")[-1] or f"{device} couldn't be mounted.")
    m = re.search(r"at (/\S.*?)\s*$", r.stdout.strip())
    path = m.group(1) if m else next((d["path"] for d in devices() if d["device"] == device), "")
    return {"path": path}


def unmount(path):
    """Unmounts (and, for a stick, ejects) the disk at path; {unmounted: path}"""
    r = subprocess.run(["gio", "mount", "-e", path], capture_output=True, text=True, timeout=60)
    if r.returncode != 0:
        r = subprocess.run(["gio", "mount", "-u", path], capture_output=True, text=True, timeout=60)
    if r.returncode != 0:
        raise trash.Refused(r.stderr.strip().split("\n")[-1] or f"{path} couldn't be unmounted: something uses it.")
    return {"unmounted": path}


def all_places():
    """The sidebar's groups but the first (pinned.rows, which cli.py adds), and Downloads' folder for gd"""
    return {"bookmarks": bookmarks(), "devices": devices(), "trash": trash.count(),
            "downloads": str(user_dirs()["DOWNLOAD"])}
