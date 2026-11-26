#!/usr/bin/python3 -I
"""Save on an Ask Claude result card (#2245, #2225): a file Claude downloaded into the conversation's own folder
(web_download, config/mcp/web/download.py) copied into the user's Downloads. Only the card's button runs this, never
Claude: there is no tool for it, as what lands in Downloads is the user's choice.

    save.py [--into FOLDER] ID FILE     prints {"path", "name"}; a failure goes to stderr with exit status 1

- ID is the conversation's (a uuid), FILE the download's id: a plain name in ~/.local/state/nightdrive/ask/ID/files,
  no link, no half-downloaded .part, as results.py takes it.
- Nothing is overwritten: a name already there gets " (2)", " (3)" … and is created exclusively, so not even a file
  that appears meanwhile is replaced. The copy is 0644: nothing saved can be run.
- Where it came from goes with it, as browsers keep it (Files shows it): the download's own address in
  user.xdg.origin.url, and the page its card names (where its licence is) in user.xdg.referrer.url. A file system
  without user xattrs saves the file without them.
"""
import json, os, re, shutil, sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))   # files_rules.py, beside ask-claude
from files_rules import die, user_dir  # noqa: E402

STATE = Path(os.environ.get("XDG_STATE_HOME") or Path.home() / ".local/state") / "nightdrive/ask"
ORIGIN = "user.xdg.origin.url"
REFERRER = "user.xdg.referrer.url"
TRIES = 100          # names tried for a free one: "name (2)" … "name (100)"
ID = re.compile(r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}")


def candidates(name):
    """The names tried in turn: the file's own, then "stem (2).ext" up to TRIES. A double extension (.tar.gz) isn't
    one of web_download's types, so the last suffix is the extension."""
    stem, ext = os.path.splitext(name)
    if not stem:          # ".ogg" alone: no stem to number
        stem, ext = name, ""
    yield name
    for n in range(2, TRIES + 1):
        yield f"{stem} ({n}){ext}"


def source(conv, file_id):
    """The download's path in conversation conv; dies on an id that isn't one of its files."""
    if not ID.fullmatch(conv or ""):
        die("ID must be a conversation's id.")
    if not re.fullmatch(r"[^/\x00]{1,255}", file_id or "") or file_id.startswith(".") or file_id.endswith(".part"):
        die(f"{file_id!r} isn't a downloaded file's id.")
    path = STATE / conv / "files" / file_id
    if path.is_symlink() or not path.is_file():
        die(f"{file_id} isn't one of this conversation's downloads (it may have gone with the conversation).")
    return path


def page_of(conv, file_id):
    """The page the file's card names (results.json), or None"""
    try:
        cards = json.loads((STATE / conv / "results.json").read_text(encoding="utf-8")).get("cards") or []
    except (OSError, ValueError, AttributeError):
        return None
    for c in cards:
        if isinstance(c, dict) and c.get("file") == file_id and isinstance(c.get("url"), str):
            return c["url"]
    return None


def create(folder, name):
    """Opens the first free name in folder exclusively: (fd, path)"""
    for candidate in candidates(name):
        path = folder / candidate
        try:
            return os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o644), path
        except FileExistsError:
            continue
    die(f"{folder} has {name} and {TRIES - 1} numbered copies of it already.")


def keep_source(src, dst, page):
    """Where the file came from, on the copy; a file system without user xattrs just goes without"""
    tags = {}
    try:
        tags[ORIGIN] = os.getxattr(src, ORIGIN)
    except OSError:
        pass
    if page:
        tags[REFERRER] = page.encode()
    for key, value in tags.items():
        try:
            os.setxattr(dst, key, value)
        except OSError:
            pass


def save(conv, file_id, into=None):
    src = source(conv, file_id)
    folder = Path(into) if into else user_dir("DOWNLOAD")
    if folder is None:
        die("There is no Downloads folder.")
    try:
        folder.mkdir(parents=True, exist_ok=True)
    except OSError as e:
        die(f"Can't make {folder}: {e.strerror}.")
    fd, path = create(folder, file_id)
    try:
        with open(src, "rb") as f, os.fdopen(fd, "wb") as out:
            shutil.copyfileobj(f, out)
        os.chmod(path, 0o644)     # whatever the umask: readable, never runnable
    except OSError as e:
        path.unlink(missing_ok=True)
        die(f"Can't save {file_id}: {e.strerror}.")
    keep_source(src, path, page_of(conv, file_id))
    return path


def main(argv):
    into = None
    if argv[:1] == ["--into"] and len(argv) >= 2:
        into, argv = argv[1], argv[2:]
    if len(argv) != 2:
        die(__doc__.split("\n\n")[1].strip(), 2)
    path = save(*argv, into=into)
    print(json.dumps({"path": str(path), "name": path.name}, ensure_ascii=False))


if __name__ == "__main__":
    main(sys.argv[1:])
