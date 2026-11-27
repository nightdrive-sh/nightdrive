#!/usr/bin/env python3
"""Network Drives' own ssh key: `python3 plugins/netdrive/lib/sshkey_test.py`. The key is made with a passphrase that
never reaches a command line, the drives' agent is started once and unlocks the key with what askpass gives, and a
drive with a key logs in with only that key from that agent (never 1Password's). The keyring is stood in for by a
secret-tool of the test's own (lib/askpass is the real one), and its lock by a check of the test's own (locked while
NETDRIVE_TEST_LOCKED is set), and the agent runs as a plain process in the test's own runtime folder: the user's own
agent and keyring are never touched. Needs ssh-keygen, ssh-agent and ssh-add."""
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent))
import drives  # noqa: E402
import mountcmd  # noqa: E402
import sshkey  # noqa: E402

TOOLS = all(shutil.which(t) for t in ("ssh-keygen", "ssh-agent", "ssh-add"))
PASS = "test-passphrase-not-a-secret"


@unittest.skipUnless(TOOLS, "needs ssh-keygen, ssh-agent and ssh-add (openssh-clients)")
class Key(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        home = Path(self.tmp.name).resolve()
        self.key = str(home / ".ssh" / "netdrive")
        tools = home / "bin"
        tools.mkdir()
        fake = tools / "secret-tool"          # the keyring: "lookup … key PATH" answers the test's passphrase
        fake.write_text('#!/bin/sh\n[ "$1" = lookup ] && [ "$5" = "$NETDRIVE_KEY" ] && printf "%s" "$NETDRIVE_TEST_PASS"\n')
        fake.chmod(0o700)
        check = tools / "keyring-locked"      # lib/keyring-locked: exit 0 while locked
        check.write_text('#!/bin/sh\n[ -n "$NETDRIVE_TEST_LOCKED" ]\n')
        check.chmod(0o700)
        env = {"HOME": str(home), "XDG_RUNTIME_DIR": str(home / "run"), "NETDRIVE_TEST_PASS": PASS,
               "PATH": f"{tools}:{os.environ.get('PATH', '/usr/bin:/bin')}"}
        self.patches = [mock.patch.dict(os.environ, env), mock.patch.object(sshkey, "SYSTEMD", False),
                        mock.patch.object(sshkey, "KEYRING_CHECK", str(check))]
        for p in self.patches:
            p.start()

    def tearDown(self):
        # The agent the test started (a plain process, by its socket in the test's folder)
        subprocess.run(["pkill", "-f", f"[s]sh-agent -D -a {mountcmd.agent_socket()}"], capture_output=True)
        while sshkey._detached:
            sshkey._detached.pop().wait(timeout=5)
        for p in reversed(self.patches):
            p.stop()
        self.tmp.cleanup()

    def make(self):
        os.makedirs(os.path.dirname(self.key), mode=0o700)
        sshkey.keygen(self.key, PASS)

    def test_key_has_the_passphrase(self):
        self.make()
        self.assertTrue(os.path.exists(self.key + ".pub"))
        self.assertIn(sshkey.COMMENT, Path(self.key + ".pub").read_text())
        no_pass = subprocess.run(["ssh-keygen", "-y", "-P", "", "-f", self.key], capture_output=True)
        self.assertNotEqual(no_pass.returncode, 0, "the key was made without a passphrase")
        right = subprocess.run(["ssh-keygen", "-y", "-P", PASS, "-f", self.key], capture_output=True)
        self.assertEqual(right.returncode, 0)

    def test_load_starts_the_agent_once_and_unlocks(self):
        self.make()
        sshkey.load(self.key)
        listed = subprocess.run(["ssh-add", "-l"], env=sshkey.env(self.key), capture_output=True, text=True).stdout
        self.assertIn(sshkey.fingerprint(self.key), listed)
        with mock.patch.object(sshkey, "start_agent", side_effect=AssertionError("started twice")):
            sshkey.load(self.key)             # the second drive: the agent is there and has the key

    def test_load_waits_for_the_keyring(self):
        self.make()
        told = []
        with mock.patch.object(sshkey, "keyring_locked", side_effect=[True, True, False]) as locked, \
                mock.patch.object(sshkey, "KEYRING_POLL", 0):
            sshkey.load(self.key, told.append)
        self.assertEqual(locked.call_count, 3)
        self.assertTrue(told[0].startswith("Waiting for the login keyring"))
        self.assertEqual(len([t for t in told if t.startswith("Waiting")]), 1, "said once, not on every look")
        listed = subprocess.run(["ssh-add", "-l"], env=sshkey.env(self.key), capture_output=True, text=True).stdout
        self.assertIn(sshkey.fingerprint(self.key), listed)

    def test_keyring_locked_reads_the_check(self):
        self.assertFalse(sshkey.keyring_locked())
        with mock.patch.dict(os.environ, {"NETDRIVE_TEST_LOCKED": "1"}):
            self.assertTrue(sshkey.keyring_locked())

    def test_wrong_passphrase_is_refused_without_looping(self):
        self.make()
        with mock.patch.dict(os.environ, {"NETDRIVE_TEST_PASS": "wrong"}), \
                mock.patch.object(sshkey, "UNLOCK_TIMEOUT", 5):
            with self.assertRaises(drives.Refused):
                sshkey.load(self.key)

    def test_askpass_answers_only_the_first_prompt(self):
        def ask(prompt):
            return subprocess.run([sshkey.ASKPASS, prompt], env=sshkey.env(self.key), capture_output=True, text=True)
        self.assertEqual(ask(f"Enter passphrase for {self.key}: ").stdout, PASS)
        self.assertNotEqual(ask(f"Bad passphrase, try again for {self.key}: ").returncode, 0)

    def test_askpass_never_asks_a_locked_keyring(self):
        """secret-tool at a locked keyring opens gnome-keyring's own prompt (#3728): askpass answers nothing then"""
        def ask(**extra):
            env = dict(sshkey.env(self.key), **extra)
            return subprocess.run([sshkey.ASKPASS, f"Enter passphrase for {self.key}: "], env=env,
                                  capture_output=True, text=True)
        locked = ask(NETDRIVE_TEST_LOCKED="1")
        self.assertNotEqual(locked.returncode, 0)
        self.assertEqual(locked.stdout, "")
        self.assertEqual(ask(NETDRIVE_KEYRING_CHECK="").stdout, "", "no check, no answer")

    def test_missing_key_is_refused(self):
        with self.assertRaises(drives.Refused):
            sshkey.load(self.key)


class Options(unittest.TestCase):
    def test_a_keyed_drive_uses_only_its_key_and_agent(self):
        with mock.patch.dict(os.environ, {"XDG_RUNTIME_DIR": "/run/user/1000"}):
            d = {"name": "Files", "ssh": "storage-files", "path": "~/Storage/Files", "key": "~/.ssh/netdrive"}
            flags = mountcmd.connection_flags(d)
            ssh = flags[flags.index("--sftp-ssh") + 1]
            self.assertIn(f"-i {os.path.expanduser('~/.ssh/netdrive')}", ssh)
            self.assertIn("IdentitiesOnly=yes", ssh)
            self.assertIn("IdentityAgent=/run/user/1000/netdrive/agent.sock", ssh)
            plain = mountcmd.connection_flags({**d, "key": ""})
            self.assertNotIn("IdentityAgent", plain[plain.index("--sftp-ssh") + 1])


if __name__ == "__main__":
    unittest.main()
