"""The rules every file tool of Claude's keeps, and your own `nightdrive files` too where they say so (#1849, #1883,
#1995): which paths a call may name, where a link really leads, which folders are never touched. `files` (recent,
open, trash, check) and `files_move.py` (mkdir, move, rename, move-back) import it; its tests are
config/mcp/files_guard_test.py, folders_test.py and files_move_test.py. The rules in words are `files`'s docstring.
"""
import json, os, stat, subprocess, sys
from pathlib import Path

HOME = Path.home().resolve()
USUAL = ("DESKTOP", "DOWNLOAD", "TEMPLATES", "PUBLICSHARE", "DOCUMENTS", "MUSIC", "PICTURES", "VIDEOS")
COUNT_MAX = 100_000   # files counted in a folder for a card; past it the card says "over"
NAME_MAX = 255        # bytes in one name: ext4's and btrfs's limit
# Where Claude's trash and moves never reach, whatever folders it may use (#1883, #1995): the mail store, whose next
# sync deletes on the server what went from here (mbsync's Expunge Both) and uploads what came in; the notes; code.
# Also any mail folder (cur, new and tmp) elsewhere, and any git repository, Nightdrive's own among them (its undo
# runs from it). Nothing is moved out of them or into them
GUARDED = {"Mail": "your mail", "Projects": "your projects"}
NOTES = Path(os.environ.get("NOTES_DIR") or HOME / "Notes")   # plugins/notes/lib/store.py's ROOT
# The folders Claude can use: Access's apps-files `folders` (config/mcp/areas.py). Its entries are ~, ~/A/B or one of
# these, home's own folders by their English names, which xdg-user-dir finds wherever they are (~/Lataukset)
ACCESS_AREA, ACCESS_OPTION = "apps-files", "folders"
STANDARD = {"Desktop": "DESKTOP", "Documents": "DOCUMENTS", "Downloads": "DOWNLOAD", "Music": "MUSIC",
            "Pictures": "PICTURES", "Videos": "VIDEOS"}
WHERE_TO_CHANGE = "Settings › Claude › Access › Apps and files › Folders Claude can use"


def die(msg, code=1):
    print(msg, file=sys.stderr)
    sys.exit(code)


def user_dir(name):
    try:
        out = subprocess.run(["xdg-user-dir", name], capture_output=True, text=True, timeout=5).stdout.strip()
    except (OSError, subprocess.TimeoutExpired):
        out = ""
    fallback = {key: word for word, key in STANDARD.items()}.get(name)
    if out and Path(out).resolve() != HOME:   # xdg-user-dir answers home for a folder that isn't set
        return Path(out).resolve()
    return HOME / fallback if fallback else None


def inside_home(p):
    """A resolved path in home and not hidden (no part starting with a dot)."""
    try:
        rel = p.relative_to(HOME)
    except ValueError:
        return False
    return not any(part.startswith(".") for part in rel.parts)


# --- the folders Claude can use (#1849) ---------------------------------------------------------------------------

def folder_of(entry):
    """One entry of the list as the folder it means, resolved; None for one that isn't a folder in home."""
    if entry in STANDARD:
        folder = user_dir(STANDARD[entry])
    elif entry == "~" or entry.startswith("~/"):
        folder = (HOME / entry[2:]).resolve()
    else:
        return None
    return folder if folder and folder.is_dir() and (folder == HOME or inside_home(folder)) else None


def claude_folders():
    """None for your own use; Claude's: the folders it may use, resolved (a link in the list counts where it leads).
    What can't be read gives none: the list only ever lets more through."""
    if not os.environ.get("NIGHTDRIVE_MCP"):
        return None
    entries = None
    for var, area in (("NIGHTDRIVE_MCP_OPTIONS_FROM", ACCESS_AREA), ("NIGHTDRIVE_MCP_OPTIONS", None)):
        try:
            options = json.loads(os.environ.get(var) or "{}")
            options = options.get(area, {}) if area else options
            entries = options.get(ACCESS_OPTION, entries) if isinstance(options, dict) else entries
        except ValueError:
            pass
        if entries is not None:
            break
    if not isinstance(entries, list):
        return []
    return list(dict.fromkeys(f for e in entries if isinstance(e, str) for f in [folder_of(e)] if f))


def within(path, folders, below=False):
    """Whether a resolved path is in one of the folders (below=True: inside it, not the folder itself)."""
    return any(f in path.parents or (path == f and not below) for f in folders)


def refuse_outside(arg, folders):
    named = ", ".join(shown(f) if f != HOME else "~" for f in folders)
    allowed = f"the folders Claude may use ({named})" if folders else "any folder: Claude may use none now"
    die(f"{arg} is outside {allowed}. The user can change them in {WHERE_TO_CHANGE}.")


def one_name(path, arg):
    """Claude's: a file with another name too (a hard link) isn't opened or sent. Its other name may be in a hidden
    folder or outside Claude's folders (Downloads/key and ~/.ssh/id_ed25519 are one file), and nothing tells where:
    resolve() follows a symbolic link, not a hard one (#1864). Only someone with a shell makes one (the user, Claude
    Code's own commands), so it is refused rather than looked for; a trash moves just the one name, and is let be."""
    try:
        st = os.stat(path)
    except OSError:
        return
    if stat.S_ISREG(st.st_mode) and st.st_nlink > 1:
        die(f"{arg} is a hard link: the same file has another name too, which may be anywhere, so Claude doesn't open "
            "or send it. Copy it (cp) and give the copy.")


def guarded(path):
    """What of Claude's no-go places for a trash or a move (GUARDED) a path is in, in words; None when in none."""
    places = {(HOME / name).resolve(): what for name, what in GUARDED.items()}
    places[NOTES.resolve()] = "your notes"
    for p in (path, *path.parents):
        if p == HOME:
            return None   # home itself in git (a dotfiles repo) doesn't guard all of it
        if p in places:
            return places[p]
        if os.path.lexists(p / ".git"):
            return "a git repository"
        if all((p / d).is_dir() for d in ("cur", "new", "tmp")):
            return "a mail folder"
    return None


def checked(arg, moving=False, sending=False, doing="move anything there to the trash"):
    """The path a PATH argument means, by the rules above; dies with the reason otherwise. Its folder is resolved
    (no link leads it out), the last part is kept as it is: trashing a link moves the link, not what it points to.
    doing: what Claude doesn't do in a guarded place, for the refusal."""
    p = Path(arg).expanduser()
    p = p if p.is_absolute() else HOME / p
    folders = claude_folders()
    # Claude's folders first, so a refusal doesn't tell whether something exists outside them
    if folders is not None and not within(p.parent.resolve() / p.name, folders, below=moving):
        refuse_outside(arg, folders)
    # Out of home or hidden by where it would be, before anything about whether it is there: ~/.ssh/id_rsa and
    # ~/.ssh/nothing get the same answer (Open's folders are the whole home, #1883)
    if p.name in ("", ".", "..") or not inside_home(p.parent.resolve() / p.name):
        die(f"{arg}: only files in your home folder, and none hidden (settings, keys, the trash).")
    try:
        folder = p.parent.resolve(strict=True)
    except OSError:
        die(f"{arg}: no such folder.")
    path = folder / p.name
    if not os.path.lexists(path):
        die(f"{arg} doesn't exist.")
    if not inside_home(path):
        die(f"{arg}: only files in your home folder, and none hidden (settings, keys, the trash).")
    verb = "moved" if moving else "sent whole" if sending else "opened"
    if moving or sending:
        usual = {user_dir(n) for n in USUAL}
        # A link is sent as what it points to, so that is checked too (a link in Downloads to home); trash moves links
        whole = {path, path.resolve()} if sending else {path}
        if whole & ({HOME} | usual):
            die(f"{arg} is one of your home's own folders: it isn't {verb}.")
    if not moving and not inside_home(path.resolve()):
        die(f"{arg} is a link that leads out of your home folder (or into a hidden one): it isn't {verb.split()[0]}.")
    if folders is not None:
        # Where it lies (above) and, as it is opened or sent as what it points to, where it leads; a folder Claude
        # may use isn't trashed itself (taking it away isn't using what is in it)
        if not within(path, folders, below=moving) or (not moving and not within(path.resolve(), folders)):
            refuse_outside(arg, folders)
        if not moving:
            one_name(path.resolve(), arg)
        elif guarded(path):
            die(f"{arg} is in {guarded(path)}: Claude doesn't {doing}. The user can, in Files.")
    return path



def size_text(n):
    for unit in ("bytes", "kB", "MB", "GB"):
        if n < 1000 or unit == "GB":
            return f"{n} {unit}" if unit == "bytes" else f"{n:.1f} {unit}"
        n /= 1000


def shown(path):
    """A path as the card shows it: ~ for home, and a newline in a name spelled out, so a name can't pass for lines
    of its own (confirm.py spells out what hides or reorders text)."""
    rel = path.relative_to(HOME)
    return ("~/" + str(rel)).replace("\n", "\\n").replace("\r", "\\r")


def count(path):
    """A folder's files and their size, (files, bytes), links to folders counted as a file and not followed: what
    goes with it. At COUNT_MAX it stops counting."""
    files, size = 0, 0
    for root, dirs, names in os.walk(path):
        for n in names + [d for d in dirs if os.path.islink(os.path.join(root, d))]:
            files += 1
            try:
                size += os.lstat(os.path.join(root, n)).st_size
            except OSError:
                pass
            if files >= COUNT_MAX:
                return files, size
    return files, size


def what_goes(path):
    """One path for a card: a file and its size, a link, or a folder with everything in it, as all of it goes."""
    if path.is_symlink():
        return f"{shown(path)}  (a link: only the link goes)"
    if not path.is_dir():
        return f"{shown(path)}  ({size_text(path.lstat().st_size)})"
    files, size = count(path)
    if files >= COUNT_MAX:
        return f"{shown(path)}  (a folder of over {COUNT_MAX:,} files)"
    many = "an empty folder" if not files else f"a folder of {files} file{'s' * (files != 1)}, {size_text(size)}"
    return f"{shown(path)}  ({many})"


# --- where a new folder or a move goes (#1995) -------------------------------------------------------------------

def what_of(paths):
    """Paths for a notice: the one's name, or how many of what."""
    if len(paths) == 1:
        return paths[0].name
    folders = sum(p.is_dir() and not p.is_symlink() for p in paths)
    kinds = "folders" if folders == len(paths) else "files" if not folders else "files and folders"
    return f"{len(paths)} {kinds}"


def valid_name(name, arg=None):
    """A new name for a file or a folder: one part, not hidden, no control characters (a newline would pass for a
    line of its own on the card) and not too long; dies otherwise."""
    arg = arg or repr(name)
    if not name or name in (".", "..") or "/" in name or "\0" in name:
        die(f"{arg} isn't a name: one part, without /.")
    if name.startswith("."):
        die(f"{arg} would be hidden: Claude doesn't make hidden files or folders.")
    if any(ord(c) < 32 or ord(c) == 127 for c in name):
        die(f"{arg} has a control character (a newline, a tab) in it.")
    if len(name.encode("utf-8", "surrogateescape")) > NAME_MAX:
        die(f"{arg} is longer than {NAME_MAX} bytes.")
    return name


def destination(arg, new=None):
    """The folder a move goes into, or a new folder (mkdir), resolved: in home, not hidden, in Claude's folders and in
    none of GUARDED's places, by where it really is (a link to a folder counts where it leads). Its parent must
    exist: one level is made, not a path of them. new=True: it mustn't exist yet (mkdir); False: it must, as a
    folder; None: either (a move makes it). Returns (path, whether it is to be made); dies with the reason."""
    p = Path(arg).expanduser()
    p = p if p.is_absolute() else HOME / p
    folders = claude_folders()
    where = p.parent.resolve() / p.name
    # As checked: Claude's folders first, then home and hidden, before anything about what exists there
    if folders is not None and not within(where.resolve(), folders):
        refuse_outside(arg, folders)
    if p.name in ("", ".", "..") or not inside_home(where):
        die(f"{arg}: only folders in your home folder, and none hidden (settings, keys, the trash).")
    try:
        parent = p.parent.resolve(strict=True)
    except OSError:
        die(f"{arg}: its folder {shown(where.parent) if inside_home(where.parent) else where.parent} doesn't exist "
            "(one folder is made at a time).")
    path = parent / p.name
    exists = os.path.lexists(path)
    if exists and new is True:
        die(f"{arg} exists already.")
    if not exists and new is False:
        die(f"{arg} doesn't exist.")
    if exists:
        path = path.resolve()   # a link to a folder: where it leads is checked, and moved into
        if not path.is_dir():
            die(f"{arg} isn't a folder.")
        if not inside_home(path):
            die(f"{arg} leads out of your home folder (or into a hidden one).")
        if folders is not None and not within(path, folders):
            refuse_outside(arg, folders)
    else:
        valid_name(p.name, arg)
    if folders is not None and guarded(path):
        die(f"{arg} is in {guarded(path)}: Claude doesn't move anything there. The user can, in Files.")
    return path, not exists
