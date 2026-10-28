#!/usr/bin/env python3
"""Waits for a started VM's guest to be up, for lib/state.sh (boot_watch runs it in the background):

    bootwait.py VMDIR SSH_PORT LIMIT

Up is its sshd greeting on the forwarded port (SSH-2.0-…) or its guest agent answering a guest-sync, whichever comes
first. Then the VM's state file, while it still says booting, goes: the VM is running. It gives up, leaving the file,
when qemu has gone, the state has become something else (a shutdown asked for meanwhile) or LIMIT seconds have passed
(state.sh counts a boot that old as up).

The guest agent's socket takes one client at a time: a look at it is short, and only every few rounds, so that a
Shut down then (its guest-shutdown) rarely finds it taken.
"""
import fcntl
import json
import os
import random
import socket
import sys
import time

ROUND = 2           # seconds between looks
AGENT_EVERY = 2     # rounds between looks at the guest agent
PROBE_TIMEOUT = 0.8


def alive(vmdir):
    try:
        with open(os.path.join(vmdir, "pid")) as f:
            os.kill(int(f.read().strip()), 0)
        return True
    except (OSError, ValueError):
        return False


def booting(vmdir):
    try:
        with open(os.path.join(vmdir, "state")) as f:
            return f.read().split()[:1] == ["booting"]
    except OSError:
        return False


def ssh_up(port):
    """sshd's greeting: qemu's port forward takes the connection whatever the guest does, so only the greeting tells"""
    if not port:
        return False
    try:
        with socket.create_connection(("127.0.0.1", port), timeout=PROBE_TIMEOUT) as s:
            return s.recv(64).startswith(b"SSH-")
    except OSError:
        return False


def agent_up(vmdir):
    """The agent echoes guest-sync's id: one left over from an earlier client must not pass for this one's answer"""
    token = random.randrange(1, 2**31)
    try:
        with socket.socket(socket.AF_UNIX) as s:
            s.settimeout(PROBE_TIMEOUT)
            s.connect(os.path.join(vmdir, "qga.sock"))
            s.sendall((json.dumps({"execute": "guest-sync", "arguments": {"id": token}}) + "\n").encode())
            buf = b""
            while b'"return": %d' % token not in buf and b'"return":%d' % token not in buf:
                chunk = s.recv(4096)
                if not chunk or len(buf) > 65536:
                    return False
                buf += chunk
            return True
    except OSError:
        return False


def clear(vmdir):
    """The state file goes only if it still says booting: under state.lock, as garage-ctl stop may write meanwhile"""
    with open(os.path.join(vmdir, "state.lock"), "w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        if booting(vmdir):
            os.remove(os.path.join(vmdir, "state"))


def main():
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    vmdir, port, limit = sys.argv[1], int(sys.argv[2]), float(sys.argv[3])
    end = time.monotonic() + limit
    n = 0
    while time.monotonic() < end and alive(vmdir) and booting(vmdir):
        if ssh_up(port) or (n % AGENT_EVERY == 0 and agent_up(vmdir)):
            clear(vmdir)
            return
        n += 1
        time.sleep(ROUND)


main()
