#!/usr/bin/env python3
"""Whether the login keyring is locked, for the sync's ExecCondition (`contacts keyring-locked`). The same as Mail's
lib/keyring.py: a plugin can't count on another one being installed.

    keyring.py    exit 0 if the login collection is locked, 1 if it is open or there is no keyring to ask

gnome-keyring registers a caller in an idle callback queued by each incoming message, and a property read that arrives
before that has run aborts the daemon (GLib's "invoke_get_property_in_idle_cb: assertion failed": its getter returns
nothing and no error). So `busctl get-property` straight away, a connection whose first message is that read, could
take the keyring down. Here one connection makes a method call first: once its reply is back, the caller is known and
the read is safe.
"""

import sys

import gi

gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib

BUS_NAME = "org.freedesktop.secrets"
SERVICE = "/org/freedesktop/secrets"
COLLECTION = "/org/freedesktop/secrets/collection/login"
TIMEOUT_MS = 5000


def call(bus, path, interface, method, args):
    return bus.call_sync(BUS_NAME, path, interface, method, args, None, Gio.DBusCallFlags.NO_AUTO_START, TIMEOUT_MS, None)


def is_locked():
    """True while the login collection is locked. False without a keyring or a login collection: nothing would prompt."""
    try:
        bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
        call(bus, SERVICE, "org.freedesktop.Secret.Service", "ReadAlias", GLib.Variant("(s)", ("default",)))
        reply = call(bus, COLLECTION, "org.freedesktop.DBus.Properties", "Get",
                     GLib.Variant("(ss)", ("org.freedesktop.Secret.Collection", "Locked")))
    except GLib.Error:
        return False
    return reply.unpack()[0]


if __name__ == "__main__":
    sys.exit(0 if is_locked() else 1)
