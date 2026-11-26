#!/usr/bin/python3 -I
"""web_download (#2242, log 4035): a file from the web into Ask Claude's own folder for this conversation, where its
result cards (#2243) show it and the user saves what they want from it. Claude never reads a file back: what it gets
is the file's id, type and size, so a downloaded file can't carry instructions to it.

Limits, as the folder is filled by what a web page may have asked for:
- public web servers only (netguard.py: no localhost or LAN, on any redirect either);
- FILE_MAX a file and RUN_MAX a conversation, counted as it streams (a server's Content-Length isn't trusted);
- the type is read from the content (sniff.py), never from the name or the server: audio, pictures, PDF and zip (not
  unpacked), each saved with its type's own extension, so nothing lands that would run as it opens;
- a clean name, mode 600, and the address in the xattr user.xdg.origin.url (as browsers keep it, for Files).

The folder is the conversation's (~/.local/state/nightdrive/ask/<id>/files), which ask-claude gives the MCP server in
NIGHTDRIVE_ASK_FILES: without it (a terminal session) nothing is downloaded.

    download.py get URL [--name NAME]          downloads; prints {id, type, size}
    download.py folder                         the folder as JSON ({folder}): the tool's `before`, for its undo
    download.py remove --folder FOLDER ID      deletes a file it downloaded (the undo)
"""
import http.client, json, os, re, sys, tempfile, time
from pathlib import Path
from urllib.parse import unquote, urlsplit

sys.path.insert(0, str(Path(__file__).resolve().parent))   # -I leaves the script's folder out
import netguard   # noqa: E402
import sniff      # noqa: E402

ENV = "NIGHTDRIVE_ASK_FILES"
STATE = Path(os.environ.get("XDG_STATE_HOME") or Path.home() / ".local/state") / "nightdrive/ask"
FILE_MAX = 25 * 1024 * 1024
RUN_MAX = 200 * 1024 * 1024
TIME_MAX = 100        # seconds for one download, under the tool's timeout (web.json: 120)
CHUNK = 64 * 1024
STEM_MAX = 80         # characters of a name before its extension
ORIGIN = "user.xdg.origin.url"
# Extensions a name may end in that the type's own replaces (photo.jpeg → photo.jpg)
KNOWN = {"ogg", "oga", "mp3", "wav", "flac", "png", "jpg", "jpeg", "webp", "gif", "pdf", "zip"}


def die(msg, code=1):
    print(msg, file=sys.stderr)
    sys.exit(code)


def own_folder(path):
    """A path as the conversation folder it must be (STATE/<id>/files, no link on the way), resolved; else dies. The
    undo's folder comes from the change log, a file of the user's that anything they run can write."""
    folder = Path(path).absolute()
    real = folder.resolve()
    if folder.is_symlink() or folder.parent.is_symlink() or real.parent.parent != STATE.resolve() \
            or real.name != "files" or not re.fullmatch(r"[A-Za-z0-9-]{1,64}", real.parent.name):
        die(f"{path} isn't an Ask Claude conversation's own folder.")
    return real


def folder_from_env():
    if not os.environ.get(ENV):
        die("web_download works only in Ask Claude (the launcher's ⌘⌥Enter): what it downloads goes into that "
            "conversation's own folder.")
    folder = Path(os.environ[ENV]).absolute()
    if folder.parent.parent.resolve() == STATE.resolve():   # ask-claude makes it; a check before making one
        folder.mkdir(parents=True, exist_ok=True, mode=0o700)
    return own_folder(folder)


def used(folder):
    """Bytes in the folder now: its files, half-downloaded ones too."""
    return sum(e.stat(follow_symlinks=False).st_size for e in os.scandir(folder) if e.is_file(follow_symlinks=False))


def clean_stem(name):
    """A name safe to show and keep: letters, digits, spaces, - and _, no dots in front, its extension dropped when
    it is one of the kept types' (the type's own is put on instead)."""
    name = unquote(name).rsplit("/", 1)[-1]
    stem, dot, ext = name.rpartition(".")
    if dot and ext.lower() in KNOWN:
        name = stem
    name = re.sub(r"[^\w \-]+", "-", name, flags=re.UNICODE)
    name = re.sub(r"[\s]+", " ", re.sub(r"-{2,}", "-", name)).strip(" -_.")
    return name[:STEM_MAX].strip(" -_") or "download"


def claim(folder, stem, ext):
    """A new file's name in the folder (stem.ext, stem-2.ext…), created empty so no other download takes it."""
    for n in range(1, 1000):
        name = f"{stem}.{ext}" if n == 1 else f"{stem}-{n}.{ext}"
        try:
            os.close(os.open(folder / name, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600))
            return name
        except FileExistsError:
            continue
    die(f"The folder has too many files named {stem}.")


def fetch(url, part, limit):
    """Streams url's body into the open file part, at most limit bytes; returns (bytes, final url)."""
    deadline = time.monotonic() + TIME_MAX
    try:
        response, final = netguard.open_url(url, deadline)
    except netguard.BlockedError as e:
        die(str(e))
    except (OSError, ValueError, http.client.HTTPException) as e:   # ssl.SSLError and timeouts are OSErrors
        die(f"The download failed: {e}")
    declared = response.getheader("Content-Length")
    if declared and declared.isdigit() and int(declared) > limit:
        die(too_big(limit))
    size = 0
    try:
        while chunk := response.read(CHUNK):
            size += len(chunk)
            if size > limit:
                die(too_big(limit))
            if time.monotonic() > deadline:
                die(f"The download took over {TIME_MAX} s: nothing was kept.")
            part.write(chunk)
    except (OSError, http.client.HTTPException) as e:
        die(f"The download broke off: {e!r}")
    finally:
        response.close()
    return size, final


def too_big(limit):
    if limit < FILE_MAX:
        return f"The file is bigger than this conversation's {limit // 1024 // 1024} MB left: nothing was kept."
    return f"The file is bigger than {FILE_MAX // 1024 // 1024} MB: nothing was kept."


def cmd_get(url, name=None):
    folder = folder_from_env()
    limit = min(FILE_MAX, RUN_MAX - used(folder))
    if limit <= 0:
        die(f"This conversation has downloaded {RUN_MAX // 1024 // 1024} MB already: nothing more is.")
    fd, tmp = tempfile.mkstemp(prefix=".part-", dir=folder)   # mode 600, hidden: not yet one of the files
    try:
        with os.fdopen(fd, "wb") as part:
            size, final = fetch(url, part, limit)
        if size == 0:
            die("The server sent an empty file: nothing was kept.")
        with open(tmp, "rb") as f:
            found = sniff.kind(f.read(sniff.HEAD))
        if not found:
            die("The file isn't one of the types downloaded: audio (ogg, mp3, wav, flac), pictures (png, jpeg, webp, "
                "gif), PDF or zip. Give the file's own address, not a page's.")
        mime, ext = found
        stem = clean_stem(name or urlsplit(final).path or "download")
        kept = claim(folder, stem, ext)
        os.replace(tmp, folder / kept)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)
    try:
        os.setxattr(folder / kept, ORIGIN, url.encode())
    except OSError:
        pass   # a file system without user xattrs: the file is all that matters
    print(json.dumps({"id": kept, "type": mime, "size": size}))


def cmd_remove(folder, file_id):
    folder = own_folder(folder)
    if not re.fullmatch(r"[^/\x00]{1,255}", file_id) or file_id.startswith("."):
        die(f"{file_id!r} isn't a downloaded file's id.")
    path = folder / file_id
    if path.is_symlink() or not path.is_file():
        die(f"{file_id} isn't in the conversation's folder (any more).")
    path.unlink()
    print(json.dumps({"removed": file_id}))


def main(argv):
    if len(argv) in (2, 4) and argv[0] == "get" and (len(argv) == 2 or argv[2] == "--name"):
        cmd_get(argv[1], argv[3] if len(argv) == 4 else None)
    elif argv == ["folder"]:
        print(json.dumps({"folder": str(folder_from_env())}))
    elif len(argv) == 4 and argv[0] == "remove" and argv[1] == "--folder":
        cmd_remove(argv[2], argv[3])
    else:
        die(__doc__.rsplit("\n\n", 1)[-1], 2)


if __name__ == "__main__":
    main(sys.argv[1:])
