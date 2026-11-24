#!/usr/bin/env python3
"""Files as the desktop's Open and Save window: a backend of xdg-desktop-portal (org.freedesktop.impl.portal.FileChooser).

An app asks the portal (org.freedesktop.portal.FileChooser) for a file; the portal hands the request to the backend that
hyprland-portals.conf names for FileChooser, which is this one once `files picker on` has set it up (README.md › Open
and Save). Each request runs a picker of its own (pickrun.Picker: Files' window in its pick mode, a Quickshell process
apart from the Files windows the user has open), and its answer goes back to the app as file:// URIs.

Runs on the session bus as org.freedesktop.impl.portal.desktop.nightdrive, started by D-Bus activation when the portal
first needs it, and stays while requests come.
"""
import os
import sys

import gi
gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib  # noqa: E402

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pickrun  # noqa: E402

BUS_NAME = "org.freedesktop.impl.portal.desktop.nightdrive"
OBJECT_PATH = "/org/freedesktop/portal/desktop"
IDLE_EXIT_S = 300            # with no request open for this long, the backend ends; D-Bus starts it again on the next

# The portal's responses: the user picked, cancelled, or something else ended it
OK, CANCELLED, OTHER = 0, 1, 2

_ARGS = """<arg type="o" name="handle" direction="in"/><arg type="s" name="app_id" direction="in"/>
<arg type="s" name="parent_window" direction="in"/><arg type="s" name="title" direction="in"/>
<arg type="a{sv}" name="options" direction="in"/>
<arg type="u" name="response" direction="out"/><arg type="a{sv}" name="results" direction="out"/>"""
XML = f"""<node>
<interface name="org.freedesktop.impl.portal.FileChooser">
<method name="OpenFile">{_ARGS}</method><method name="SaveFile">{_ARGS}</method><method name="SaveFiles">{_ARGS}</method>
</interface>
<interface name="org.freedesktop.impl.portal.Request"><method name="Close"/></interface>
</node>"""
NODE = Gio.DBusNodeInfo.new_for_xml(XML)
CHOOSER, REQUEST = NODE.interfaces


def register(conn, path, iface, method_call):
    """An object on the bus; register_object is deprecated from PyGObject 3.52 on, which has the closures2 form."""
    reg = getattr(conn, "register_object_with_closures2", None) or conn.register_object
    return reg(path, iface, method_call, None, None)


def _path_bytes(value):
    """A folder or file the app gave as a byte string ending in a NUL (ay), as text; "" when none."""
    if not value:
        return ""
    raw = bytes(value).rstrip(b"\0")
    return os.fsdecode(raw)


def request_of(method, title, options):
    """What the picker needs to know from a portal call, as plain JSON for app/picker.qml."""
    o = options
    mode = {"OpenFile": "open", "SaveFile": "save", "SaveFiles": "saveFiles"}[method]
    req = {
        "mode": mode,
        "title": title or {"open": "Open", "save": "Save", "saveFiles": "Save"}[mode],
        "accept": o.get("accept_label", ""),
        "multiple": bool(o.get("multiple", False)) and mode == "open",
        "directory": bool(o.get("directory", False)) or mode == "saveFiles",
        "name": o.get("current_name", ""),
        "folder": _path_bytes(o.get("current_folder")),
        "file": _path_bytes(o.get("current_file")),
        # [(name, [(kind, pattern)])]: kind 0 a glob, 1 a MIME type
        "filters": [{"name": n, "rules": [[k, p] for k, p in rules]} for n, rules in o.get("filters", [])],
        "files": [_path_bytes(f) for f in o.get("files", [])],
    }
    cur = o.get("current_filter")
    if cur:
        req["filter"] = cur[0]
    # A file to save over (current_file) is its folder and name
    if req["file"] and mode == "save":
        req["folder"] = req["folder"] or os.path.dirname(req["file"])
        req["name"] = os.path.basename(req["file"])
    return req


def results_of(answer, req):
    """The portal's results from the picker's answer: the paths as file:// URIs, and the filter it had on."""
    paths = answer.get("paths", [])
    if req["mode"] == "saveFiles" and paths:
        folder = paths[0]
        paths = [os.path.join(folder, os.path.basename(f)) for f in req["files"]]
    # GLib's own, not Gio.File's get_uri: that starts gvfs's daemon for a plain path
    res = {"uris": GLib.Variant("as", [GLib.filename_to_uri(p, None) for p in paths])}
    i = answer.get("filter")
    if isinstance(i, int) and 0 <= i < len(req["filters"]):
        f = req["filters"][i]
        res["current_filter"] = GLib.Variant("(sa(us))", (f["name"], [(k, p) for k, p in f["rules"]]))
    return res


class Backend:
    def __init__(self, conn):
        self.conn = conn
        self.open = {}                # handle → (invocation, picker, registration id)
        self.idle = None
        register(conn, OBJECT_PATH, CHOOSER, self._call)
        self._arm_idle()

    def _arm_idle(self):
        if self.idle:
            GLib.source_remove(self.idle)
        self.idle = GLib.timeout_add_seconds(IDLE_EXIT_S, self._idle_exit)

    def _idle_exit(self):
        if self.open:
            return True
        loop.quit()
        return False

    def _call(self, conn, sender, path, iface, method, params, invocation):
        handle, app_id, parent, title, options = params.unpack()
        req = request_of(method, title, options)
        req["app"] = app_id
        reg = register(conn, handle, REQUEST, self._close)
        picker = pickrun.Picker(req, lambda answer: self._answer(handle, answer))
        self.open[handle] = (invocation, picker, reg, req)
        self._arm_idle()
        picker.start()

    def _close(self, conn, sender, path, iface, method, params, invocation):
        """The app or the portal gave up on the request (Request.Close): the picker goes, no answer."""
        invocation.return_value(None)
        entry = self.open.get(path)
        if entry:
            entry[1].stop()
            self._answer(path, None)

    def _answer(self, handle, answer):
        """The picker ended: answer is {"paths": […], "filter": i}, {"cancel": true}, or None when it failed."""
        entry = self.open.pop(handle, None)
        if not entry:
            return
        invocation, _picker, reg, req = entry
        self.conn.unregister_object(reg)
        if answer is None:
            out = (OTHER, {})
        elif answer.get("cancel") or not answer.get("paths"):
            out = (CANCELLED, {})
        else:
            out = (OK, results_of(answer, req))
        invocation.return_value(GLib.Variant("(ua{sv})", out))
        self._arm_idle()


def main():
    global loop
    loop = GLib.MainLoop()

    # The objects are there before the name is: the portal may call the moment it sees the name
    def connected(conn, _name):
        Backend(conn)

    def lost(_conn, _name):
        print(f"portal: {BUS_NAME} is taken, or the bus went away.", file=sys.stderr)
        loop.quit()

    Gio.bus_own_name(Gio.BusType.SESSION, BUS_NAME, Gio.BusNameOwnerFlags.NONE, connected, None, lost)
    loop.run()


if __name__ == "__main__":
    main()
