#!/usr/bin/env python3
"""Garage's clipboard into a VM (guestclip.py, #3117): which of the host clipboard's types is taken and what is refused
(a password manager's, no text, too long), which way the guest agent allows (guest-exec, else a file in /run), what each
way sends and how a failure reads, and the whole command against a fake guest agent on a real socket: the file way, the
exec way, and --if-changed sending the same text only once per qemu."""
import base64, importlib.util, json, os, socket, subprocess, sys, tempfile, threading, unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
SCRIPT = HERE / "guestclip.py"
spec = importlib.util.spec_from_file_location("guestclip", SCRIPT)
gc = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gc)


def info(*enabled, disabled=()):
    return {"supported_commands": [{"name": n, "enabled": True} for n in enabled]
            + [{"name": n, "enabled": False} for n in disabled]}


EXEC = ("guest-exec", "guest-exec-status")
FILE = ("guest-file-open", "guest-file-write", "guest-file-close")


class Types(unittest.TestCase):
    def test_utf8_text_first(self):
        self.assertEqual(gc.pick_type(["image/png", "text/plain", "text/plain;charset=utf-8"]), "text/plain;charset=utf-8")
        self.assertEqual(gc.pick_type(["UTF8_STRING", "TEXT"]), "UTF8_STRING")

    def test_password_manager_secret_refused(self):
        with self.assertRaisesRegex(gc.Refused, "password"):
            gc.pick_type(["text/plain", gc.SECRET_HINT])

    def test_no_text(self):
        with self.assertRaisesRegex(gc.Refused, "no text"):
            gc.pick_type(["image/png"])

    def test_check(self):
        gc.check(b"hello")
        gc.check("ääkköset".encode())
        for bad, why in ((b"", "no text"), (b"x" * (gc.MAX_BYTES + 1), "KB"), (b"\xff\xfe\x00", "no text")):
            with self.assertRaisesRegex(gc.Refused, why):
                gc.check(bad)


class Route(unittest.TestCase):
    def test_exec_when_allowed(self):
        self.assertEqual(gc.route("vm", gc.enabled_commands(info(*EXEC, *FILE))), "exec")

    def test_file_when_exec_blocked(self):
        # Fedora's qemu-ga: guest-exec listed, but disabled
        self.assertEqual(gc.route("vm", gc.enabled_commands(info(*FILE, disabled=EXEC))), "file")

    def test_neither(self):
        with self.assertRaisesRegex(gc.Refused, "vm's guest agent allows neither"):
            gc.route("vm", gc.enabled_commands(info(disabled=EXEC + FILE)))

    def test_exec_failures_read(self):
        self.assertIn("wl-clipboard", gc.exec_failure("vm", {"exitcode": gc.NO_WL_COPY}))
        self.assertIn("logged in", gc.exec_failure("vm", {"exitcode": gc.NO_DESKTOP}))
        err = base64.b64encode(b"runuser: oops\n").decode()
        self.assertEqual(gc.exec_failure("vm", {"exitcode": 1, "err-data": err}),
                         "vm didn't take the clipboard (exit 1: runuser: oops)")


class FakeAgent(threading.Thread):
    """qemu-ga's side of qga.sock, for one connection: answers guest-sync, guest-info (with `allowed`), the file and exec
    commands, and keeps what came, so a test can look"""
    def __init__(self, path, allowed, exitcode=0):
        super().__init__(daemon=True)
        self.srv = socket.socket(socket.AF_UNIX)
        self.srv.bind(path)
        self.srv.listen(4)
        self.allowed, self.exitcode = allowed, exitcode
        self.calls, self.written, self.stdin = [], b"", None

    def run(self):
        while True:
            try:
                conn, _ = self.srv.accept()
            except OSError:
                return
            f = conn.makefile("rw")
            for line in f:
                msg = json.loads(line)
                cmd, args = msg["execute"], msg.get("arguments", {})
                self.calls.append(cmd)
                ret = {}
                if cmd == "guest-sync":
                    ret = args["id"]
                elif cmd == "guest-info":
                    ret = info(*self.allowed)
                elif cmd == "guest-file-open":
                    self.path, ret = args["path"], 7
                elif cmd == "guest-file-write":
                    self.written += base64.b64decode(args["buf-b64"])
                elif cmd == "guest-exec":
                    self.stdin, self.argv, ret = base64.b64decode(args["input-data"]), args["arg"], {"pid": 42}
                elif cmd == "guest-exec-status":
                    ret = {"exited": True, "exitcode": self.exitcode}
                f.write(json.dumps({"return": ret}) + "\n")
                f.flush()
            conn.close()


class Command(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = Path(self.tmp.name)
        self.sent = self.dir / "clip" / "vm"

    def tearDown(self):
        self.tmp.cleanup()

    def agent(self, allowed, exitcode=0):
        a = FakeAgent(str(self.dir / "qga.sock"), allowed, exitcode)
        a.start()
        self.addCleanup(a.srv.close)
        return a

    def run_clip(self, text, *args):
        return subprocess.run([sys.executable, "-I", str(SCRIPT), "qga.sock", "vm", *args], cwd=self.dir,
                              input=text, capture_output=True, timeout=20)

    def test_file_way(self):
        a = self.agent(FILE)
        r = self.run_clip("hei\nmaailma".encode())
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(r.stdout.strip(), b"file")
        self.assertEqual(a.path, gc.CLIP_FILE)
        header, text = a.written.split(b"\n", 1)
        self.assertTrue(header.startswith(gc.CLIP_HEADER + b" "))
        self.assertEqual(text, "hei\nmaailma".encode())
        self.assertIn("guest-file-close", a.calls)

    def test_exec_way(self):
        a = self.agent(EXEC + FILE)
        r = self.run_clip(b"text")
        self.assertEqual(r.stdout.strip(), b"exec", r.stderr)
        self.assertEqual(a.stdin, b"text")
        self.assertEqual(a.argv[0], "-c")
        self.assertNotIn("guest-file-open", a.calls)

    def test_exec_failure_is_said(self):
        self.agent(EXEC, exitcode=gc.NO_WL_COPY)
        r = self.run_clip(b"text")
        self.assertEqual(r.returncode, 1)
        self.assertIn(b"wl-clipboard", r.stderr)

    def test_same_text_once_per_qemu(self):
        a = self.agent(FILE)
        args = ("--sent", str(self.sent), "100", "--if-changed")
        self.assertEqual(self.run_clip(b"one", *args).stdout.strip(), b"file")
        self.assertEqual(self.run_clip(b"one", *args).stdout.strip(), b"same")
        self.assertEqual(a.calls.count("guest-file-write"), 1)
        # What is remembered is a hash, never the text
        self.assertNotIn("one", self.sent.read_text())
        # Another text, or the VM started again (a new pid), goes
        self.assertEqual(self.run_clip(b"two", *args).stdout.strip(), b"file")
        self.assertEqual(self.run_clip(b"two", "--sent", str(self.sent), "101", "--if-changed").stdout.strip(), b"file")
        # By hand it always goes
        self.assertEqual(self.run_clip(b"two", "--sent", str(self.sent), "101").stdout.strip(), b"file")

    def test_no_agent(self):
        # The socket is there (qemu holds it) but nothing answers
        srv = socket.socket(socket.AF_UNIX)
        srv.bind(str(self.dir / "qga.sock"))
        srv.listen(1)
        self.addCleanup(srv.close)
        r = self.run_clip(b"text")
        self.assertEqual(r.returncode, 3)


if __name__ == "__main__":
    unittest.main()
