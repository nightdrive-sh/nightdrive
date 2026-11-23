"""Packing files and folders into an archive: zip, tar.gz, tar.xz or plain tar. Plain Python (zipfile, tarfile), as
fsops.py is; cli.py's `compress` runs it, and Files' c.

- Nothing is overwritten: a name taken in the folder gets " (2)" (fsops.free_name), and the archive is written as a
  hidden file beside it first, put in place under its name only once whole. Stopped (SIGTERM) or failed, it goes.
- Each path goes in under its own name, its folders whole; links are kept as links, not followed (an archive of a
  folder with a link to / stays small). Sockets, fifos and devices are left out.
- Two paths of the same name (a search's results from different folders) get " (2)" inside the archive too.
"""
import errno, os, stat, tarfile, tempfile, time, zipfile
from pathlib import Path

import fsops
from fsops import CHUNK, Progress, Refused, Stopped

FORMATS = {"zip": ".zip", "tar.gz": ".tar.gz", "tar.xz": ".tar.xz", "tar": ".tar"}
TAR_MODES = {"tar.gz": "w:gz", "tar.xz": "w:xz", "tar": "w"}


def with_ending(name, fmt):
    """name with fmt's ending, put on when it hasn't got it: "photos" → "photos.zip"."""
    end = FORMATS[fmt]
    return name if name.lower().endswith(end) else name + end


def _walk(path, arcname):
    """(path, name in the archive) for path and everything under it, links not followed, folders before what's in them."""
    yield path, arcname
    if path.is_dir() and not path.is_symlink():
        for child in sorted(path.iterdir()):
            yield from _walk(child, arcname + "/" + child.name)


def _entries(srcs):
    """Every (path, name in the archive), each source under a name of its own at the top."""
    taken = set()
    for p in srcs:
        is_dir = p.is_dir() and not p.is_symlink()
        top = next(fsops.numbered(p.name, n, is_dir) for n in range(1, 10000)
                   if fsops.numbered(p.name, n, is_dir) not in taken)
        taken.add(top)
        yield from _walk(p, top)


class _Reader:
    """A file read in chunks for tarfile, counting progress and stopping on SIGTERM between them."""

    def __init__(self, f, prog, name):
        self.f, self.prog, self.name = f, prog, name

    def read(self, n=-1):
        if fsops._stop:
            raise Stopped()
        buf = self.f.read(n if 0 < n <= CHUNK else CHUNK)
        self.prog.add(len(buf), self.name)
        return buf


def _zip(entries, out, prog):
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED, allowZip64=True, strict_timestamps=False) as zf:
        for path, arc in entries:
            st = path.lstat()
            if stat.S_ISLNK(st.st_mode):
                stamp = time.localtime(max(st.st_mtime, 315532800))[:6]   # zip's times start in 1980
                info = zipfile.ZipInfo(arc, stamp)
                info.create_system = 3
                info.external_attr = (stat.S_IFLNK | 0o777) << 16
                zf.writestr(info, os.readlink(path))
            elif stat.S_ISDIR(st.st_mode):
                zf.write(path, arc + "/")
            elif stat.S_ISREG(st.st_mode):
                info = zipfile.ZipInfo.from_file(path, arc, strict_timestamps=False)
                info.compress_type = zipfile.ZIP_DEFLATED
                with open(path, "rb") as fi, zf.open(info, "w") as fo:
                    while True:
                        if fsops._stop:
                            raise Stopped()
                        buf = fi.read(CHUNK)
                        if not buf:
                            break
                        fo.write(buf)
                        prog.add(len(buf), path.name)


def _tar(entries, out, prog, fmt):
    with tarfile.open(out, TAR_MODES[fmt]) as tf:
        for path, arc in entries:
            info = tf.gettarinfo(str(path), arc)
            if info is None:             # a socket: nothing tar can hold
                continue
            if info.isreg():
                with open(path, "rb") as fi:
                    tf.addfile(info, _Reader(fi, prog, path.name))
            elif info.isdir() or info.issym():
                tf.addfile(info)
            # devices and fifos are left out: unpacked anywhere they'd be of no use, or worse


def _place(tmp, into, name):
    """tmp under name in into, or the first free numbered name: a link can't write over a file that came meanwhile
    (a rename would). A disk without hard links (a USB stick's FAT) gets a rename of a name checked free."""
    for _ in range(100):
        dst = into / fsops.free_name(into, name, is_dir=False)
        try:
            os.link(tmp, dst)
            os.unlink(tmp)
            return dst
        except FileExistsError:
            continue
        except OSError as e:
            if e.errno not in (errno.EPERM, errno.EOPNOTSUPP, errno.ENOTSUP, errno.EMLINK, errno.EXDEV):
                raise
            os.rename(tmp, dst)
            return dst
    raise Refused(f"Too many named {name} in {into}.")


def compress(paths, into, name, fmt, report=None):
    """Packs paths into an archive named name (fmt's ending put on) in the folder into; {made: [path]}."""
    if fmt not in FORMATS:
        raise Refused(f"Files can't make a {fmt} archive.")
    name = with_ending(fsops.valid_name(name), fmt)
    srcs = fsops._sources(paths, into)
    into = Path(into)
    prog = Progress(sum(fsops.size_of(p) for p in srcs), report)
    fd, tmp = tempfile.mkstemp(dir=into, prefix=f".{name}.", suffix=".part")
    os.close(fd)
    umask = os.umask(0); os.umask(umask)
    os.chmod(tmp, 0o666 & ~umask)                           # mkstemp's is the owner's alone
    try:
        entries = _entries(srcs)
        if fmt == "zip":
            _zip(entries, tmp, prog)
        else:
            _tar(entries, tmp, prog, fmt)
        return {"made": [str(_place(tmp, into, name))]}
    except Stopped:
        return {"made": [], "stopped": True}
    finally:
        if os.path.lexists(tmp):
            os.unlink(tmp)
