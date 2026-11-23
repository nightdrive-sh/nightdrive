#!/usr/bin/env python3
"""Files' opening of a file (launch.py): what counts as a program (an ELF executable or PIE, an AppImage, a script with
#! and its x bit; not a library, a script without its x bit, a text), that open never runs one but says so, that a
file no app opens says that, and that run starts the program in its own folder and session (so it outlives Files),
makes it executable first only when asked, and in the terminal through the desktop's terminal script. Runs launch.py
in a throwaway home with no apps of its own (the system's MIME database linked in), and only programs it wrote."""
import json, os, subprocess, sys, tempfile, time, unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
LAUNCH = HERE / "launch.py"
sys.path.insert(0, str(HERE))
import launch  # noqa: E402

try:
    import gi
    gi.require_version("Gio", "2.0")
    from gi.repository import Gio  # noqa: F401
    HAVE_GIO = True
except (ImportError, ValueError):
    HAVE_GIO = False
MIME = Path("/usr/share/mime")


def elf(etype, interp, wide=True, appimage=False):
    """An ELF header (little-endian) with one program header: PT_INTERP when interp, else PT_LOAD."""
    if wide:
        head = bytearray(64)
        head[4], head[5] = 2, 1
        head[16:18] = etype.to_bytes(2, "little")
        head[32:40] = (64).to_bytes(8, "little")                 # e_phoff
        head[54:56] = (56).to_bytes(2, "little")                 # e_phentsize
        head[56:58] = (1).to_bytes(2, "little")                  # e_phnum
        ph = bytearray(56)
    else:
        head = bytearray(52)
        head[4], head[5] = 1, 1
        head[16:18] = etype.to_bytes(2, "little")
        head[28:32] = (52).to_bytes(4, "little")
        head[42:44] = (32).to_bytes(2, "little")
        head[44:46] = (1).to_bytes(2, "little")
        ph = bytearray(32)
    head[0:4] = b"\x7fELF"
    if appimage:
        head[8:11] = b"AI\x02"
    ph[0:4] = (3 if interp else 1).to_bytes(4, "little")
    return bytes(head + ph)


class Program(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.t = Path(self.tmp.name)

    def tearDown(self):
        self.tmp.cleanup()

    def write(self, name, data, mode=0o644):
        p = self.t / name
        p.write_bytes(data)
        p.chmod(mode)
        return str(p)

    def test_elf_programs(self):
        self.assertEqual(launch.program(self.write("game.arm64", elf(2, False), 0o755)), {"kind": "elf", "executable": True})
        self.assertEqual(launch.program(self.write("pie", elf(3, True), 0o755))["kind"], "elf")
        self.assertEqual(launch.program(self.write("old32", elf(2, False, wide=False), 0o755))["kind"], "elf")

    def test_elf_without_x_is_still_a_program(self):
        # A download loses its x bit: the window offers Make executable and run
        self.assertEqual(launch.program(self.write("game", elf(3, True))), {"kind": "elf", "executable": False})

    def test_appimage(self):
        self.assertEqual(launch.program(self.write("Tool.AppImage", elf(2, False), 0o755))["kind"], "appimage")
        self.assertEqual(launch.program(self.write("tool", elf(3, True, appimage=True)))["kind"], "appimage")

    def test_libraries_are_not(self):
        self.assertIsNone(launch.program(self.write("libx.so", elf(3, False), 0o755)))
        self.assertIsNone(launch.program(self.write("libc.so.6", elf(3, True), 0o755)))   # one with an interpreter
        self.assertIsNone(launch.program(self.write("plugin", elf(3, False), 0o755)))
        self.assertIsNone(launch.program(self.write("thing.o", elf(1, False))))

    def test_scripts_need_their_x_bit(self):
        self.assertEqual(launch.program(self.write("go.sh", b"#!/bin/sh\necho hi\n", 0o755)), {"kind": "script", "executable": True})
        self.assertIsNone(launch.program(self.write("read.sh", b"#!/bin/sh\necho hi\n")))

    def test_others_are_not(self):
        # An x bit alone (a USB stick's FAT gives every file one) doesn't make a program
        self.assertIsNone(launch.program(self.write("notes.txt", b"hello\n", 0o755)))
        self.assertIsNone(launch.program(self.write("empty", b"", 0o755)))
        self.assertIsNone(launch.program(str(self.t)))
        self.assertIsNone(launch.program(str(self.t / "missing")))


@unittest.skipUnless(HAVE_GIO and MIME.is_dir(), "needs GIO (python3-gobject) and shared-mime-info")
class OpenAndRun(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        t = self.t = Path(self.tmp.name)
        (t / "data/applications").mkdir(parents=True)
        (t / "data/mime").symlink_to(MIME)
        (t / ".config/hypr/scripts").mkdir(parents=True)
        (t / "bin").mkdir()
        (t / "config").mkdir()
        (t / "game").mkdir()
        # gio stand-in: what it was asked to open
        self.tool("bin/gio", f"printf '%s\\n' \"$@\" > {t}/opened")
        # The desktop's terminal script, standing in: its arguments, then the command itself
        self.tool(".config/hypr/scripts/terminal", f"printf '%s\\n' \"$@\" > {t}/terminal")
        # The program: where it ran, and whether its session is its own. The session id is field 6 of /proc/PID/stat,
        # read by the shell itself: CI's Fedora container has no ps (procps-ng), and an empty file never came (#3482)
        self.prog = self.tool("game/run.sh",
                              f"pwd > {t}/ran; read -r _ _ _ _ _ sid _ < /proc/$$/stat; echo $sid > {t}/sid")
        self.env = {"HOME": str(t), "XDG_DATA_HOME": str(t / "data"), "XDG_DATA_DIRS": str(t / "data"),
                    "XDG_CONFIG_HOME": str(t / "config"), "XDG_CONFIG_DIRS": str(t / "config"),
                    "PATH": f"{t}/bin:/usr/bin:/bin"}

    def tearDown(self):
        self.tmp.cleanup()

    def tool(self, rel, body):
        p = self.t / rel
        p.write_text(f"#!/bin/sh\n{body}\n")
        p.chmod(0o755)
        return str(p)

    def launch(self, *args):
        r = subprocess.run([sys.executable, "-I", str(LAUNCH), *args], env=self.env, capture_output=True, text=True)
        return r.returncode, r.stdout, r.stderr

    def wait_for(self, name):
        p = self.t / name
        for _ in range(100):
            if p.exists() and p.read_text():
                return p.read_text()
            time.sleep(0.05)
        self.fail(f"{name} never came")

    def test_open_never_runs_a_program(self):
        code, out, _ = self.launch("open", self.prog)
        self.assertEqual(code, 0)
        self.assertEqual(json.loads(out)["program"], {"kind": "script", "executable": True, "name": "run.sh", "path": self.prog})
        time.sleep(0.2)
        self.assertFalse((self.t / "ran").exists())
        self.assertFalse((self.t / "opened").exists())

    def test_open_with_no_app_says_so(self):
        f = self.t / "data.bin"
        f.write_bytes(b"\x00\x01\x02 nothing opens this")
        code, out, _ = self.launch("open", str(f))
        self.assertEqual(code, 0)
        self.assertEqual(json.loads(out)["noapp"]["name"], "data.bin")
        self.assertFalse((self.t / "opened").exists())

    def test_open_with_an_app_hands_it_to_gio(self):
        f = self.t / "notes.txt"
        f.write_text("hello\n")
        (self.t / "data/applications/pad.desktop").write_text(
            "[Desktop Entry]\nType=Application\nName=Pad\nExec=true %F\nMimeType=text/plain;\n")
        (self.t / "config/mimeapps.list").write_text("[Default Applications]\ntext/plain=pad.desktop\n")
        code, out, _ = self.launch("open", str(f))
        self.assertEqual((code, out), (0, ""))
        self.assertEqual(self.wait_for("opened").split(), ["open", str(f)])

    def test_run_in_its_folder_and_session(self):
        code, out, _ = self.launch("run", self.prog)
        self.assertEqual(code, 0)
        self.assertEqual(self.wait_for("ran").strip(), str(self.t / "game"))
        sid = int(self.wait_for("sid"))
        self.assertNotEqual(sid, os.getsid(0))        # a session of its own: Files closing doesn't end it

    def test_run_in_terminal(self):
        code, _, _ = self.launch("run", self.prog, "--terminal")
        self.assertEqual(code, 0)
        self.assertEqual(self.wait_for("terminal").split("\n")[:5], ["--dir", str(self.t / "game"), "--hold", "--", self.prog])

    def test_run_needs_x_unless_asked(self):
        p = self.t / "game/bin"
        p.write_bytes(elf(2, False))
        p.chmod(0o644)
        code, _, err = self.launch("run", str(p))
        self.assertEqual(code, 1)
        self.assertIn("isn't executable", err)
        self.assertEqual(p.stat().st_mode & 0o777, 0o644)
        # --chmod gives it its x bit; the made-up ELF can't run then, which comes back as the error
        code, _, err = self.launch("run", str(p), "--chmod")
        self.assertEqual(p.stat().st_mode & 0o777, 0o755)
        self.assertEqual(code, 1)
        self.assertTrue(err.startswith("bin: "), err)

    def test_run_refuses_what_isnt_a_program(self):
        f = self.t / "notes.txt"
        f.write_text("hello\n")
        code, _, err = self.launch("run", str(f), "--chmod")
        self.assertEqual(code, 1)
        self.assertIn("isn't a program", err)
        self.assertEqual(f.stat().st_mode & 0o111, 0)


if __name__ == "__main__":
    unittest.main()
