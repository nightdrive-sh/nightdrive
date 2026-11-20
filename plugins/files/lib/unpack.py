"""Unpacking an archive into a folder: zip, tar and its compressed kinds (.tar.gz .tgz, .tar.bz2 .tbz2, .tar.xz .txz).
Plain Python (zipfile, tarfile), as fsops.py is; cli.py's `extract` runs it, and Files' ⏎ on an archive.

- An archive may come from anywhere, so nothing in it reaches outside the folder it unpacks into: a member whose path
  is absolute, has a "..", or a drive letter is left out (named in the result's "skipped"). A symlink is made only when
  its target stays inside too, and links are made last, after every file and folder, under folders that are real ones:
  no file is ever written through a link. Hard links, devices and fifos are left out; set-uid bits are dropped.
- Nothing is overwritten: it all unpacks first into a hidden folder of its own beside where it goes, then is renamed
  into place under a free name (fsops.free_name: " (2)"). Stopped (SIGTERM) or failed, the hidden folder goes.
- One thing at the archive's top (a folder or a file) lands as itself; several land in a folder named after the archive,
  so they don't scatter among the folder's own files.
- An archive that would need more room than the disk has free is refused before anything is written.
"""
import os, posixpath, re, shutil, stat, tarfile, tempfile, time, zipfile
from pathlib import Path

import fsops
from fsops import CHUNK, Progress, Refused, Stopped

SUFFIXES = (".tar.gz", ".tar.bz2", ".tar.xz", ".tgz", ".tbz2", ".tbz", ".txz", ".tar", ".zip")
DRIVE = re.compile(r"^[A-Za-z]:")


def kind(path):
    """"zip", "tar" or None, by the name's ending."""
    low = str(path).lower()
    if low.endswith(".zip"):
        return "zip"
    return "tar" if low.endswith(SUFFIXES) else None


def stem(name):
    """The archive's name without its ending: "photos.tar.gz" → "photos"."""
    low = name.lower()
    for s in SUFFIXES:
        if low.endswith(s) and len(name) > len(s):
            return name[:-len(s)]
    return name


def safe_parts(name, backslash=False):
    """A member's path as its parts under the folder, [] for the folder itself ("./"), None when it would leave it."""
    if backslash:                        # zips made on Windows may use \ between folders
        name = name.replace("\\", "/")
    if name.startswith("/") or DRIVE.match(name) or "\0" in name:
        return None
    parts = [p for p in name.split("/") if p not in ("", ".")]
    return None if ".." in parts else parts


def link_inside(parts, target):
    """Whether a link at parts pointing to target stays inside the folder (read as text: nothing on disk is asked)."""
    if not target or target.startswith("/") or DRIVE.match(target) or "\0" in target:
        return False
    joined = posixpath.normpath(posixpath.join(*parts[:-1], target) if len(parts) > 1 else target)
    return joined != ".." and not joined.startswith("../") and not joined.startswith("/")


class Member:
    """One entry of either kind of archive, as unpacking needs it."""

    def __init__(self, name, what, size=0, mode=0o644, mtime=None, target="", open_=None):
        self.name, self.what, self.size, self.mode = name, what, size, mode
        self.mtime, self.target, self.open = mtime, target, open_


def _zip_members(zf):
    for info in zf.infolist():
        unix = info.external_attr >> 16 if info.create_system == 3 else 0
        mtime = time.mktime(info.date_time + (0, 0, -1)) if info.date_time[0] >= 1980 else None
        mode = stat.S_IMODE(unix) or 0o644
        if stat.S_ISLNK(unix):
            target = zf.read(info).decode("utf-8", "replace")
            yield Member(info.filename, "link", target=target)
        elif info.is_dir():
            yield Member(info.filename, "dir")
        else:
            yield Member(info.filename, "file", info.file_size, mode, mtime, open_=lambda i=info: zf.open(i))


def _tar_members(tf):
    for m in tf:
        if m.issym():
            yield Member(m.name, "link", target=m.linkname)
        elif m.isdir():
            yield Member(m.name, "dir")
        elif m.isreg():
            yield Member(m.name, "file", m.size, m.mode, m.mtime, open_=lambda m=m: tf.extractfile(m))
        else:                            # hard links, devices, fifos: left out
            yield Member(m.name, "other")


def _real_dir(root, parts):
    """root/parts as a folder, made if it isn't there; None when something on the way is a link or a file."""
    d = root
    for p in parts:
        d = d / p
        if d.is_symlink():
            return None
        if not d.exists():
            os.mkdir(d)
        elif not d.is_dir():
            return None
    return d


def _write(m, dst, prog):
    with m.open() as fi, open(dst, "xb") as fo:
        while True:
            if fsops._stop:
                raise Stopped()
            buf = fi.read(CHUNK)
            if not buf:
                break
            fo.write(buf)
            prog.add(len(buf), dst.name)
    os.chmod(dst, (m.mode & 0o777) | 0o600)
    if m.mtime is not None:
        os.utime(dst, (m.mtime, m.mtime))


def _unpack_into(members, root, prog, backslash):
    """Every safe member under root; the names left out."""
    skipped, links = [], []
    for m in members:
        parts = safe_parts(m.name, backslash)
        if parts is None or m.what == "other":
            skipped.append(m.name)
            continue
        if not parts:
            continue                     # "./": the folder itself
        if m.what == "link":
            links.append((parts, m))     # last, so no file goes through one
            continue
        parent = _real_dir(root, parts[:-1] if m.what == "file" else parts)
        if parent is None:
            skipped.append(m.name)
        elif m.what == "file":
            try:
                _write(m, parent / parts[-1], prog)
            except FileExistsError:      # the same name twice in the archive: the first one stays
                skipped.append(m.name)
    for parts, m in links:
        parent = _real_dir(root, parts[:-1])
        if parent is None or not link_inside(parts, m.target) or os.path.lexists(parent / parts[-1]):
            skipped.append(m.name)
            continue
        os.symlink(m.target, parent / parts[-1])
    return skipped


def _open(path):
    """The archive's members and the archive to close after, or Refused in words."""
    try:
        if kind(path) == "zip":
            zf = zipfile.ZipFile(path)
            return zf, list(_zip_members(zf)), True
        tf = tarfile.open(path, "r:*")
        return tf, list(_tar_members(tf)), False
    except (zipfile.BadZipFile, tarfile.TarError, EOFError, OSError) as e:
        raise Refused(f"{Path(path).name} couldn't be read as an archive ({e}).")


def extract(path, into=None, report=None):
    """Unpacks path into the folder into (the archive's own when None); {made: [path], skipped: [names]}."""
    path = Path(path)
    into = Path(into) if into else path.parent
    if not kind(path):
        raise Refused(f"{path.name} isn't an archive Files can unpack.")
    if not path.is_file():
        raise Refused(f"{path.name} isn't there any more.")
    if not into.is_dir():
        raise Refused(f"{into} isn't a folder.")
    arc, members, is_zip = _open(path)
    with arc:
        need = sum(m.size for m in members)
        if need > shutil.disk_usage(into).free:
            raise Refused(f"{path.name} needs {need // 2**20} MB unpacked: there isn't room for it here.")
        tmp = Path(tempfile.mkdtemp(dir=into, prefix=f".{stem(path.name)}.unpacking-"))
        try:
            skipped = _unpack_into(members, tmp, Progress(need, report), is_zip)
            top = sorted(tmp.iterdir())
            if not top:
                raise Refused(f"There was nothing in {path.name} to unpack." if not skipped
                              else f"Nothing in {path.name} was safe to unpack.")
            if len(top) == 1:
                dst = into / fsops.free_name(into, top[0].name)
                os.rename(top[0], dst)
                tmp.rmdir()
            else:
                umask = os.umask(0); os.umask(umask)
                os.chmod(tmp, 0o777 & ~umask)                      # mkdtemp's is the owner's alone
                dst = into / fsops.free_name(into, stem(path.name), is_dir=True)
                os.rename(tmp, dst)
        except Stopped:
            shutil.rmtree(tmp, ignore_errors=True)
            return {"made": [], "stopped": True}
        except zipfile.BadZipFile as e:
            shutil.rmtree(tmp, ignore_errors=True)
            raise Refused(f"{path.name} is damaged ({e}).")
        except RuntimeError as e:        # zipfile: a password is needed
            shutil.rmtree(tmp, ignore_errors=True)
            raise Refused(f"{path.name} couldn't be unpacked ({e}).")
        except BaseException:
            shutil.rmtree(tmp, ignore_errors=True)
            raise
    return {"made": [str(dst)], "skipped": skipped}
