"""GTK's Open and Save window in place of Files' when Files' picker fails (portal.py): the same request, handed to
xdg-desktop-portal-gtk's FileChooser as it came, and its answer given back to the app as it is.

So an app's Save never hangs on Files: a picker that doesn't come up in time or dies before it answers, and the user
sees GTK's window instead (with the app's own title, folder, name and filters). A Request.Close that comes meanwhile
goes on to GTK's request too. Without xdg-desktop-portal-gtk the request ends as failed, as it did before.
"""
from gi.repository import Gio, GLib

GTK_NAME = "org.freedesktop.impl.portal.desktop.gtk"
OBJECT_PATH = "/org/freedesktop/portal/desktop"
CHOOSER = "org.freedesktop.impl.portal.FileChooser"
REQUEST = "org.freedesktop.impl.portal.Request"
OTHER = 2
NO_TIMEOUT = GLib.MAXINT      # the user may take as long as they like in GTK's window


def forward(conn, method, params, done):
    """Ask GTK's backend for the same thing; done((response, results)) once it answers, or (2, {}) when it can't."""
    def answered(c, result):
        try:
            done(c.call_finish(result))
        except GLib.Error as e:
            print(f"portal: GTK's file chooser didn't answer either: {e.message}", flush=True)
            done(GLib.Variant("(ua{sv})", (OTHER, {})))

    conn.call(GTK_NAME, OBJECT_PATH, CHOOSER, method, params, GLib.VariantType("(ua{sv})"),
              Gio.DBusCallFlags.NONE, NO_TIMEOUT, None, answered)


def close(conn, handle):
    """The app gave up while GTK's window was up: GTK's request at the same handle closes it."""
    conn.call(GTK_NAME, handle, REQUEST, "Close", None, None, Gio.DBusCallFlags.NONE, -1, None, None)
