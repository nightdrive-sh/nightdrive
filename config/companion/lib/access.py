"""Who gets in (protocol.md › Access).

The server listens on a Unix socket in the user's runtime folder, not on a port. tailscale serve proxies the tailnet's
HTTPS to it, and tailscaled (root) is the only peer let through: no other user of this computer, and no web page in a
browser here (DNS rebinding), can reach the API at all. Its own user's processes could, but they can run anything as
the user anyway.

tailscale serve drops any Tailscale-User-Login a device sends and sets its own for a user's device, so from tailscaled
the header can be trusted: only the machine's own Tailscale user gets in. A request without one (a tagged device,
Funnel) is refused, never taken as local.

The demo (made-up sessions) is on 127.0.0.1:PORT instead, for a browser here; it only lets in a Host of its own, so a
rebound name can't reach it either, and it keeps its slots in a file of its own (control.DEMO_CONFIG).
"""
import json
import os
import socket
import struct
import subprocess
import threading
import time

RUNTIME = os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}"
SOCKET = os.path.join(RUNTIME, "nightdrive", "companion.sock")
TAILSCALED_UID = 0      # tailscaled runs as root
OWNER_RETRY = 30        # seconds before asking Tailscale again when it didn't answer
OWNER_KEEP = 300        # seconds a known owner is kept before asking again (a login to another account)
DEMO_HOSTS = ("127.0.0.1", "localhost")


def peer_uid(conn):
    """The uid of the process at the other end of a Unix socket (SO_PEERCRED: pid, uid, gid)."""
    creds = conn.getsockopt(socket.SOL_SOCKET, socket.SO_PEERCRED, struct.calcsize("3i"))
    return struct.unpack("3i", creds)[1]


def tailscale_owner():
    """The login of this machine's Tailscale user, or None (not connected, or a tagged machine: no user's)."""
    try:
        st = json.loads(subprocess.run(["tailscale", "status", "--json"], capture_output=True, timeout=5).stdout)
        if st.get("BackendState") != "Running" or st["Self"].get("Tags"):
            return None
        return st["User"][str(st["Self"]["UserID"])]["LoginName"] or None
    except (OSError, subprocess.SubprocessError, ValueError, KeyError, TypeError, AttributeError):
        return None


class Owner:
    """The machine's Tailscale user, asked again now and then: Tailscale may come up after the server."""

    def __init__(self):
        self.login, self.at = None, 0.0
        self.lock = threading.Lock()

    def get(self):
        # One request asks and the others wait for its answer. When `at` was set before the answer came, a request in
        # parallel (a page reconnecting after a restart: its state and its stream) took the login not yet known for
        # no one's and got a 403 (#3081)
        with self.lock:
            if time.time() - self.at >= (OWNER_KEEP if self.login else OWNER_RETRY):
                self.login = tailscale_owner()
                self.at = time.time()
            return self.login


def allowed_tailnet(headers, owner):
    login = headers.get("Tailscale-User-Login")
    want = owner.get()
    return bool(login) and want is not None and login == want


def allowed_demo(headers, port):
    host = headers.get("Host", "")
    return host in {f"{h}:{port}" for h in DEMO_HOSTS}


def make_socket_dir():
    """The socket's folder, the user's alone (the runtime folder is already, this is in case it isn't)."""
    folder = os.path.dirname(SOCKET)
    os.makedirs(folder, mode=0o700, exist_ok=True)
    try:
        os.unlink(SOCKET)       # a server that died leaves it behind; bind would fail
    except FileNotFoundError:
        pass
