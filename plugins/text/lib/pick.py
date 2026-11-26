#!/usr/bin/env python3
"""The desktop's Open and Save window for Text (⌘O, ⌘N), through xdg-desktop-portal: Files' picker when the user has
turned it on (`files picker on`), else GTK's. Prints the paths picked, one a line; exit 1 when cancelled.

  pick.py open [FOLDER]            files to open (several)
  pick.py save NAME [FOLDER]       where a new file goes, NAME suggested
"""
import os
import secrets
import sys
from urllib.parse import unquote, urlparse

import gi
gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib  # noqa: E402

PORTAL = "org.freedesktop.portal.Desktop"
PATH = "/org/freedesktop/portal/desktop"
IFACE = "org.freedesktop.portal.FileChooser"
TIMEOUT_S = 3600            # the picker left open this long: given up


def folder_bytes(folder):
    # The portal takes the folder as a NUL-terminated byte string (ay)
    return GLib.Variant("ay", os.fsencode(folder) + b"\0")


def pick(mode, name="", folder=""):
    bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
    token = "text" + secrets.token_hex(6)
    sender = bus.get_unique_name()[1:].replace(".", "_")
    request = f"/org/freedesktop/portal/desktop/request/{sender}/{token}"
    loop, answer = GLib.MainLoop(), {}

    def on_response(_conn, _sender, _path, _iface, _signal, params):
        code, results = params.unpack()
        answer["code"], answer["uris"] = code, results.get("uris", [])
        loop.quit()

    # Subscribed before the call, so a quick answer isn't missed
    bus.signal_subscribe(PORTAL, "org.freedesktop.portal.Request", "Response", request, None,
                         Gio.DBusSignalFlags.NO_MATCH_RULE, on_response)
    opts = {"handle_token": GLib.Variant("s", token), "modal": GLib.Variant("b", True)}
    if folder and os.path.isdir(folder):
        opts["current_folder"] = folder_bytes(folder)
    if mode == "open":
        method, title = "OpenFile", "Open"
        opts["multiple"] = GLib.Variant("b", True)
    else:
        method, title = "SaveFile", "New file"
        opts["current_name"] = GLib.Variant("s", name or "Untitled.txt")
    bus.call_sync(PORTAL, PATH, IFACE, method, GLib.Variant("(ssa{sv})", ("", title, opts)),
                  None, Gio.DBusCallFlags.NONE, -1, None)
    GLib.timeout_add_seconds(TIMEOUT_S, loop.quit)
    loop.run()
    if answer.get("code") != 0:
        return []
    return [unquote(urlparse(u).path) for u in answer["uris"] if u.startswith("file://")]


def main(args):
    if not args or args[0] not in ("open", "save") or (args[0] == "save" and len(args) < 2):
        sys.exit(__doc__.strip())
    if args[0] == "open":
        paths = pick("open", folder=args[1] if len(args) > 1 else "")
    else:
        paths = pick("save", args[1], args[2] if len(args) > 2 else "")
    if not paths:
        sys.exit(1)
    print("\n".join(paths))


if __name__ == "__main__":
    main(sys.argv[1:])
