"""Network Drives' list of drives: ~/.config/nightdrive/netdrive.json, machine-specific, never in the repo.

    {"drives": [{"name": "Files", "ssh": "storage-files", "path": "~/Storage/Files"},
                {"name": "Photos", "ssh": "storage-photos", "path": "~/Storage/Photos", "read_only": true},
                {"name": "Jotta", "remote": "jotta:Sync", "path": "~/Storage/Jotta"}]}

A drive is either an ssh host (`ssh`: a Host of ~/.ssh/config, its key and agent as ssh has them, so no password is
ever written anywhere; `root`: an optional folder there) or any remote of `rclone config` (`remote`: "name:path"; what
it needs to log in is rclone's). The name is the unit's instance (netdrive@Files.service), so it stays a plain word.
"""
import json
import os
import re
from pathlib import Path

NAME = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_-]{0,31}$")
# The folder the drives go in when add gets no --path: one plain local folder in home, each drive a folder in it
DEFAULT_PARENT = "~/Storage"


class Refused(Exception):
    """A message for the user: printed as it is, exit 1"""


def config_file():
    base = os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config")
    return Path(base) / "nightdrive" / "netdrive.json"


def load():
    """[drive dicts], [] without the file. A broken file is refused rather than read as empty: add would overwrite it."""
    f = config_file()
    try:
        data = json.loads(f.read_text())
    except FileNotFoundError:
        return []
    except (OSError, ValueError) as e:
        raise Refused(f"{f} can't be read: {e}")
    drives = data.get("drives") if isinstance(data, dict) else None
    if not isinstance(drives, list):
        raise Refused(f"{f} has no \"drives\" list.")
    return [d for d in drives if isinstance(d, dict) and NAME.match(str(d.get("name", "")))]


def save(drives):
    f = config_file()
    f.parent.mkdir(parents=True, exist_ok=True)
    tmp = f.with_suffix(".json.tmp")
    tmp.write_text(json.dumps({"drives": drives}, indent=2) + "\n")
    os.replace(tmp, f)


def init():
    """An empty list, if there is none yet (the installer: plugin.conf's installed tests for the file)"""
    if not config_file().exists():
        save([])
    return {"file": str(config_file())}


def get(name):
    for d in load():
        if d["name"] == name:
            return d
    raise Refused(f"No drive named {name}: netdrive list shows them.")


def mountpoint(d):
    """The drive's folder, absolute"""
    return os.path.abspath(os.path.expanduser(d.get("path") or f"{DEFAULT_PARENT}/{d['name']}"))


def add(name, ssh="", remote="", path="", root="", read_only=False):
    if not NAME.match(name):
        raise Refused(f"{name!r}: a drive's name is letters, digits, - and _ (it names its service).")
    if bool(ssh) == bool(remote):
        raise Refused("Give either --ssh HOST (a Host of ~/.ssh/config) or --remote NAME:PATH (from rclone config).")
    if remote and ":" not in remote:
        raise Refused(f"{remote!r}: an rclone remote is NAME:PATH, e.g. jotta:Sync (rclone listremotes lists them).")
    if ssh and not re.match(r"^[A-Za-z0-9._@-]+$", ssh):
        raise Refused(f"{ssh!r}: give the Host's name from ~/.ssh/config.")
    drives = load()
    if any(d["name"] == name for d in drives):
        raise Refused(f"There is a drive named {name} already: netdrive remove {name} first.")
    d = {"name": name}
    if ssh:
        d["ssh"] = ssh
        if root:
            d["root"] = root
    else:
        d["remote"] = remote
    path = path or f"{DEFAULT_PARENT}/{name}"
    d["path"] = path
    home = os.path.expanduser("~")
    where = mountpoint(d)
    if not where.startswith(home + os.sep):
        raise Refused(f"{path}: the folder goes under your home folder.")
    for o in drives:
        mine, theirs = where + os.sep, mountpoint(o) + os.sep
        if mine.startswith(theirs) or theirs.startswith(mine):
            raise Refused(f"{path} is inside {o['name']}'s folder or holds it: one drive can't be inside another.")
    if read_only:
        d["read_only"] = True
    drives.append(d)
    save(drives)
    return d


def remove(name):
    drives = load()
    left = [d for d in drives if d["name"] != name]
    if len(left) == len(drives):
        raise Refused(f"No drive named {name}: netdrive list shows them.")
    save(left)
    return {"removed": name}
