"""An Inbox file to the page so that <audio> and <video> play it (#3331): iOS asks for media in byte ranges (first
bytes=0-1, then pieces as it plays and seeks) and won't play a file served only whole, so a Range gets 206 with its
Content-Range. And Safari plays no Ogg/Opus: the page asks for such audio as AAC (?as=m4a), which ffmpeg makes once
and keeps in a cache, keyed by the file's path, size and time, so a ranged request reads a finished file.

Video isn't converted (a long encode on a request): one Safari can't play stays a link on the page.
"""
import hashlib
import os
import re
import shutil
import subprocess
import threading
import time

RANGE = re.compile(r"^bytes=(\d*)-(\d*)$")
CHUNK = 256 * 1024          # bytes written at a time: a long file isn't read into memory
CACHE = os.path.join(os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache"), "nightdrive", "companion",
                     "media")
CONVERT_TIMEOUT = 180       # seconds ffmpeg may take: a voice note takes a second, an hour of audio about a minute
KEEP_DAYS = 30              # a converted file not asked for in this long is removed
_lock = threading.Lock()    # iOS sends several ranged requests at once: one conversion, the others wait for it


class MediaError(ValueError):
    """It can't be converted (no ffmpeg, not audio, ffmpeg failed): the page keeps its link."""


def byte_range(header, size):
    """(start, end) inclusive for a Range header, None for the whole file. One range only: several, or a unit other
    than bytes, get the whole file, as RFC 9110 allows. Raises ValueError when it starts past the end (416)."""
    m = RANGE.match((header or "").strip())
    if not m or not (m.group(1) or m.group(2)):
        return None
    first, last = m.group(1), m.group(2)
    if not first:                       # bytes=-500: the last 500
        n = int(last)
        if n == 0:
            raise ValueError("empty suffix")
        return max(0, size - n), size - 1
    start = int(first)
    end = min(int(last), size - 1) if last else size - 1
    if start >= size or start > end:
        raise ValueError("past the end")
    return start, end


def send(handler, path, ctype):
    """The file to the request: 200 whole, 206 a range, 416 a range past its end."""
    size = os.path.getsize(path)
    try:
        span = byte_range(handler.headers.get("Range"), size)
    except ValueError:
        handler.send_response(416)
        handler.send_header("Content-Range", f"bytes */{size}")
        handler.send_header("Content-Length", "0")
        handler.end_headers()
        return
    start, end = span or (0, size - 1)
    handler.send_response(206 if span else 200)
    handler.send_header("Content-Type", ctype)
    handler.send_header("Accept-Ranges", "bytes")
    handler.send_header("Content-Length", str(max(0, end - start + 1)))
    if span:
        handler.send_header("Content-Range", f"bytes {start}-{end}/{size}")
    handler.send_header("Cache-Control", "no-cache")
    handler.end_headers()
    left = end - start + 1
    try:
        with open(path, "rb") as f:
            f.seek(start)
            while left > 0:
                data = f.read(min(CHUNK, left))
                if not data:
                    break
                handler.wfile.write(data)
                left -= len(data)
    except (BrokenPipeError, ConnectionResetError):
        pass                            # the player asked for a range and moved on: it does that


def as_m4a(path, ctype):
    """The audio file as AAC in an .m4a from the cache, converted first if it isn't there yet."""
    if not ctype.startswith("audio/"):
        raise MediaError("Only audio is converted")
    ffmpeg = shutil.which("ffmpeg")
    if not ffmpeg:
        raise MediaError("ffmpeg isn't installed")
    st = os.stat(path)
    key = hashlib.sha256(f"{os.path.realpath(path)}|{st.st_size}|{st.st_mtime_ns}".encode()).hexdigest()[:24]
    out = os.path.join(CACHE, key + ".m4a")
    with _lock:
        if os.path.isfile(out):
            os.utime(out)               # asked for: kept another KEEP_DAYS
            return out
        os.makedirs(CACHE, exist_ok=True)
        prune()
        tmp = out + ".part"
        # faststart puts the index first, so the player starts before it has the whole file
        p = subprocess.run([ffmpeg, "-nostdin", "-v", "error", "-y", "-i", path, "-vn", "-c:a", "aac", "-b:a", "128k",
                            "-movflags", "+faststart", "-f", "mp4", tmp],
                           capture_output=True, text=True, timeout=CONVERT_TIMEOUT)
        if p.returncode or not os.path.isfile(tmp):
            if os.path.exists(tmp):
                os.remove(tmp)
            raise MediaError(f"ffmpeg couldn't convert it: {p.stderr.strip()[-200:]}")
        os.replace(tmp, out)
        return out


def prune():
    """Converted files not asked for in KEEP_DAYS, and parts a crash left, out of the cache."""
    old = time.time() - KEEP_DAYS * 86400
    for name in os.listdir(CACHE):
        full = os.path.join(CACHE, name)
        try:
            if name.endswith(".part") or os.path.getmtime(full) < old:
                os.remove(full)
        except OSError:
            pass
