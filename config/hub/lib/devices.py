"""Devices for the sync tests: each a throwaway home of its own, running `cli.py` as its own process.

A process per device because Tasks' store reads where its folder is once, when imported; and because that is how the
timer runs it. NIGHTDRIVE_HUB_NO_TIMER keeps `join` from turning on the person's real systemd timer: a test's home is
throwaway, their systemd isn't.
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile
import uuid

LIB = os.path.dirname(os.path.abspath(__file__))
CLI = os.path.join(LIB, "cli.py")


def vtodo(uid, summary, extra=""):
    return ("BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//Test//EN\r\nBEGIN:VTODO\r\nUID:%s\r\nSUMMARY:%s\r\n%s"
            "STATUS:NEEDS-ACTION\r\nEND:VTODO\r\nEND:VCALENDAR\r\n" % (uid, summary, extra))


class Device:
    def __init__(self, name):
        self.name = name
        self.home = tempfile.mkdtemp(prefix="hub-%s-" % name)
        self.tasks = os.path.join(self.home, ".local/share/nightdrive/tasks")
        self.env = {"HOME": self.home, "PATH": os.environ.get("PATH", "/usr/bin:/bin"), "LANG": "C.UTF-8",
                    "XDG_CONFIG_HOME": os.path.join(self.home, ".config"),
                    "XDG_DATA_HOME": os.path.join(self.home, ".local/share"),
                    "XDG_STATE_HOME": os.path.join(self.home, ".local/state"),
                    "NIGHTDRIVE_HUB_NO_TIMER": "1"}

    def run(self, *args, ok=True):
        r = subprocess.run([sys.executable, "-I", CLI] + list(args), env=self.env, capture_output=True, text=True,
                           timeout=60)
        if ok and r.returncode:
            raise AssertionError("%s: hub %s failed (%d): %s%s" % (self.name, " ".join(args), r.returncode,
                                                                   r.stdout, r.stderr))
        return r

    def sync(self, *more):
        """The status after one sync, as JSON."""
        return json.loads(self.run("sync", "--json", *more).stdout)

    def status(self):
        return json.loads(self.run("status", "--json").stdout)

    # Tasks' files

    def add(self, lst, summary, uid=None, name=None):
        """Writes a task file in a list (made with its displayname if new). Returns its path in the collection."""
        uid = uid or str(uuid.uuid4())
        d = os.path.join(self.tasks, lst)
        if not os.path.isdir(d):
            os.makedirs(d)
            with open(os.path.join(d, "displayname"), "w") as f:
                f.write(lst.capitalize() + "\n")
        rel = "%s/%s.ics" % (lst, name or uid)
        self.write(rel, vtodo(uid, summary))
        return rel

    def write(self, rel, text):
        p = os.path.join(self.tasks, rel)
        os.makedirs(os.path.dirname(p), exist_ok=True)
        with open(p, "w", newline="") as f:
            f.write(text)

    def read(self, rel):
        p = os.path.join(self.tasks, rel)
        if not os.path.exists(p):
            return None
        with open(p, newline="") as f:
            return f.read()

    def remove(self, rel):
        os.unlink(os.path.join(self.tasks, rel))

    def files(self):
        """{path: text} of every file in the vdir, hidden ones left out."""
        out = {}
        for d, dirs, names in os.walk(self.tasks):
            for n in names:
                if not n.startswith("."):
                    rel = os.path.relpath(os.path.join(d, n), self.tasks)
                    out[rel] = self.read(rel)
        return out

    def trashed(self):
        """Paths in Tasks' own trash (~/.local/state/nightdrive/tasks/trash)."""
        t = os.path.join(self.home, ".local/state/nightdrive/tasks/trash")
        return sorted(os.path.relpath(os.path.join(d, n), t) for d, _, ns in os.walk(t) for n in ns)

    def close(self):
        shutil.rmtree(self.home, ignore_errors=True)
