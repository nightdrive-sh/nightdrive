#!/usr/bin/env python3
"""The `files` command's opening (bin/files, #3427): every open is a new window on the workspace the user is on, never
the one Files has open elsewhere brought forward. While Files runs: `files` asks its IPC for a new window home, `files
DIR` for one on DIR, `files FILE` and `files show FILE` for one on FILE's folder with FILE picked, and nothing goes to
the kit's focus (hyprctl). Not running: Quickshell starts (its first window is the new one), and a folder or file then
goes into that window. Runs bin/files against a fake qs, setsid and hyprctl that only log what they were asked."""
import os, subprocess, tempfile, unittest
from pathlib import Path

FILES = Path(__file__).resolve().parent.parent / "bin" / "files"

# qs: `list` says a process runs when RUNNING is set, `ipc show` lists the files target, `ipc call` is logged
FAKE_QS = """#!/bin/bash
echo "qs $*" >> "$LOG"
case "$1 $2" in
  "list -p") [[ -n ${RUNNING:-} ]] && echo "  Process ID: 4242" ;;
  "ipc -p") [[ $4 == show ]] && echo "target files" ;;
esac
exit 0
"""
FAKE_LOGGER = """#!/bin/bash
echo "$(basename "$0") $*" >> "$LOG"
"""


class FilesOpenTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        root = Path(self.tmp.name)
        self.bin, self.home, self.log = root / "bin", root / "home", root / "log"
        self.bin.mkdir()
        (self.home / "Docs").mkdir(parents=True)
        (self.home / "Docs" / "a.txt").write_text("a")
        for name, body in (("qs", FAKE_QS), ("setsid", FAKE_LOGGER), ("hyprctl", FAKE_LOGGER)):
            (self.bin / name).write_text(body)
            (self.bin / name).chmod(0o755)
        self.log.touch()

    def tearDown(self):
        self.tmp.cleanup()

    def run_files(self, *args, running=True):
        env = {"PATH": f"{self.bin}:/usr/bin:/bin", "HOME": str(self.home), "LOG": str(self.log)}
        if running:
            env["RUNNING"] = "1"
        r = subprocess.run(["bash", str(FILES), *args], env=env, capture_output=True, text=True, timeout=20)
        self.assertEqual(r.returncode, 0, r.stderr)
        lines = self.log.read_text().splitlines()
        self.log.write_text("")
        return [l for l in lines if " list " not in l and not l.endswith(" show")]   # the probes, not the acts

    def calls(self, lines):
        return [l.split(" call files ", 1)[1] for l in lines if " call files " in l]

    def test_running_open_is_a_new_window_home(self):
        for args in ((), ("open",)):
            lines = self.run_files(*args)
            self.assertEqual(self.calls(lines), [f"newWindow {self.home}"])
            self.assertFalse([l for l in lines if l.startswith(("hyprctl", "setsid"))], lines)

    def test_running_folder_is_a_new_window_there(self):
        docs = self.home / "Docs"
        self.assertEqual(self.calls(self.run_files(str(docs))), [f"newWindow {docs}"])
        self.assertEqual(self.calls(self.run_files("open", f"file://{docs}")), [f"newWindow {docs}"])

    def test_running_file_is_a_new_window_with_it_picked(self):
        f = self.home / "Docs" / "a.txt"
        self.assertEqual(self.calls(self.run_files("show", str(f))), [f"newWindowShowing {f}"])
        self.assertEqual(self.calls(self.run_files(str(f))), [f"newWindowShowing {f}"])

    def test_not_running_starts_and_fills_the_first_window(self):
        lines = self.run_files(running=False)
        self.assertTrue(any(l.startswith("setsid -f qs -p") for l in lines), lines)
        self.assertEqual(self.calls(lines), [])        # home: the first window is already there
        docs = self.home / "Docs"
        lines = self.run_files(str(docs), running=False)
        self.assertEqual(self.calls(lines), [f"openFolder {docs}"])
        f = docs / "a.txt"
        self.assertEqual(self.calls(self.run_files(str(f), running=False)), [f"showFile {f}"])

    def test_missing_path_fails_without_a_window(self):
        env = {"PATH": f"{self.bin}:/usr/bin:/bin", "HOME": str(self.home), "LOG": str(self.log), "RUNNING": "1"}
        r = subprocess.run(["bash", str(FILES), str(self.home / "nope")], env=env, capture_output=True, text=True)
        self.assertEqual(r.returncode, 1)
        self.assertIn("isn't there", r.stderr)
        self.assertEqual(self.calls(self.log.read_text().splitlines()), [])


if __name__ == "__main__":
    unittest.main()
