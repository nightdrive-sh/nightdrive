"""Network Drives' test mount, for offline_test.py and upload_test.py: `rclone serve sftp` on 127.0.0.1 with a key made
for the test, and the drive mounted through a relay here, with the drive's own ssh options (mountcmd.ssh_command) and
its own rclone flags (mountcmd.argv). The relay can go dark: it keeps the connections open and drops every byte, as a
Wi-Fi with no internet behind it does (the hard case: nothing says the link is gone), or refuse connections, as a
computer with no network at all. The user's own network is never touched.
Needs rclone, fusermount3, ssh and a usable /dev/fuse; each missing one skips the tests with the reason.
NETDRIVE_TEST_LOG=DEBUG logs every call rclone gets, NETDRIVE_TEST_KEEP=1 keeps the test's folder and its rclone.log.
"""
import os
import shutil
import socket
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import mountcmd  # noqa: E402

# The longest a call may take once the server is gone: ssh notices a dead link after ALIVE_INTERVAL * ALIVE_COUNT
# (up to one interval more), then one try to connect again (CONNECT_TIMEOUT), and a few seconds' slack for rclone
LIMIT = mountcmd.ALIVE_INTERVAL * (mountcmd.ALIVE_COUNT + 1) + mountcmd.CONNECT_TIMEOUT + 5
# Opening a file not in the cache yet: rclone's cache tries the download 10 times, and its sftp pacer sleeps between
# tries, up to 2 s and longer while a failing upload shares it (neither has a flag; lib/ssh-breaker already takes the
# network's own wait out of all but the first try). Measured 23-42 s.
READ_LIMIT = LIMIT + 10 * 3
DIR_CACHE = "3s"   # the test's listing cache, so an expired listing can be tried without waiting the real minute


def fuse_usable():
    return os.access("/dev/fuse", os.R_OK | os.W_OK) and shutil.which("fusermount3")


def free_port():
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


class Relay:
    """127.0.0.1:port → target. dark(): connections stay open but nothing gets through, new ones are taken and left
    silent. refuse(): no one listens."""

    def __init__(self, target):
        self.target, self.port, self.is_dark = target, free_port(), False
        self.listener = socket.create_server(("127.0.0.1", self.port))
        self.socks = []
        threading.Thread(target=self.accept, daemon=True).start()

    def accept(self):
        while True:
            try:
                c, _ = self.listener.accept()
            except OSError:
                return
            self.socks.append(c)
            if self.is_dark:
                continue
            s = socket.create_connection(self.target)
            self.socks.append(s)
            threading.Thread(target=self.pipe, args=(c, s), daemon=True).start()
            threading.Thread(target=self.pipe, args=(s, c), daemon=True).start()

    def pipe(self, a, b):
        while True:
            try:
                data = a.recv(65536)
            except OSError:
                return
            if not data:
                return
            if not self.is_dark:
                try:
                    b.sendall(data)
                except OSError:
                    return

    def dark(self):
        self.is_dark = True

    def refuse(self):
        """shutdown wakes the accept in the other thread; a close alone would leave it listening"""
        try:
            self.listener.shutdown(socket.SHUT_RDWR)
        except OSError:
            pass
        self.listener.close()

    def cut(self):
        """Every open link goes, as with Wi-Fi off (shutdown first: a close alone leaves a recv in another thread holding
        the socket open)"""
        for s in self.socks:
            try:
                s.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
            s.close()

    def close(self):
        self.refuse()
        self.cut()


def timed(cmd, cap):
    """(seconds, exit status) of a shell command, stopped at cap (None as the status then: it hung)"""
    start = time.monotonic()
    try:
        r = subprocess.run(cmd, shell=True, capture_output=True, timeout=cap)
        return time.monotonic() - start, r.returncode
    except subprocess.TimeoutExpired:
        return time.monotonic() - start, None


# The tests' classes take these (a decorator on this base would skip it, not them)
NEEDS = unittest.skipUnless(shutil.which("rclone") and shutil.which("ssh") and shutil.which("ssh-keygen"),
                            "needs rclone and ssh")
NEEDS_FUSE = unittest.skipUnless(fuse_usable(), "needs /dev/fuse and fusermount3 (no FUSE in this container)")


class Mounted(unittest.TestCase):
    """A drive mounted for each test (setUp), and the calls and checks the tests share"""

    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix="netdrive-test-"))
        self.served = self.tmp / "served"
        self.served.mkdir()
        (self.served / "seen.txt").write_text("listed but never opened\n")
        (self.served / "folder").mkdir()
        (self.served / "folder" / "inside.txt").write_text("x\n")
        key = self.tmp / "key"
        subprocess.run(["ssh-keygen", "-q", "-t", "ed25519", "-N", "", "-f", str(key)], check=True)
        port = free_port()
        self.server = subprocess.Popen(
            ["rclone", "serve", "sftp", str(self.served), "--addr", f"127.0.0.1:{port}", "--config", "/dev/null",
             "--authorized-keys", f"{key}.pub", "--user", "test"],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        self.wait(lambda: self.listening(port), 15, "rclone serve sftp didn't start")
        self.relay = Relay(("127.0.0.1", port))
        ssh = mountcmd.ssh_command("test@127.0.0.1", extra=[
            "-F", "/dev/null", "-i", str(key), "-p", str(self.relay.port), "-o", "IdentitiesOnly=yes",
            "-o", "IdentityAgent=none", "-o", "StrictHostKeyChecking=no", "-o", "UserKnownHostsFile=/dev/null",
            "-o", "LogLevel=ERROR"])
        self.mnt = self.tmp / "mnt"
        self.mnt.mkdir()
        os.environ["XDG_RUNTIME_DIR"] = str(self.tmp)
        os.environ["XDG_CACHE_HOME"] = str(self.tmp / "cache")
        os.makedirs(mountcmd.runtime_dir())
        drive = {"name": "Test", "ssh": "unused", "path": str(self.mnt)}
        cmd = mountcmd.argv(drive, ssh=ssh)
        cmd[cmd.index("--dir-cache-time") + 1] = DIR_CACHE
        # A queued upload, as the drives have: with 0 s a file is uploaded as it closes, and a failure is never tried again
        cmd[cmd.index("--vfs-write-back") + 1] = "1s"
        cmd[cmd.index("--log-level") + 1] = os.environ.get("NETDRIVE_TEST_LOG", "INFO")   # DEBUG to see each call
        self.log = open(self.tmp / "rclone.log", "w")
        self.mount = subprocess.Popen(cmd + ["--config", "/dev/null"], stdout=self.log, stderr=self.log)
        self.wait(lambda: self.mounted(), 20, "the drive didn't mount")

    def tearDown(self):
        self.mount.terminate()
        try:
            self.mount.wait(15)
        except subprocess.TimeoutExpired:
            self.mount.kill()
        subprocess.run(["fusermount3", "-uz", str(self.mnt)], capture_output=True)
        self.relay.close()
        self.server.terminate()
        self.server.wait(10)
        self.log.close()
        if os.environ.get("NETDRIVE_TEST_KEEP"):
            print(f"kept {self.tmp}", file=sys.stderr)
        else:
            shutil.rmtree(self.tmp, ignore_errors=True)

    def wait(self, ok, seconds, why):
        end = time.monotonic() + seconds
        while time.monotonic() < end:
            if ok():
                return
            time.sleep(0.2)
        self.fail(why + ":\n" + (self.tmp / "rclone.log").read_text() if (self.tmp / "rclone.log").exists() else why)

    def listening(self, port):
        try:
            socket.create_connection(("127.0.0.1", port), timeout=1).close()
            return True
        except OSError:
            return False

    def mounted(self):
        with open("/proc/self/mounts") as f:
            return any(line.split()[1] == str(self.mnt) for line in f)

    def online(self):
        """The drive in use, as before the network goes: a folder listed, a file opened, a file saved and uploaded"""
        self.assertEqual(sorted(os.listdir(self.mnt)), ["folder", "seen.txt"])
        (self.mnt / "saved.txt").write_text("saved online\n")
        self.assertEqual((self.mnt / "saved.txt").read_text(), "saved online\n")
        self.wait(lambda: (self.served / "saved.txt").exists(), 20, "the saved file wasn't uploaded")

    def calls(self, cap):
        """Every call a program makes on the folder, all at once, each timed: {name: (seconds, status)}"""
        m = str(self.mnt)
        cmds = {"list": f"ls '{m}'", "stat": f"stat '{m}/seen.txt'", "df": f"df '{m}'",
                "read cached": f"cat '{m}/saved.txt'", "read new": f"cat '{m}/seen.txt'",
                "list folder": f"ls '{m}/folder'", "save": f"echo offline > '{m}/offline.txt'",
                "mkdir": f"mkdir '{m}/new-folder'"}
        out, threads = {}, []
        for name, cmd in cmds.items():
            t = threading.Thread(target=lambda n=name, c=cmd: out.__setitem__(n, timed(c, cap)))
            t.start()
            threads.append(t)
        for t in threads:
            t.join()
        return out

    def check(self, results, must_work):
        report = "\n".join(f"  {n}: {s:.1f} s, " + ("hung" if r is None else f"exit {r}")
                           for n, (s, r) in sorted(results.items()))
        print(f"\n{self.id().split('.')[-1]} (limit {LIMIT} s, a download {READ_LIMIT} s):\n{report}", file=sys.stderr)
        self.log.flush()
        report += "\nrclone's log:\n" + "".join((self.tmp / "rclone.log").read_text().splitlines(True)[-30:])
        for name, (seconds, status) in results.items():
            self.assertIsNotNone(status, f"{name} hung:\n{report}")
            self.assertLess(seconds, READ_LIMIT if name == "read new" else LIMIT, f"{name} took too long:\n{report}")
        for name in must_work:
            self.assertEqual(results[name][1], 0, f"{name} should work offline:\n{report}")
