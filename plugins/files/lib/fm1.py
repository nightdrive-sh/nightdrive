#!/usr/bin/python3 -I
"""org.freedesktop.FileManager1 for Files: what other apps call to show a file in its folder (a browser's "Show in
folder", Recorder, Flatpak apps through the portal). The session bus starts this when one asks and no other file
manager holds the name: `files enable` puts its service file in ~/.local/share/dbus-1/services, which comes before
the system's (Nautilus's). Each call runs `files`, which opens the window or brings it forward. It quits after a while
without calls, and the bus starts it again on the next.

  ShowFolders(uris, startup_id)         each folder (Files shows the last)
  ShowItems(uris, startup_id)           the folder each is in, with it picked
  ShowItemProperties(uris, startup_id)  the same: Files has no properties window; its preview says what they are
"""
import os, subprocess, sys

import gi
gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib  # noqa: E402

NAME = "org.freedesktop.FileManager1"
PATH = "/org/freedesktop/FileManager1"
IDLE = 300                  # seconds without a call before it quits
FILES = os.path.expanduser("~/.local/bin/files")
XML = f"""<node><interface name="{NAME}">
  <method name="ShowFolders"><arg type="as" name="URIs" direction="in"/><arg type="s" name="StartupId" direction="in"/></method>
  <method name="ShowItems"><arg type="as" name="URIs" direction="in"/><arg type="s" name="StartupId" direction="in"/></method>
  <method name="ShowItemProperties"><arg type="as" name="URIs" direction="in"/><arg type="s" name="StartupId" direction="in"/></method>
</interface></node>"""

loop = GLib.MainLoop()
idle = [0]


def rearm():
    if idle[0]:
        GLib.source_remove(idle[0])
    idle[0] = GLib.timeout_add_seconds(IDLE, loop.quit)


def call(conn, sender, path, iface, method, params, invocation):
    uris = params.unpack()[0]
    rearm()
    # The last one asked for is the one left on show; a folder opens, an item shows in its folder
    for uri in uris[-1:]:
        verb = [] if method == "ShowFolders" else ["show"]
        env = dict(os.environ, XDG_ACTIVATION_TOKEN=params.unpack()[1]) if params.unpack()[1] else None
        subprocess.Popen([FILES, *verb, uri], env=env, stdin=subprocess.DEVNULL,
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
    invocation.return_value(None)


def acquired(conn, name):
    rearm()


def lost(conn, name):
    loop.quit()


def main():
    node = Gio.DBusNodeInfo.new_for_xml(XML)

    def on_bus(conn, name):
        conn.register_object(PATH, node.interfaces[0], call, None, None)

    Gio.bus_own_name(Gio.BusType.SESSION, NAME, Gio.BusNameOwnerFlags.ALLOW_REPLACEMENT, on_bus, acquired, lost)
    loop.run()


if __name__ == "__main__":
    sys.exit(main())
