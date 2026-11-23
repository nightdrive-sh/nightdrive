#!/usr/bin/env python3
"""The apps that can open a file, for Files' Open with (O, app/OpenWith.qml).

  apps.py list FILE...                     JSON: the first file's type, its default app and the apps to offer
  apps.py open APP.desktop [--default] FILE...
                                           open the files in APP; --default makes it the type's default first

The list is GIO's (the same the desktop's "Open with" dialogs show): the default first, then the apps recommended for
the type, then the rest that say they open it ("type"), and after them every other app the launcher shows ("other"):
a type no app claims (a script, a log with no ending) still opens in an editor picked by name. Files itself stays out.
The default is written by GIO to ~/.config/mimeapps.list for this one type, as Settings › Default apps does for a kind
(hypr/scripts/default-apps); the files open through gtk-launch, as the launcher starts apps.
"""
import json, os, sys

import gi
gi.require_version("Gio", "2.0")
from gi.repository import Gio
try:                                         # GLib 2.86 moved it; Gio's name still works there, with a warning
    gi.require_version("GioUnix", "2.0")
    from gi.repository import GioUnix
    DesktopAppInfo = GioUnix.DesktopAppInfo
except (ImportError, ValueError):
    DesktopAppInfo = Gio.DesktopAppInfo

SELF = "nightdrive-files.desktop"           # Files' own entry (share/files.desktop): not an app to open a file in


def content_type(path):
    """The file's type as GIO sees it: by its content, its name for one that can't be read; a folder is inode/directory."""
    try:
        info = Gio.File.new_for_path(path).query_info("standard::content-type", Gio.FileQueryInfoFlags.NONE, None)
        t = info.get_content_type()
        if t:
            return t
    except Exception:
        pass
    guessed, _ = Gio.content_type_guess(path, None)
    return guessed or "application/octet-stream"


def row(app, kind, default_id):
    icon = app.get_icon()
    name = ""
    if isinstance(icon, Gio.ThemedIcon):
        names = icon.get_names()
        name = names[0] if names else ""
    elif isinstance(icon, Gio.FileIcon):
        name = icon.get_file().get_path() or ""
    return {"id": app.get_id(), "name": app.get_display_name() or app.get_name(), "icon": name, "kind": kind,
            "default": app.get_id() == default_id}


def offer(ctype):
    """The type, its description, its default app's id and the apps to offer, in the order the menu shows them."""
    default = Gio.AppInfo.get_default_for_type(ctype, False)
    default_id = default.get_id() if default else ""
    seen, rows = {SELF}, []

    def add(app, kind):
        aid = app.get_id() if app else None
        if not aid or aid in seen or not app.should_show():
            return
        seen.add(aid)
        rows.append(row(app, kind, default_id))

    add(default, "type")
    for a in Gio.AppInfo.get_recommended_for_type(ctype):
        add(a, "type")
    by_name = lambda a: (a.get_display_name() or "").lower()
    for a in sorted(Gio.AppInfo.get_all_for_type(ctype), key=by_name):
        add(a, "type")
    everything = sorted(Gio.AppInfo.get_all(), key=by_name)
    # Editors register few types (VS Code none but its workspaces), so a text file offers them by their category too,
    # as Settings › Default apps does for its code and text kinds
    if Gio.content_type_is_a(ctype, "text/plain"):
        for a in everything:
            cats = (a.get_categories() or "").split(";") if hasattr(a, "get_categories") else []
            if "TextEditor" in cats or "IDE" in cats:
                add(a, "type")
    for a in everything:
        add(a, "other")
    return {"type": ctype, "description": Gio.content_type_get_description(ctype), "default": default_id, "apps": rows}


def open_with(app_id, files, make_default=False):
    app = DesktopAppInfo.new(app_id)
    if app is None:
        sys.exit(f"No app {app_id}")
    if make_default:
        app.set_as_default_for_type(content_type(files[0]))
    # gtk-launch takes the entry's full name: an id that itself ends in .desktop (org.telegram.desktop) is otherwise not
    # found (hypr/scripts/focus-app). The paths go as they are: it turns them into what the app's Exec asks for.
    os.execvp("gtk-launch", ["gtk-launch", app_id] + [os.path.abspath(f) for f in files])


def main(args):
    if len(args) >= 2 and args[0] == "list":
        print(json.dumps(offer(content_type(args[1]))))
    elif len(args) >= 3 and args[0] == "open":
        rest = args[2:]
        make_default = "--default" in rest
        files = [a for a in rest if a != "--default"]
        if not files:
            sys.exit(__doc__)
        open_with(args[1], files, make_default)
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main(sys.argv[1:])
