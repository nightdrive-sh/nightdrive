#!/usr/bin/python3 -I
"""The app that really opens a file's type, for Files (plugins/files/lib/launch.py) and no-app (xdg-open, GIO's apps).

  fitting_app.py check FILE      JSON: the file's type, its description, the app that fits (or null) and the app to
                                 install for it, where one is known (#3715)

GIO, and mimeopen behind xdg-open, take a type's app from its parents when the type has none of its own: an .xlsx is a
zip, so with no spreadsheet app it opened in Nautilus, which says it opens zip archives (as a folder); an .odt is
application/octet-stream underneath, whose app is Ferry's send window. An app fits only when it says it opens the type
itself, or a parent of it that isn't a container (an archive, or octet-stream, which every binary type is): a .zip
still opens in Nautilus, a .json in the text editor (text/plain), an .xlsx in nothing until a spreadsheet app is there.
The user's own choice for the type (Open with's Set as default, mimeapps.list) always fits.
"""
import json, os, sys

import gi
gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib

NO_APP = "nightdrive-no-app.desktop"     # hypr/scripts/no-app's hidden entry: the default it writes is no app at all
SELF = "nightdrive-files.desktop"        # Files opens folders, never a file
# The parents an app's claim doesn't carry over from: archives (what a file manager or an archiver opens as such) and
# octet-stream. A type that is one of these itself is still theirs: a .zip opens in Nautilus as before
CONTAINERS = {
    "application/octet-stream", "application/zip", "application/x-zip-compressed", "application/x-tar",
    "application/gzip", "application/x-gzip", "application/x-bzip", "application/x-bzip2", "application/bzip2",
    "application/x-xz", "application/x-lzma", "application/x-lzip", "application/zstd", "application/x-zstd",
    "application/x-7z-compressed", "application/vnd.rar", "application/x-rar", "application/x-rar-compressed",
    "application/x-cpio", "application/x-archive", "application/x-compress", "application/x-lha", "application/x-xar",
}
# What to install for a type no app opens: (words in the type, source, package, name). dnf packages from Fedora: the
# Software level and `nightdrive software install` take the same (dnf asks for the password in the system's dialog)
INSTALL = (
    (("spreadsheet", "ms-excel", "apple.numbers"), "dnf", "libreoffice-calc", "LibreOffice Calc"),
    (("wordprocessingml", "opendocument.text", "msword", "apple.pages", "application/rtf"), "dnf",
     "libreoffice-writer", "LibreOffice Writer"),
    (("presentationml", "opendocument.presentation", "ms-powerpoint", "apple.keynote"), "dnf",
     "libreoffice-impress", "LibreOffice Impress"),
    (("epub", "mobipocket", "fictionbook", "fb2", "comicbook"), "dnf", "foliate", "Foliate"),
)


def content_type(path):
    """The file's type as GIO sees it: by its content, its name for one that can't be read."""
    try:
        info = Gio.File.new_for_path(path).query_info("standard::content-type", Gio.FileQueryInfoFlags.NONE, None)
        if info.get_content_type():
            return info.get_content_type()
    except GLib.Error:
        pass
    guessed, _ = Gio.content_type_guess(path, None)
    return guessed or "application/octet-stream"


def chosen(ctype):
    """The app ids the user's mimeapps.list names for the type itself: its default and its added associations."""
    out = []
    for path in [os.path.join(GLib.get_user_config_dir(), "mimeapps.list")]:
        kf = GLib.KeyFile()
        try:
            kf.load_from_file(path, GLib.KeyFileFlags.NONE)
        except GLib.Error:
            continue
        for section in ("Default Applications", "Added Associations"):
            try:
                out += [a for a in kf.get_string_list(section, ctype) if a]
            except GLib.Error:
                pass
    return out


def fits(app, ctype, mine=()):
    """Whether APP opens CTYPE by its own claim: the type, or a parent of it that isn't a container."""
    aid = app.get_id() if app else None
    if not aid or aid in (NO_APP, SELF):
        return False
    if aid in mine:
        return True
    for t in app.get_supported_types() or []:
        if t == ctype or (t not in CONTAINERS and Gio.content_type_is_a(ctype, t)):
            return True
    return False


def fitting(ctype):
    """The app that opens CTYPE, or None: GIO's default when it fits, else the first app GIO offers that does."""
    mine = chosen(ctype)
    default = Gio.AppInfo.get_default_for_type(ctype, False)
    if fits(default, ctype, mine):
        return default
    for app in Gio.AppInfo.get_recommended_for_type(ctype) + Gio.AppInfo.get_all_for_type(ctype):
        if fits(app, ctype, mine):
            return app
    return None


def install_hint(ctype):
    """{"source", "id", "name"} of the app to install for CTYPE, or None when none is known."""
    for words, source, pkg, name in INSTALL:
        if any(w in ctype for w in words):
            return {"source": source, "id": pkg, "name": name}
    return None


def guarded_types():
    """The types no-app may stand in for: those under an archive (an .xlsx, an .epub) and those with an app to install
    (an .odt under octet-stream). Containers themselves, and the rest under octet-stream, are left to GIO."""
    out = []
    for t in Gio.content_types_get_registered():
        if t in CONTAINERS or "/" not in t:
            continue
        under_archive = any(Gio.content_type_is_a(t, c) for c in CONTAINERS if c != "application/octet-stream")
        if under_archive or install_hint(t):
            out.append(t)
    return sorted(out)


def check(path):
    ctype = content_type(path)
    app = fitting(ctype)
    return {"type": ctype, "description": Gio.content_type_get_description(ctype),
            "app": {"id": app.get_id(), "name": app.get_display_name()} if app else None,
            "install": None if app else install_hint(ctype)}


if __name__ == "__main__":
    if len(sys.argv) == 3 and sys.argv[1] == "check":
        print(json.dumps(check(sys.argv[2]), ensure_ascii=False))
    else:
        sys.exit(__doc__)
