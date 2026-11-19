"""What the preview pane shows of the picked file: its type in words, size, times, a folder's count, a link's target,
the start of a text, a picture's size, and a PDF's first page or a video's frame drawn as a picture. Reads at most TEXT_BYTES of a file, so a large one costs no more than a
small one (long: more, for the big preview). The picture itself the window draws (Qt's Image); this only gives its size.
"""
import datetime, hashlib, mimetypes, os, shutil, stat, subprocess
from pathlib import Path

TEXT_BYTES = 8192            # the start of a text that the pane shows
TEXT_LINES = 120
LONG_BYTES = 262144          # and the big preview (Space), which scrolls
LONG_LINES = 5000
# Text that mimetypes doesn't call text/: shown as such
TEXTY = ("application/json", "application/xml", "application/javascript", "application/x-sh", "application/toml",
         "application/x-yaml", "application/yaml", "application/sql", "application/x-desktop")
RENDER_WIDTH = 1200          # px of a PDF's first page or a video's frame, drawn once into the cache
VIDEOS = (".mp4", ".mkv", ".webm", ".mov", ".avi", ".mpeg", ".ogv", ".m4v")
IMAGES = (".png", ".jpg", ".jpeg", ".gif", ".webp", ".bmp", ".svg", ".avif", ".heic", ".tif", ".tiff", ".ico")


def content_type(path):
    """Gio's content type when it is there (what the default app goes by), else mimetypes' guess"""
    try:
        import gi
        gi.require_version("Gio", "2.0")
        from gi.repository import Gio
        t = Gio.File.new_for_path(str(path)).query_info("standard::content-type", 0, None).get_content_type() or ""
        desc = Gio.content_type_get_description(t) if t else ""
        return t, desc[:1].upper() + desc[1:]
    except Exception:
        t = mimetypes.guess_type(str(path))[0] or ("inode/directory" if Path(path).is_dir() else "")
        return t, ""


def iso(ts):
    return datetime.datetime.fromtimestamp(ts).isoformat(timespec="minutes")


def _text(path, long=False):
    try:
        with open(path, "rb") as f:
            raw = f.read(LONG_BYTES if long else TEXT_BYTES)
    except OSError:
        return None
    if b"\0" in raw:
        return None
    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError as e:
        if e.start < len(raw) - 4:           # not a character cut in two at the end: not UTF-8 text
            return None
        text = raw[:e.start].decode("utf-8")
    return "\n".join(text.splitlines()[:LONG_LINES if long else TEXT_LINES])


def _image_size(path):
    try:
        import gi
        gi.require_version("GdkPixbuf", "2.0")
        from gi.repository import GdkPixbuf
        _, w, h = GdkPixbuf.Pixbuf.get_file_info(str(path))
        return [w, h] if w > 0 else None
    except Exception:
        return None


def cache_dir():
    return Path(os.environ.get("XDG_CACHE_HOME") or Path.home() / ".cache") / "nightdrive/files/peek"


def rendered(p, st, kind):
    """A PDF's first page (pdftoppm) or a video's frame a second in (ffmpeg) as a PNG in the cache, named by the path,
    size and time, so a changed file is drawn again; None without the tool or when it fails."""
    tool = "pdftoppm" if kind == "pdf" else "ffmpeg"
    if not shutil.which(tool):
        return None
    key = hashlib.sha1(f"{p}\0{st.st_size}\0{st.st_mtime_ns}".encode()).hexdigest()
    out = cache_dir() / f"{key}.png"
    if out.exists():
        return str(out)
    out.parent.mkdir(parents=True, exist_ok=True)
    tmp = out.with_suffix(".part.png")
    if kind == "pdf":
        cmd = ["pdftoppm", "-png", "-f", "1", "-l", "1", "-singlefile", "-scale-to-x", str(RENDER_WIDTH),
               "-scale-to-y", "-1", str(p), str(tmp)[:-4]]
    else:
        cmd = ["ffmpeg", "-v", "error", "-y", "-ss", "1", "-i", str(p), "-frames:v", "1",
               "-vf", f"scale='min({RENDER_WIDTH},iw)':-2", str(tmp)]
    try:
        subprocess.run(cmd, capture_output=True, timeout=15, check=True)
        os.replace(tmp, out)
    except (OSError, subprocess.SubprocessError):
        tmp.unlink(missing_ok=True)
        return None
    return str(out)


def peek(path, long=False):
    p = Path(path)
    st = p.lstat()
    out = {"path": str(p), "name": p.name, "link": "", "modified": iso(st.st_mtime), "size": st.st_size}
    if stat.S_ISLNK(st.st_mode):
        out["link"] = os.readlink(p)
        try:
            st = p.stat()
        except OSError:
            out.update(type="", kind="Link to nothing", dir=False)
            return out
    out["dir"] = stat.S_ISDIR(st.st_mode)
    if out["dir"]:
        try:
            names = os.listdir(p)
            out["items"] = len([n for n in names if not n.startswith(".")])
            out["hidden"] = len(names) - out["items"]
        except OSError:
            out["items"] = None
        out.update(type="inode/directory", kind="Folder")
        return out
    out["size"] = st.st_size
    t, desc = content_type(p)
    out["type"], out["kind"] = t, desc or t or "File"
    out["executable"] = bool(st.st_mode & 0o111)
    if p.suffix.lower() in IMAGES or t.startswith("image/"):
        out["image"] = True
        out["pixels"] = _image_size(p)
    elif t == "application/pdf" or p.suffix.lower() == ".pdf":
        out["picture"] = rendered(p, st, "pdf")
    elif t.startswith("video/") or p.suffix.lower() in VIDEOS:
        out["picture"] = rendered(p, st, "video")
    elif t.startswith("text/") or t in TEXTY or t.endswith(("+xml", "+json")) or not t or t == "application/octet-stream":
        text = _text(p, long)
        if text is not None:
            out["text"] = text
    return out
