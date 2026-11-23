"""Looking into an archive without unpacking it (Files' → on a zip or tar, #3307): its listing, one member taken out to
a temporary place for the preview, and the members picked (y in the archive, p in a folder) unpacked under unpack.py's
rules. cli.py's archive-list, member-peek, member-clean and extract-members run these.

- A zip's listing is read at once (its central directory); a compressed tar has to be read from start to end, so a big
  one takes a while: the listing goes into a cache (~/.cache/nightdrive/files/archives), named by the archive's path,
  size and time, and the next look is at once. While it reads, report(done, total, name) says how far, in bytes of
  the archive.
- The listing is what unpacking it would make: a member whose path would leave the folder ("..", absolute, a drive
  letter), a hard link, a device or a fifo is left out (counted in "skipped"), and so is a second member of the same
  name (unpack.py keeps the first). Folders a tar leaves out but its paths imply are put in.
- A member previewed is written to $XDG_RUNTIME_DIR/nightdrive-files/<slot>/ (a window's own slot), read-only and
  without its execute bit. A slot's members not looked at for a while go as the next one is taken out, and the whole
  slot goes when the window leaves the archive or closes (member-clean); the runtime dir itself is gone at logout.
- Members picked are unpacked by unpack.py's own code, so its rules hold: nothing outside the folder, links only when
  they stay inside what was picked, nothing written over (" (2)"), stopped or failed leaves nothing.
"""
import hashlib, json, lzma, mimetypes, os, re, shutil, tarfile, tempfile, time, zipfile, zlib
from pathlib import Path

import fsops, peek, unpack
from fsops import Progress, Refused, Stopped

CACHE_KEEP = 30                  # listings kept in the cache, the newest
PREVIEW_MAX = 512 * 2**20        # a member larger than this isn't taken out for a preview
SLOT_STALE = 120                 # s: a member not looked at for this long goes when another is taken out
SLOT_ORPHAN = 24 * 3600          # s: a slot left by a window that never cleaned it (a crash)
TICK = 0.2                       # s between progress lines while a listing is read
SLOT = re.compile(r"^[a-z0-9]{1,32}$")
READ_ERRORS = (zipfile.BadZipFile, tarfile.TarError, EOFError, OSError, ValueError, lzma.LZMAError, zlib.error)


def cache_dir():
    return Path(os.environ.get("XDG_CACHE_HOME") or Path.home() / ".cache") / "nightdrive/files/archives"


def runtime_dir():
    base = os.environ.get("XDG_RUNTIME_DIR") or os.path.join(tempfile.gettempdir(), f"run-{os.getuid()}")
    d = Path(base) / "nightdrive-files"
    d.mkdir(mode=0o700, parents=True, exist_ok=True)
    return d


def _stat(path):
    path = Path(path)
    if not unpack.kind(path):
        raise Refused(f"{path.name} isn't an archive Files can look into.")
    try:
        st = path.stat()
    except OSError:
        raise Refused(f"{path.name} isn't there any more.")
    if not path.is_file():
        raise Refused(f"{path.name} isn't an archive Files can look into.")
    return path, st


def _key(path, st, extra=""):
    return hashlib.sha1(f"{os.path.realpath(path)}\0{st.st_size}\0{st.st_mtime_ns}\0{extra}".encode()).hexdigest()


class _Reader:
    """The archive opened for reading, its members (unpack.py's Member) one by one, closed after."""

    def __init__(self, path):
        self.path, self.raw, self.arc = path, None, None
        self.zip = unpack.kind(path) == "zip"

    def __enter__(self):
        try:
            if self.zip:
                self.arc = zipfile.ZipFile(self.path)
                self.members = unpack._zip_members(self.arc)
            else:                        # the raw file of our own, so its position tells how far the read has come
                self.raw = open(self.path, "rb")
                self.arc = tarfile.open(fileobj=self.raw, mode="r:*")
                self.members = unpack._tar_members(self.arc)
        except READ_ERRORS as e:
            self.__exit__()
            raise Refused(f"{Path(self.path).name} couldn't be read as an archive ({e}).")
        return self

    def pos(self):
        return self.raw.tell() if self.raw else 0

    def __exit__(self, *_):
        if self.arc:
            self.arc.close()
        if self.raw:
            self.raw.close()

    def safe(self):
        """(parts, member) of each member unpacking would make; (None, member) for those it leaves out."""
        for m in self.members:
            if fsops._stop:
                raise Stopped()
            parts = unpack.safe_parts(m.name, self.zip)
            yield (None if m.what == "other" else parts), m


def _read(path, size, report):
    entries, skipped, last = {}, 0, time.monotonic()
    with _Reader(path) as r:
        try:
            for parts, m in r.safe():
                if report and time.monotonic() - last >= TICK:
                    last = time.monotonic()
                    report(r.pos(), size, m.name)
                if parts is None:
                    skipped += 1
                    continue
                if not parts:
                    continue             # "./": the archive's top itself
                for i in range(1, len(parts)):          # folders only implied by a deeper path
                    entries.setdefault("/".join(parts[:i]), {"dir": True, "size": 0, "modified": None, "link": ""})
                name = "/".join(parts)
                e = {"dir": m.what == "dir", "size": m.size if m.what == "file" else 0,
                     "modified": m.mtime, "link": m.target if m.what == "link" else ""}
                old = entries.get(name)
                if old is None:
                    entries[name] = e
                elif old["dir"] and e["dir"] and old["modified"] is None:
                    old["modified"] = e["modified"]     # the folder's own entry, after a path that implied it
                else:
                    skipped += 1         # the same name twice: unpacking keeps the first
        except READ_ERRORS as e:
            raise Refused(f"{Path(path).name} is damaged ({e}).")
    return [dict(name=n, **e) for n, e in entries.items()], skipped


def _cache_write(key, out):
    d = cache_dir()
    d.mkdir(parents=True, exist_ok=True)
    tmp = d / f".{key}.{os.getpid()}"
    tmp.write_text(json.dumps(out, ensure_ascii=False))
    os.replace(tmp, d / f"{key}.json")
    old = sorted(d.glob("*.json"), key=lambda p: p.stat().st_mtime, reverse=True)[CACHE_KEEP:]
    for p in old:
        p.unlink(missing_ok=True)


def listing(path, report=None):
    """{archive, entries: [{name, dir, size, modified, link}], skipped, cached}: every member as a path under the
    archive's top ("docs/a.txt"), modified in epoch seconds or None."""
    path, st = _stat(path)
    key = _key(path, st)
    cached = cache_dir() / f"{key}.json"
    try:
        out = json.loads(cached.read_text())
        os.utime(cached)                 # the newest stay
        out.update(archive=str(path), cached=True)
        return out
    except (OSError, ValueError):
        pass
    entries, skipped = _read(path, st.st_size, report)
    for e in entries:                    # a folder without a time of its own (a zip's, an implied one): the archive's
        if e["modified"] is None:
            e["modified"] = st.st_mtime
    out = {"archive": str(path), "entries": entries, "skipped": skipped}
    try:
        _cache_write(key, out)
    except OSError:
        pass                             # a full disk: no cache, the listing still comes
    return dict(out, cached=False)


def _find(lst, name):
    for e in lst["entries"]:
        if e["name"] == name:
            return e
    raise Refused(f"{name} isn't in {Path(lst['archive']).name} any more.")


def _prune(slot_dir):
    """A slot's members not looked at for SLOT_STALE, and slots no window cleaned for SLOT_ORPHAN."""
    now = time.time()
    for d, age in [(d, SLOT_STALE) for d in _dirs(slot_dir)] + [(s, SLOT_ORPHAN) for s in _dirs(slot_dir.parent)]:
        try:
            if d != slot_dir and now - d.stat().st_mtime > age:
                shutil.rmtree(d, ignore_errors=True)
        except OSError:
            pass                         # another window's, gone meanwhile


def _dirs(d):
    try:
        return list(d.iterdir())
    except OSError:
        return []


def member_file(path, name, slot):
    """The member name of the archive as a file of its own in the window's slot, taken out once; None when it is too
    large to take out for a preview."""
    if not SLOT.match(slot or ""):
        raise Refused("No slot for the preview.")
    path, st = _stat(path)
    e = _find(listing(path), name)
    if e["dir"] or e["link"]:
        raise Refused(f"{name} isn't a file.")
    if e["size"] > PREVIEW_MAX:
        return None
    slot_dir = runtime_dir() / slot
    d = slot_dir / _key(path, st, name)[:20]
    out = d / name.rsplit("/", 1)[-1]
    if out.exists():
        os.utime(d)
        os.utime(slot_dir)
        return out
    _prune(slot_dir)
    d.mkdir(mode=0o700, parents=True, exist_ok=True)
    part = d / ".partial"
    part.unlink(missing_ok=True)
    with _Reader(path) as r:
        try:
            for parts, m in r.safe():
                if parts and "/".join(parts) == name and m.what == "file":
                    unpack._write(m, part, Progress(m.size, None))
                    os.chmod(part, 0o400)    # a look at it, not a copy to change or run
                    os.rename(part, out)
                    os.utime(slot_dir)
                    return out
        except RuntimeError as e:        # zipfile: a password is needed
            part.unlink(missing_ok=True)
            raise Refused(f"{name} couldn't be taken out ({e}).")
        except READ_ERRORS as e:
            part.unlink(missing_ok=True)
            raise Refused(f"{Path(path).name} is damaged ({e}).")
    raise Refused(f"{name} isn't in {path.name} any more.")


def peek_member(path, name, slot, long=False):
    """What the preview shows of a member, as peek.peek gives it for a file on disk; path is the member's place under
    the archive ("…/photos.zip/docs/a.txt"), and file the copy taken out for the window to draw or play."""
    path, st = _stat(path)
    lst = listing(path)
    e = _find(lst, name)
    base = name.rsplit("/", 1)[-1]
    out = {"path": f"{path}/{name}", "name": base, "link": e["link"], "size": e["size"], "dir": e["dir"],
           "modified": peek.iso(e["modified"] or st.st_mtime), "executable": False}
    if e["dir"]:
        kids = [x["name"].rsplit("/", 1)[-1] for x in lst["entries"] if x["name"].rsplit("/", 1)[0] == name and "/" in x["name"]]
        hidden = len([k for k in kids if k.startswith(".")])
        return dict(out, type="inode/directory", kind="Folder", items=len(kids) - hidden, hidden=hidden)
    if e["link"]:
        return dict(out, type="", kind="Link")
    f = member_file(path, name, slot)
    if f is None:
        t = mimetypes.guess_type(base)[0] or ""
        return dict(out, type=t, kind="Too large to preview inside the archive")
    seen = peek.peek(f, long)
    seen.update(out, file=str(f))
    return seen


def clean(slot):
    """The window's slot, and what was taken out into it, gone."""
    if not SLOT.match(slot or ""):
        raise Refused("No slot.")
    shutil.rmtree(runtime_dir() / slot, ignore_errors=True)
    return {"cleaned": slot}


def _picked(r, sel, dirs, dropped):
    """The members under the names picked, each from the picked one's own name down and under its place in sel
    ("docs/deep/b.bin", picked second as "docs/deep" → "1/deep/b.bin"): two picked of the same name never meet. Stops
    early once every picked file has come and no folder was picked. A link is judged where it will land, without the
    number in front (unpack.py would let "../x" from "1/c/up" reach the number's folder, which isn't there after):
    pointing out of the folder unpacked into, it goes in dropped."""
    left = set(sel)
    for parts, m in r.safe():
        if not parts:
            continue
        for i, s in enumerate(sel):
            if tuple(parts[:len(s)]) == s:
                rel = parts[len(s) - 1:]
                if m.what == "link" and not unpack.link_inside(rel, m.target):
                    dropped.append(m.name)
                    break
                name = "/".join([str(i)] + rel)
                yield unpack.Member(name, m.what, m.size, m.mode, m.mtime, m.target, m.open)
                left.discard(s)
                break
        if not left and not dirs:
            return


def extract(path, names, into, report=None):
    """Unpacks the members named (as listing gives them; a folder with all in it) into the folder into, each under its
    own name; {made: [path], skipped: [names]}."""
    path, st = _stat(path)
    into = Path(into)
    if not into.is_dir():
        raise Refused(f"{into} isn't a folder.")
    try:
        lst = listing(path)
    except Stopped:
        return {"made": [], "stopped": True}
    sel = []
    for n in names:
        parts = unpack.safe_parts(n)
        if not parts or "/".join(parts) != n:
            raise Refused(f"{n} isn't a member's name.")
        sel.append(tuple(parts))
    sel = [s for s in dict.fromkeys(sel) if not any(o != s and s[:len(o)] == o for o in sel)]   # one inside another
    picked = [_find(lst, "/".join(s)) for s in sel]
    dirs = any(e["dir"] for e in picked)
    need = sum(e["size"] for e in lst["entries"] if any(tuple(e["name"].split("/")[:len(s)]) == s for s in sel))
    if need > shutil.disk_usage(into).free:
        raise Refused(f"They need {need // 2**20} MB unpacked: there isn't room for them here.")
    tmp = Path(tempfile.mkdtemp(dir=into, prefix=f".{unpack.stem(path.name)}.unpacking-"))
    made = []
    try:
        with _Reader(path) as r:
            dropped = []
            skipped = unpack._unpack_into(_picked(r, sel, dirs, dropped), tmp, Progress(need, report), False)
            skipped = dropped + skipped
        for i, s in enumerate(sel):      # in the order picked, those that came
            top = tmp / str(i) / s[-1]
            if top.exists() or top.is_symlink():
                dst = into / fsops.free_name(into, top.name, is_dir=top.is_dir() and not top.is_symlink())
                os.rename(top, dst)
                made.append(str(dst))
        shutil.rmtree(tmp, ignore_errors=True)
        if not made:
            raise Refused("Nothing picked was safe to unpack." if skipped else "Nothing picked was in the archive.")
    except Stopped:
        shutil.rmtree(tmp, ignore_errors=True)
        return {"made": made, "stopped": True}
    except RuntimeError as e:            # zipfile: a password is needed
        shutil.rmtree(tmp, ignore_errors=True)
        raise Refused(f"{path.name} couldn't be unpacked ({e}).")
    except READ_ERRORS as e:
        shutil.rmtree(tmp, ignore_errors=True)
        raise Refused(f"{path.name} is damaged ({e}).")
    except BaseException:
        shutil.rmtree(tmp, ignore_errors=True)
        raise
    return {"made": made, "skipped": skipped}
