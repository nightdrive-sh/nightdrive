"""Tests for hypr/scripts/lid's guard: a lid change waits while the lock is being replaced or a relock is due (#2342,
#3363), and a note relock left behind holds it back only once.

The script is sourced in bash for its functions (it returns before its commands when sourced), with fakes on PATH:
pgrep lists the lock pids from a file, logger writes down its message and sleep returns at once.
"""
import os
import shutil
import subprocess
import tempfile
import unittest

SCRIPT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "lid")

FAKES = {
    "pgrep": '#!/bin/sh\n[ -s "$FAKE/locks" ] || exit 1\ncat "$FAKE/locks"\n',
    "logger": '#!/bin/sh\nshift 2\necho "$*" >> "$FAKE/log"\n',
    "sleep": "#!/bin/sh\n",
}


class LidGuardTest(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.dir)
        self.fake = os.path.join(self.dir, "fake")
        self.run_dir = os.path.join(self.dir, "run")
        bindir = os.path.join(self.dir, "bin")
        for d in (self.fake, self.run_dir, bindir):
            os.mkdir(d)
        for name, body in FAKES.items():
            path = os.path.join(bindir, name)
            with open(path, "w") as f:
                f.write(body)
            os.chmod(path, 0o755)
        self.env = dict(os.environ, PATH=bindir + ":" + os.environ.get("PATH", "/usr/bin:/bin"), FAKE=self.fake,
                        XDG_RUNTIME_DIR=self.run_dir)
        self.note = os.path.join(self.run_dir, "nightdrive-relock")

    def lock(self, pid, secure=True):
        with open(os.path.join(self.fake, "locks"), "a") as f:
            f.write(f"{pid}\n")
        d = os.path.join(self.run_dir, "quickshell", "by-pid", str(pid))
        os.makedirs(d)
        with open(os.path.join(d, "log.log"), "w") as f:
            f.write("INFO qml: nightdrive-lock: secure\n" if secure else "INFO: Configuration Loaded\n")

    def relock_due(self):
        with open(self.note, "w") as f:
            f.write("0xaaab45df3240 apple-mtp-keyboard\n")

    def call(self, fn):
        """fn's exit status, with the script sourced"""
        return subprocess.run(["bash", "-c", f'source "{SCRIPT}" && {fn}'], env=self.env, timeout=30).returncode

    def log(self):
        try:
            with open(os.path.join(self.fake, "log")) as f:
                return f.read()
        except FileNotFoundError:
            return ""

    def test_sourcing_runs_nothing(self):
        self.assertEqual(self.call("true"), 0)
        self.assertEqual(self.log(), "")

    def test_no_lock_is_settled(self):
        self.assertEqual(self.call("settled"), 0)

    def test_one_secure_lock_is_settled(self):
        self.lock(100)
        self.assertEqual(self.call("settled"), 0)

    def test_a_lock_not_yet_secure_is_not(self):
        self.lock(100, secure=False)
        self.assertNotEqual(self.call("settled"), 0)

    def test_two_locks_are_not(self):
        self.lock(100)
        self.lock(200)
        self.assertNotEqual(self.call("settled"), 0)

    def test_a_relock_due_is_not_even_with_a_secure_lock(self):
        # The case of #3363: after a resume the old lock is the only one and secure, but relock may replace it
        self.lock(100)
        self.relock_due()
        self.assertNotEqual(self.call("settled"), 0)

    def test_waiting_ends_when_relock_is_done(self):
        self.lock(100)
        self.assertEqual(self.call("wait_settled"), 0)
        self.assertEqual(self.log(), "")

    def test_a_stale_note_holds_it_back_once(self):
        self.lock(100)
        self.relock_due()
        self.call("wait_settled")
        self.assertIn("didn't settle in 15 s", self.log())
        self.assertIn("removed relock's stale note", self.log())
        self.assertFalse(os.path.exists(self.note))
        self.assertEqual(self.call("settled"), 0)


if __name__ == "__main__":
    unittest.main()
