#!/usr/bin/env python3
"""Files as the portal's Open and Save window (portal.py, pickrun.py): what a portal call's options become for the
picker (a folder and file as NUL-ended bytes, filters, SaveFiles' names), what its answer becomes for the app (file://
URIs, the filter it had on), where the window goes over the app that asked, and, on a D-Bus session of the test's own,
the whole round: SaveFile and OpenFile answered with the picker's paths, a cancel as response 1, and a picker that dies
without an answer or never comes up handed to GTK's backend, whose answer the app gets (2 when there is none), and with
`files picker off`'s flag every request GTK's at once. A
stand-in `qs` on PATH plays the picker and a stand-in GTK backend GTK's, so no window opens."""
import json, os, shutil, subprocess, sys, tempfile, textwrap, unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
try:
    import portal
    import pickrun
    HAVE_GI = True
except (ImportError, ValueError):
    HAVE_GI = False


def nul(p):
    return list(p.encode() + b"\0")


@unittest.skipUnless(HAVE_GI, "needs python3-gobject")
class Requests(unittest.TestCase):
    def test_save_options(self):
        req = portal.request_of("SaveFile", "Save Image", {
            "current_name": "cat.png", "current_folder": nul("/home/u/Pictures"), "accept_label": "_Save",
            "filters": [("PNG", [(0, "*.png")]), ("Images", [(1, "image/*")])], "current_filter": ("PNG", [(0, "*.png")])})
        self.assertEqual(req["mode"], "save")
        self.assertEqual((req["name"], req["folder"], req["accept"]), ("cat.png", "/home/u/Pictures", "_Save"))
        self.assertEqual((req["filters"][1]["name"], req["filters"][1]["rules"]), ("Images", [[1, "image/*"]]))
        self.assertEqual(req["filters"][0]["regex"], r"^(?:.*\.png)$")     # pickfilters_test.py has the rest
        self.assertEqual(req["filter"], "PNG")
        self.assertFalse(req["multiple"])

    def test_current_file_is_folder_and_name(self):
        req = portal.request_of("SaveFile", "", {"current_file": nul("/tmp/a b/notes.txt")})
        self.assertEqual((req["folder"], req["name"], req["title"]), ("/tmp/a b", "notes.txt", "Save"))

    def test_open_and_save_files(self):
        self.assertTrue(portal.request_of("OpenFile", "", {"multiple": True})["multiple"])
        self.assertFalse(portal.request_of("SaveFile", "", {"multiple": True})["multiple"])
        req = portal.request_of("SaveFiles", "", {"files": [nul("a.txt"), nul("b.txt")]})
        self.assertTrue(req["directory"])
        self.assertEqual(req["files"], ["a.txt", "b.txt"])

    def test_results(self):
        req = portal.request_of("SaveFile", "", {"filters": [("Text", [(0, "*.txt")])]})
        res = portal.results_of({"paths": ["/tmp/a b/ä.txt"], "filter": 0}, req)
        self.assertEqual(res["uris"].unpack(), ["file:///tmp/a%20b/%C3%A4.txt"])
        self.assertEqual(res["current_filter"].unpack(), ("Text", [(0, "*.txt")]))
        self.assertNotIn("current_filter", portal.results_of({"paths": ["/x"], "filter": 5}, req))

    def test_save_files_puts_each_name_in_the_folder(self):
        req = portal.request_of("SaveFiles", "", {"files": [nul("a.txt"), nul("b.txt")]})
        res = portal.results_of({"paths": ["/home/u/Out"]}, req)
        self.assertEqual(res["uris"].unpack(), ["file:///home/u/Out/a.txt", "file:///home/u/Out/b.txt"])


@unittest.skipUnless(HAVE_GI, "needs python3-gobject")
class Geometry(unittest.TestCase):
    def test_centred_over_the_app(self):
        self.assertEqual(pickrun.geometry((100, 50, 1600, 1000), (0, 0, 2560, 1440)), (400, 210, 1000, 680))

    def test_smaller_app_smaller_picker_never_under_min(self):
        self.assertEqual(pickrun.geometry((0, 0, 800, 600), None), (40, 40, 720, 520))
        self.assertEqual(pickrun.geometry((0, 0, 300, 200), None)[2:], pickrun.MIN)

    def test_no_app_the_screen(self):
        self.assertEqual(pickrun.geometry(None, (0, 40, 1920, 1040)), (460, 220, 1000, 680))


# The stand-in picker: answers as request.json's "app" says (what the test passed as app_id)
FAKE_QS = textwrap.dedent("""\
    #!/usr/bin/env python3
    import json, os, sys
    d = os.environ["FILES_PICK"]
    req = json.load(open(os.path.join(d, "request.json")))
    how = req["app"]
    if how == "die":
        sys.exit(1)
    if how == "hang":                 # never ready: the backend stops it after FILES_PICK_READY_S
        import time; time.sleep(60)
    answer = {"cancel": True} if how == "cancel" else {"paths": [os.path.join(req["folder"] or "/tmp", req["name"] or "x")]}
    json.dump(answer, open(os.path.join(d, "answer.json"), "w"))
""")


@unittest.skipUnless(HAVE_GI and shutil.which("dbus-run-session"), "needs dbus-run-session")
class RoundTrip(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        (self.tmp / "bin").mkdir()
        qs = self.tmp / "bin" / "qs"
        qs.write_text(FAKE_QS)
        qs.chmod(0o755)
        # A bus with no services to start: the system's would bring up the real GTK backend and its window
        (self.tmp / "services").mkdir()
        (self.tmp / "bus.conf").write_text(BUS_CONF.format(dir=self.tmp))

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def calls(self, *calls, gtk=False):
        """Each (method, app_id, options) called on the backend, on a bus of its own (with a stand-in for GTK's
        backend when gtk); their answers as text."""
        fake = f"{sys.executable} -c \"$FAKE_GTK\" & " if gtk else ""
        script = f"{fake}{sys.executable} {HERE / 'portal.py'} & {sys.executable} -c \"$CLIENT\"; kill $(jobs -p)"
        env = dict(os.environ, PATH=f"{self.tmp / 'bin'}:{os.environ['PATH']}", XDG_RUNTIME_DIR=str(self.tmp),
                   XDG_DATA_HOME=str(self.tmp / "data"),
                   CLIENT=CLIENT, FAKE_GTK=FAKE_GTK, CALLS=json.dumps(calls), GIO_USE_VFS="local",
                   FILES_PICK_READY_S="0.5")
        env.pop("HYPRLAND_INSTANCE_SIGNATURE", None)
        out = subprocess.run(["dbus-run-session", f"--config-file={self.tmp / 'bus.conf'}", "--", "bash", "-c", script], env=env, capture_output=True,
                             text=True, timeout=30, stdin=subprocess.DEVNULL)
        lines = [ln for ln in out.stdout.splitlines() if ln.startswith("(")]
        self.assertEqual(len(lines), len(calls), out.stderr[-2000:])
        return lines

    def test_answers(self):
        save, cancel, died = self.calls(
            ("SaveFile", "ok", {"current_name": "a b.txt", "current_folder": "/srv"}),
            ("OpenFile", "cancel", {}),
            ("SaveFile", "die", {}))
        self.assertIn("(0, {'uris': ['file:///srv/a%20b.txt']})", save)
        self.assertEqual(cancel, "(1, {})")
        self.assertEqual(died, "(2, {})")

    def test_gtk_takes_a_failed_picker(self):
        died, hung = self.calls(("SaveFile", "die", {"current_name": "x.txt"}), ("OpenFile", "hang", {}), gtk=True)
        self.assertEqual(died, "(0, {'uris': ['file:///gtk/SaveFile/x.txt']})")
        self.assertEqual(hung, "(0, {'uris': ['file:///gtk/OpenFile/']})")

    def test_off_hands_every_request_to_gtk(self):
        (self.tmp / "data" / "nightdrive").mkdir(parents=True)
        (self.tmp / "data" / "nightdrive" / "picker-off").touch()
        ok, = self.calls(("SaveFile", "ok", {"current_name": "y.txt", "current_folder": "/srv"}), gtk=True)
        self.assertEqual(ok, "(0, {'uris': ['file:///gtk/SaveFile/y.txt']})")


BUS_CONF = """<!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-Bus Bus Configuration 1.0//EN"
 "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
<busconfig><type>session</type><listen>unix:dir={dir}</listen><auth>EXTERNAL</auth><servicedir>{dir}/services</servicedir>
<policy context="default"><allow send_destination="*" eavesdrop="true"/><allow eavesdrop="true"/><allow own="*"/></policy>
</busconfig>"""


# GTK's backend as the test needs it: answers each call with a path that says what it was asked
FAKE_GTK = textwrap.dedent("""\
    from gi.repository import Gio, GLib
    XML = '<node><interface name="org.freedesktop.impl.portal.FileChooser">' + ''.join(
        f'<method name="{m}"><arg type="o" direction="in"/><arg type="s" direction="in"/><arg type="s" direction="in"/>'
        '<arg type="s" direction="in"/><arg type="a{sv}" direction="in"/><arg type="u" direction="out"/>'
        '<arg type="a{sv}" direction="out"/></method>' for m in ("OpenFile", "SaveFile")) + '</interface></node>'
    def call(conn, sender, path, iface, method, params, inv):
        name = params.unpack()[4].get("current_name", "")
        inv.return_value(GLib.Variant("(ua{sv})", (0, {"uris": GLib.Variant("as", [f"file:///gtk/{method}/{name}"])})))
    def got(conn, _name):
        conn.register_object_with_closures2("/org/freedesktop/portal/desktop",
                                            Gio.DBusNodeInfo.new_for_xml(XML).interfaces[0], call, None, None)
    Gio.bus_own_name(Gio.BusType.SESSION, "org.freedesktop.impl.portal.desktop.gtk", 0, got, None, None)
    GLib.MainLoop().run()
""")


# The app's side: Gio's own call with real variants (gdbus call garbles a byte string inside a variant)
CLIENT = textwrap.dedent("""\
    import json, os, time
    from gi.repository import Gio, GLib
    bus = Gio.bus_get_sync(Gio.BusType.SESSION)
    name, path = "org.freedesktop.impl.portal.desktop.nightdrive", "/org/freedesktop/portal/desktop"
    for _ in range(50):
        if bus.call_sync("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus", "NameHasOwner",
                         GLib.Variant("(s)", (name,)), None, 0, -1).unpack()[0]:
            break
        time.sleep(0.1)
    for n, (method, app, opts) in enumerate(json.loads(os.environ["CALLS"])):
        o = {k: GLib.Variant("ay", v.encode() + bytes(1)) if k == "current_folder" else GLib.Variant("s", v)
             for k, v in opts.items()}
        args = GLib.Variant("(osssa{sv})", (f"{path}/request/1_1/t{n}", app, "", "Title", o))
        print(bus.call_sync(name, path, "org.freedesktop.impl.portal.FileChooser", method, args, None, 0, 10000).unpack())
""")


if __name__ == "__main__":
    unittest.main()
