#!/usr/bin/env python3
"""Thumbnails for the grid (FileGrid.qml), in the freedesktop thumbnail cache that Nautilus, GTK's file chooser and the
others share: ~/.cache/thumbnails/{large,x-large}/<md5 of the file's URI>.png, each with the file's URI and mtime in
its PNG text (Thumb::URI, Thumb::MTime), so a file changed since is drawn again and one drawn by another app is used
as it is. A file that can't be drawn gets an empty mark under fail/nightdrive-files/ and isn't tried again until it
changes.

    thumbs.py SIZE PATH...      # SIZE: large (256 px) or x-large (512 px)

prints one JSON line per file it has a thumbnail for, {"path", "thumb"}, as each is ready: those in the cache first,
then the ones drawn, a few at a time. Files of other kinds print nothing. Pictures are drawn with GdkPixbuf, a PDF's
first page with pdftoppm and a video's frame with ffmpeg (the same kinds the preview draws, peek.py).
"""
import hashlib, json, os, stat, subprocess, shutil, sys, tempfile
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from urllib.parse import quote

from peek import IMAGES, VIDEOS

SIZES = {"large": 256, "x-large": 512}
WORKERS = 4                  # drawn side by side: a folder of photos comes in a few seconds, not one by one
TIMEOUT = 20                 # s for a PDF page or a video frame
FAIL_DIR = "nightdrive-files"
MAX_IMAGE_BYTES = 200_000_000  # a picture larger than this isn't decoded for a thumbnail


def cache_root():
    return Path(os.environ.get("XDG_CACHE_HOME") or Path.home() / ".cache") / "thumbnails"


def uri(path):
    """The file's URI as GLib writes it (the cache's key must match the other apps'), else close to it"""
    try:
        import gi
        from gi.repository import GLib
        return GLib.filename_to_uri(str(path), None)
    except Exception:
        return "file://" + quote(str(path), safe="/!$&'()*+,=:@")


def kind(path):
    s = Path(path).suffix.lower()
    return "image" if s in IMAGES else "pdf" if s == ".pdf" else "video" if s in VIDEOS else None


def names(path, size):
    u = uri(path)
    key = hashlib.md5(u.encode()).hexdigest() + ".png"
    root = cache_root()
    return u, root / size / key, root / "fail" / FAIL_DIR / key


def _pixbuf():
    import gi
    gi.require_version("GdkPixbuf", "2.0")
    from gi.repository import GdkPixbuf
    return GdkPixbuf


def valid(png, mtime):
    """A thumbnail in the cache is good while its Thumb::MTime is the file's"""
    try:
        GdkPixbuf = _pixbuf()
        pb = GdkPixbuf.Pixbuf.new_from_file(str(png))
        return pb.get_option("tEXt::Thumb::MTime") == str(mtime)
    except Exception:
        return False


def _scaled(src, px):
    """The picture at src at most px on its longer side (never larger than it is), turned as its EXIF says"""
    GdkPixbuf = _pixbuf()
    _, w, h = GdkPixbuf.Pixbuf.get_file_info(str(src))     # at_scale would enlarge a small one
    if w > 0 and h > 0:
        px = min(px, max(w, h))
    pb = GdkPixbuf.Pixbuf.new_from_file_at_scale(str(src), px, px, True)
    return pb.apply_embedded_orientation() or pb


def _save(pb, out, u, st):
    """Written beside its place first and moved in, so another app never reads half a file"""
    out.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    fd, tmp = tempfile.mkstemp(dir=out.parent, suffix=".part")
    os.close(fd)
    try:
        pb.savev(tmp, "png", ["tEXt::Thumb::URI", "tEXt::Thumb::MTime", "tEXt::Thumb::Size", "tEXt::Software"],
                 [u, str(int(st.st_mtime)), str(st.st_size), "Nightdrive Files"])
        os.chmod(tmp, 0o600)
        os.replace(tmp, out)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)


def _render(path, k, px, tmpdir):
    """A PDF's first page or a video's frame as a PNG in tmpdir; None when the tool is missing or fails"""
    out = Path(tmpdir) / "frame.png"
    if k == "pdf":
        cmd = ["pdftoppm", "-png", "-f", "1", "-l", "1", "-singlefile", "-scale-to", str(px), str(path), str(out)[:-4]]
    else:
        # A second in (the first frame is often black); a clip shorter than that, its first frame
        cmd = ["ffmpeg", "-v", "error", "-y", "-ss", "1", "-i", str(path), "-frames:v", "1",
               "-vf", f"scale='min({px},iw)':-2", str(out)]
    if not shutil.which(cmd[0]):
        return None
    for attempt in (cmd, cmd[:4] + cmd[6:]) if k == "video" else (cmd,):
        try:
            subprocess.run(attempt, capture_output=True, timeout=TIMEOUT, check=True)
            if out.exists() and out.stat().st_size:
                return out
        except (OSError, subprocess.SubprocessError):
            pass
    return None


def draw(path, size):
    """The thumbnail of path in the cache, made if need be; None for a file that isn't drawn"""
    k = kind(path)
    if not k:
        return None
    try:
        st = os.stat(path)
    except OSError:
        return None
    if not stat.S_ISREG(st.st_mode):
        return None
    u, out, fail = names(path, size)
    mtime = int(st.st_mtime)
    if out.exists() and valid(out, mtime):
        return out
    if fail.exists() and valid(fail, mtime):
        return None
    px = SIZES[size]
    try:
        if k == "image":
            if st.st_size > MAX_IMAGE_BYTES:
                raise ValueError("too large")
            pb = _scaled(path, px)
        else:
            with tempfile.TemporaryDirectory() as tmp:
                frame = _render(path, k, px, tmp)
                if not frame:
                    raise ValueError("not drawn")
                pb = _scaled(frame, px)
        _save(pb, out, u, st)
        return out
    except Exception:
        _mark_failed(fail, u, st)
        return None


def _mark_failed(fail, u, st):
    """An empty 1×1 PNG with the file's URI and mtime: the spec's way to say it was tried"""
    try:
        GdkPixbuf = _pixbuf()
        pb = GdkPixbuf.Pixbuf.new(GdkPixbuf.Colorspace.RGB, True, 8, 1, 1)
        pb.fill(0)
        _save(pb, fail, u, st)
    except Exception:
        pass


def emit(path, thumb):
    print(json.dumps({"path": str(path), "thumb": str(thumb)}), flush=True)


def main(argv):
    if len(argv) < 2 or argv[1] not in SIZES:
        print("usage: thumbs.py large|x-large PATH...", file=sys.stderr)
        return 2
    size, paths = argv[1], [p for p in argv[2:] if kind(p)]
    # Those already in the cache at once, in the order given (the grid's, so the top ones come first)
    todo = []
    for p in paths:
        try:
            mtime = int(os.stat(p).st_mtime)
        except OSError:
            continue
        _, out, _ = names(p, size)
        if out.exists() and valid(out, mtime):
            emit(p, out)
        else:
            todo.append(p)
    with ThreadPoolExecutor(WORKERS) as pool:
        for p, thumb in zip(todo, pool.map(lambda p: draw(p, size), todo)):
            if thumb:
                emit(p, thumb)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv))
    except (BrokenPipeError, KeyboardInterrupt):     # the grid moved on to another folder
        sys.exit(0)
