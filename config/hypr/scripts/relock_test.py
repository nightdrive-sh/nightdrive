"""Tests for hypr/scripts/relock and its place in hypridle.conf: the lock across a sleep (#3363).

relock runs against fakes on PATH: pgrep lists the lock pids from a file, hyprctl prints a devices file, logger and
setsid write down their arguments, and sleep returns at once. A lock is secure when its Quickshell log (under a fake
XDG_RUNTIME_DIR) has lock.qml's line. setsid stands in for `lock --replace`: it can leave the locks as they are, or
put a new secure one in place of the old, as the real one does once the new lock is secure.
"""
import json
import os
import re
import shutil
import subprocess
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(HERE, "relock")
HYPRIDLE = os.path.join(HERE, "..", "hypridle.conf")

FAKES = {
    "pgrep": '#!/bin/sh\n[ -s "$FAKE/locks" ] || exit 1\ncat "$FAKE/locks"\n',
    "hyprctl": '#!/bin/sh\n[ "$1" = devices ] && cat "$FAKE/devices.json"\n',
    "logger": '#!/bin/sh\nshift 2\necho "$*" >> "$FAKE/log"\n',
    "sleep": "#!/bin/sh\n",
    # Writes down that it ran and whether lid's note was there, then plays the new lock as $FAKE/swap says
    "setsid": r"""#!/bin/sh
echo "$*" >> "$FAKE/setsid"
[ -e "$XDG_RUNTIME_DIR/nightdrive-relock" ] && echo note >> "$FAKE/setsid"
case $(cat "$FAKE/swap" 2>/dev/null) in
  takes-over) echo 200 > "$FAKE/locks"; d="$XDG_RUNTIME_DIR/quickshell/by-pid/200"; mkdir -p "$d"
              echo "INFO qml: nightdrive-lock: secure" > "$d/log.log" ;;
  both-up) printf '100\n200\n' > "$FAKE/locks" ;;
esac
""",
}

KEYBOARD = {"address": "0xaaab45df3240", "name": "apple-mtp-keyboard"}
USB = {"address": "0xaaab4e000010", "name": "usb-keyboard"}


class RelockTest(unittest.TestCase):
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
                        XDG_RUNTIME_DIR=self.run_dir, HOME=self.dir)
        self.note = os.path.join(self.run_dir, "nightdrive-relock")
        self.keyboards([KEYBOARD])

    # The fake desktop
    def keyboards(self, kbs):
        with open(os.path.join(self.fake, "devices.json"), "w") as f:
            json.dump({"mice": [], "keyboards": kbs}, f)

    def lock(self, pid=100, secure=True):
        with open(os.path.join(self.fake, "locks"), "a") as f:
            f.write(f"{pid}\n")
        d = os.path.join(self.run_dir, "quickshell", "by-pid", str(pid))
        os.makedirs(d)
        with open(os.path.join(d, "log.log"), "w") as f:
            f.write("INFO: Configuration Loaded\n" + ("INFO qml: nightdrive-lock: secure\n" if secure else ""))

    def swap(self, how):
        with open(os.path.join(self.fake, "swap"), "w") as f:
            f.write(how)

    def relock(self, *args):
        subprocess.run([SCRIPT, *args], env=self.env, check=True, timeout=30)

    def read(self, name):
        try:
            with open(os.path.join(self.fake, name)) as f:
                return f.read()
        except FileNotFoundError:
            return ""

    # prepare (before the sleep)
    def test_prepare_notes_the_keyboards(self):
        self.keyboards([USB, KEYBOARD])
        self.relock("prepare")
        with open(self.note) as f:
            self.assertEqual(f.read().splitlines(), ["0xaaab45df3240 apple-mtp-keyboard", "0xaaab4e000010 usb-keyboard"])

    def test_prepare_leaves_a_note_when_hyprctl_has_nothing(self):
        os.remove(os.path.join(self.fake, "devices.json"))
        self.relock("prepare")
        self.assertTrue(os.path.exists(self.note))   # lid still waits; relock then replaces (any keyboard is new)

    # after the sleep: whether it replaces the lock
    def test_same_keyboards_and_a_secure_lock_stays(self):
        self.lock()
        self.relock("prepare")
        self.relock()
        self.assertEqual(self.read("setsid"), "")
        self.assertIn("the lock stays", self.read("log"))
        self.assertFalse(os.path.exists(self.note))

    def test_a_keyboard_gone_doesnt_matter(self):
        self.keyboards([KEYBOARD, {"address": "0xaaab46e166e0", "name": "airpods-avrcp"}])
        self.lock()
        self.relock("prepare")
        self.keyboards([KEYBOARD])
        self.relock()
        self.assertEqual(self.read("setsid"), "")

    def test_a_keyboard_added_again_replaces_it(self):
        self.lock()
        self.relock("prepare")
        self.keyboards([dict(KEYBOARD, address="0xaaab50000000")])   # the same keyboard as a new device
        self.swap("takes-over")
        self.relock()
        self.assertIn("lock --replace", self.read("setsid"))
        self.assertIn("keyboards added: apple-mtp-keyboard", self.read("log"))

    def test_a_lock_not_secure_is_replaced(self):
        self.lock(secure=False)
        self.relock("prepare")
        self.swap("takes-over")
        self.relock()
        self.assertIn("the lock isn't secure", self.read("log"))
        self.assertIn("lock --replace", self.read("setsid"))

    def test_without_the_note_it_is_replaced_as_before(self):
        self.lock()
        self.swap("takes-over")
        self.relock()
        self.assertIn("no note of the keyboards", self.read("log"))

    def test_two_locks_up_are_replaced(self):
        self.lock(100)
        self.lock(101)
        self.relock("prepare")
        self.swap("takes-over")
        self.relock()
        self.assertIn("2 locks up", self.read("log"))

    def test_no_lock_does_nothing_and_drops_the_note(self):
        self.relock("prepare")
        self.relock()
        self.assertEqual(self.read("setsid"), "")
        self.assertFalse(os.path.exists(self.note))

    # The order lid relies on: the note stays until the new lock has taken over
    def test_the_note_lasts_until_the_new_lock_has_taken_over(self):
        self.lock()
        self.relock("prepare")
        self.keyboards([USB])
        self.swap("takes-over")
        self.relock()
        self.assertEqual(self.read("setsid").splitlines()[1], "note")   # there while the new lock started
        self.assertFalse(os.path.exists(self.note))
        self.assertNotIn("hasn't taken over", self.read("log"))

    def test_the_old_lock_alone_is_not_taken_for_the_new_one(self):
        self.lock()
        self.relock("prepare")
        self.keyboards([USB])
        self.swap("nothing")   # the new lock never comes: the old one is still the only one, and secure
        self.relock()
        self.assertIn("hasn't taken over in 15 s", self.read("log"))
        self.assertFalse(os.path.exists(self.note))

    def test_both_locks_up_is_not_done(self):
        self.lock()
        self.relock("prepare")
        self.keyboards([USB])
        self.swap("both-up")
        self.relock()
        self.assertIn("hasn't taken over", self.read("log"))


class HypridleOrderTest(unittest.TestCase):
    """hypridle.conf: the sleep waits for the lock, relock prepare comes before the lock, relock after the sleep."""

    def setUp(self):
        with open(HYPRIDLE) as f:
            text = f.read()
        general = re.search(r"general\s*\{(.*?)\n\}", text, re.S).group(1)
        self.values = dict(re.findall(r"^\s*(\w+)\s*=\s*(.*?)\s*$", general, re.M))

    def steps(self, key):
        return [s.strip() for s in self.values[key].split(";")]

    def test_the_sleep_waits_for_the_lock(self):
        self.assertEqual(self.values.get("inhibit_sleep"), "3")

    def test_relock_prepare_comes_first_before_the_lock(self):
        steps = self.steps("before_sleep_cmd")
        self.assertEqual(steps[0], "~/.config/hypr/scripts/relock prepare")
        self.assertEqual(steps[-1], "loginctl lock-session")

    def test_relock_runs_after_the_sleep(self):
        self.assertIn("~/.config/hypr/scripts/relock", self.steps("after_sleep_cmd"))


if __name__ == "__main__":
    unittest.main()
