"""The games on this computer (#3530), for the Launcher's Games page, `nightdrive games` and the controller's Xbox button.

Two sources:
- .desktop files whose Categories has Game (Cold Start '74, a Flatpak game), where the launcher finds apps. Steam's own
  entry is left out: it is a store, not a game. So are the entries Steam writes for its games (Exec steam
  steam://rungameid/ID): the same games come from Steam's own list below, with their download state.
- Steam's library: every library folder in libraryfolders.vdf, each game's steamapps/appmanifest_<id>.acf. Proton,
  the Steam Linux Runtime and the other tools Steam installs as apps are not games, so they are left out.

A game is a dict: id ("desktop:<file id>" or "steam:<appid>"), name, source, icon (a theme name or a path, "" for
none), installed (false while Steam is still downloading it), progress (0–100 while downloading, else null), cover
(a 2:3 picture, "" for none: Steam's, or a .desktop file's X-Nightdrive-Cover) and hero (a wide one for behind it), and
for a .desktop game its path. Paths come from the environment so the tests can point them at a throwaway home."""

import configparser
import glob
import os
import re

HOME = os.path.expanduser("~")
# Where Steam may keep its root: the native package's, and the older ~/.steam/steam link to it
STEAM_ROOTS = ("~/.local/share/Steam", "~/.steam/steam")
# Steam's apps that aren't games (Proton, runtimes, redistributables): by name, and the ids whose names don't say so
TOOL_NAME = re.compile(r"^(Proton\b|Steam Linux Runtime|Steamworks Common|Steam Controller Configs|SteamVR)", re.I)
TOOL_IDS = {"228980", "1070560", "1391110", "1628350", "1493710", "2180100", "4183110", "250820"}
# appmanifest StateFlags: 4 = fully installed (the others are update and download states)
FULLY_INSTALLED = 4
# The system's Flatpak exports (the user's are under HOME)
FLATPAK_SYSTEM = "/var/lib/flatpak/exports/share"


def data_dirs():
    """XDG data dirs, the user's first: where .desktop files are looked for, as the launcher does."""
    home = os.environ.get("XDG_DATA_HOME") or os.path.join(HOME, ".local/share")
    rest = os.environ.get("XDG_DATA_DIRS") or "/usr/local/share:/usr/share"
    dirs = [home] + [d for d in rest.split(":") if d]
    # Flatpak's exports, in case the session's XDG_DATA_DIRS lacks them
    for d in (os.path.join(HOME, ".local/share/flatpak/exports/share"), FLATPAK_SYSTEM):
        if d not in dirs:
            dirs.append(d)
    return dirs


def read_desktop(path):
    """The [Desktop Entry] group as a dict, or None when it can't be read."""
    cp = configparser.ConfigParser(interpolation=None, strict=False)
    cp.optionxform = str   # keys are case-sensitive (Name, NoDisplay)
    try:
        cp.read(path, encoding="utf-8")
        return dict(cp["Desktop Entry"])
    except (configparser.Error, KeyError, UnicodeDecodeError, OSError):
        return None


def desktop_games():
    """Games from .desktop files: the first file of each id wins, as the user's own overrides the system's."""
    seen, out = set(), []
    for base in data_dirs():
        for path in sorted(glob.glob(os.path.join(base, "applications", "**", "*.desktop"), recursive=True)):
            fid = os.path.relpath(path, os.path.join(base, "applications")).replace("/", "-")[:-len(".desktop")]
            if fid in seen:
                continue
            seen.add(fid)
            e = read_desktop(path)
            if not e or e.get("Type", "Application") != "Application":
                continue
            if e.get("NoDisplay", "").lower() == "true" or e.get("Hidden", "").lower() == "true":
                continue
            if "Game" not in [c.strip() for c in e.get("Categories", "").split(";")]:
                continue
            exe = e.get("Exec", "")
            # Steam itself, and Steam's shortcuts to its games (those come from its library, below)
            if fid == "steam" or "steam://rungameid/" in exe or re.match(r"^(\S*/)?steam(\s|$)", exe):
                continue
            out.append({"id": "desktop:" + fid, "name": e.get("Name", fid), "source": "desktop",
                        "icon": e.get("Icon", ""), "installed": True, "progress": None, "path": path,
                        # A game of your own can give its cover and backdrop (a path) in its .desktop file
                        "cover": e.get("X-Nightdrive-Cover", ""), "hero": e.get("X-Nightdrive-Hero", "")})
    return out


def parse_vdf(text):
    """Valve's KeyValues text (libraryfolders.vdf, appmanifest .acf) as nested dicts of strings."""
    tokens = re.findall(r'"((?:[^"\\]|\\.)*)"|([{}])', text)
    stack, cur, key = [], {}, None
    for s, brace in tokens:
        if brace == "{":
            new = {}
            if key is not None:
                cur[key] = new
            stack.append(cur)
            cur, key = new, None
        elif brace == "}":
            cur = stack.pop() if stack else cur
            key = None
        elif key is None:
            key = s
        else:
            cur[key] = s
            key = None
    return cur


def read_vdf(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            return parse_vdf(f.read())
    except OSError:
        return {}


def steam_root():
    """Steam's folder, or "" when Steam has never run here."""
    for r in STEAM_ROOTS:
        p = os.path.realpath(os.path.expanduser(r))
        if os.path.isdir(os.path.join(p, "steamapps")):
            return p
    return ""


def steam_libraries(root):
    """Every library folder's steamapps, the root's first; a folder on a drive that isn't there is skipped."""
    libs = [os.path.join(root, "steamapps")]
    folders = read_vdf(os.path.join(root, "steamapps", "libraryfolders.vdf")).get("libraryfolders", {})
    for v in folders.values():
        path = v.get("path") if isinstance(v, dict) else None
        if path:
            sa = os.path.join(path, "steamapps")
            if os.path.isdir(sa) and os.path.realpath(sa) not in map(os.path.realpath, libs):
                libs.append(sa)
    return libs


def steam_icon(root, appid):
    """The game's small icon: one Steam put in the icon theme (steam_icon_<id>), else the 32 px one in its library
    cache (the .jpg directly in appcache/librarycache/<id>/, named by a hash)."""
    for size in ("256x256", "128x128", "64x64", "48x48", "32x32"):
        p = os.path.join(HOME, ".local/share/icons/hicolor", size, "apps", f"steam_icon_{appid}.png")
        if os.path.isfile(p):
            return p
    found = sorted(glob.glob(os.path.join(root, "appcache", "librarycache", appid, "*.jpg")))
    return found[0] if found else ""


def steam_art(root, appid, *names):
    """A picture from Steam's library cache, the first of names found: in the game's folder (where newer Steam keeps
    them, each in a hash-named folder of its own) or flat as <id>_<name> (older Steam). "" for none."""
    cache = os.path.join(root, "appcache", "librarycache")
    for n in names:
        found = sorted(glob.glob(os.path.join(cache, appid, "**", n), recursive=True))
        stem, ext = os.path.splitext(n)
        found = found or sorted(glob.glob(os.path.join(cache, f"{appid}_{stem}{ext}")))
        if found:
            return found[0]
    return ""


def steam_games():
    root = steam_root()
    if not root:
        return []
    out, seen = [], set()
    for lib in steam_libraries(root):
        for path in sorted(glob.glob(os.path.join(lib, "appmanifest_*.acf"))):
            st = read_vdf(path).get("AppState", {})
            appid, name = st.get("appid", ""), st.get("name", "")
            if not appid or not name or appid in seen or appid in TOOL_IDS or TOOL_NAME.match(name):
                continue
            seen.add(appid)
            try:
                flags = int(st.get("StateFlags", "0"))
            except ValueError:
                flags = 0
            installed = bool(flags & FULLY_INSTALLED)
            progress = None
            if not installed:
                try:
                    total, done = int(st.get("BytesToDownload", "0")), int(st.get("BytesDownloaded", "0"))
                    progress = min(99, done * 100 // total) if total > 0 else 0
                except ValueError:
                    progress = 0
            out.append({"id": "steam:" + appid, "name": name, "source": "steam", "icon": steam_icon(root, appid),
                        "installed": installed, "progress": progress,
                        "cover": steam_art(root, appid, "library_capsule.jpg", "library_600x900.jpg"),
                        "hero": steam_art(root, appid, "library_hero.jpg")})
    return out


def all_games():
    """Every game, by name (case-insensitive)."""
    return sorted(desktop_games() + steam_games(), key=lambda g: g["name"].casefold())


def find(game_id):
    return next((g for g in all_games() if g["id"] == game_id), None)


def steam_game_running(proc="/proc"):
    """The appid of the Steam game running now, or "": Steam starts each one under its reaper with SteamLaunch
    AppId=<id> on the command line (also when FEX runs it on an ARM Mac). The Xbox button is the Steam overlay's then."""
    for pid in os.listdir(proc):
        if not pid.isdigit():
            continue
        try:
            with open(os.path.join(proc, pid, "cmdline"), "rb") as f:
                args = f.read().split(b"\0")
        except OSError:
            continue
        if b"SteamLaunch" in args:
            for a in args:
                m = re.match(rb"AppId=(\d+)$", a)
                if m:
                    return m.group(1).decode()
            return "?"
    return ""
