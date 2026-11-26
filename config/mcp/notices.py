#!/usr/bin/env python3
"""The notifications of Claude's changes, from one helper process (#1882). Each change's row waits for its Undo
button for an hour (undo.NOTICE_FOR), and used to do so in a process of its own with a notify-send of its own: a
hundred changes, two hundred processes for an hour. Now the server hands each row to one helper over a socket in
XDG_RUNTIME_DIR, which starts when the first one comes and ends a minute after the last row has gone.

It keeps ROWS_MAX buttons at once. A row past that takes the oldest one's place: its button gives way to a line that
says to ask Claude, as the change itself stays in the log (recent_changes, undo_change) and can still be undone.

    python3 notices.py serve     the helper (show() starts it; one at a time, by its lock)
"""

import fcntl
import os
import select
import socket
import subprocess
import sys
import threading
import time
from collections import OrderedDict
from pathlib import Path

HERE = Path(__file__).resolve().parent
RUNTIME = Path(os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}")
SOCKET = RUNTIME / "nightdrive-claude-notices.sock"
LOCK = RUNTIME / "nightdrive-claude-notices.lock"
ROWS_MAX = 20        # rows with a live button at once
IDLE = 60            # seconds the helper stays with no rows, for the next change
START_WAIT = 3       # seconds show() waits for a helper it started to answer
REQUEST_MAX = 64     # bytes of a request: "ID undo\n"


def send(entry_id, action, path=None):
    """Hands a row to the helper; True once it said it has it."""
    try:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
            s.settimeout(2)
            s.connect(str(path or SOCKET))
            s.sendall(f"{entry_id} {action}\n".encode())
            return s.recv(16) == b"ok\n"
    except OSError:
        return False


def show(entry_id, action):
    """The row for an entry: the helper's, started if none runs. Without one (no runtime folder, a helper that won't
    start), a process of its own as before, so the button is never lost."""
    if send(entry_id, action):
        return
    if RUNTIME.is_dir():
        subprocess.Popen([sys.executable, str(HERE / "notices.py"), "serve"], stdin=subprocess.DEVNULL,
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
        end = time.monotonic() + START_WAIT
        while time.monotonic() < end:
            time.sleep(0.05)
            if send(entry_id, action):
                return
    subprocess.Popen([sys.executable, str(HERE / "undo.py"), "notice", str(entry_id), action],
                     stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                     start_new_session=True)


def request(line):
    """(entry id, action) of a request line; None when it isn't one."""
    parts = line.decode("ascii", "replace").split()
    if len(parts) == 2 and parts[0].isdigit() and parts[1] in ("undo", "redo"):
        return int(parts[0]), parts[1]
    return None


class Rows:
    """The rows the helper keeps, oldest first: a thread each, running undo.notice."""

    def __init__(self, undo, rows_max=ROWS_MAX):
        self.undo, self.rows_max = undo, rows_max
        self.rows = OrderedDict()   # entry id → its thread

    def add(self, entry_id, action):
        # A redo's row (undo_change) replaces the entry's row by its stack tag, which ends the old one's wait
        self.rows.pop(entry_id, None)
        thread = threading.Thread(target=self.undo.notice, args=(entry_id, action), daemon=True)
        self.rows[entry_id] = thread
        thread.start()
        while len(self.live()) > self.rows_max:
            oldest = next(iter(self.rows))
            self.rows.pop(oldest)
            self.undo.retire(oldest)

    def live(self):
        for entry_id in [i for i, t in self.rows.items() if not t.is_alive()]:
            del self.rows[entry_id]
        return self.rows


def serve(undo, path=SOCKET, lock=LOCK, idle=IDLE, stop=None):
    """The helper: rows from the socket until none has been left for idle seconds. Returns at once when another
    helper holds the lock."""
    with open(lock, "w") as held:
        try:
            fcntl.flock(held, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError:
            return
        path.unlink(missing_ok=True)   # one from a helper that died: the lock says none runs
        listener = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        old = os.umask(0o077)
        try:
            listener.bind(str(path))
        finally:
            os.umask(old)
        listener.listen(16)
        rows, quiet_since = Rows(undo), time.monotonic()
        try:
            while not (stop and stop.is_set()):
                if select.select([listener], [], [], 0.5)[0]:
                    conn, _ = listener.accept()
                    with conn:
                        conn.settimeout(2)
                        try:
                            asked = request(conn.recv(REQUEST_MAX))
                            if asked:
                                rows.add(*asked)
                            conn.sendall(b"ok\n" if asked else b"no\n")
                        except OSError:
                            pass
                if rows.live():
                    quiet_since = time.monotonic()
                elif time.monotonic() - quiet_since >= idle:
                    break
        finally:
            # The socket goes before the lock: a show() that comes now finds none and starts a helper of its own
            path.unlink(missing_ok=True)
            listener.close()


def main():
    if sys.argv[1:] != ["serve"]:
        sys.exit("usage: notices.py serve")
    sys.path.insert(0, str(HERE))
    import undo
    serve(undo)


if __name__ == "__main__":
    main()
