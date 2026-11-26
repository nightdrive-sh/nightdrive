"""The rclone mount command for one drive, and the wait for its host before it.

What matters most here is that no program hangs when the network is gone, the old trouble with sshfs and GVfs: a call
on a network folder blocks the program that made it until the filesystem answers, so every way the answer can take
long is cut short.
- The connection: ssh gives up connecting after CONNECT_TIMEOUT and drops a link that stops answering after
  ALIVE_INTERVAL * ALIVE_COUNT seconds; rclone's own --contimeout and --timeout do the same for other remotes.
- Retries: rclone tries a failed call 10 times by default, each up to a minute. One here, so a call without the network
  fails in seconds (the program gets an I/O error) instead of hanging for minutes. Its cache still tries a download 10
  times, with no flag to say otherwise, so ssh runs behind lib/ssh-breaker: after one failed try the rest fail at once.
- Free space: df, a file manager's status line and every Open dialog ask the filesystem for it (statfs), and rclone
  asks the server: --disable About answers from here.
- Listings: a folder read in the last DIR_CACHE opens without asking the server, so does a file in the cache
  (--vfs-cache-mode full: what was opened stays for CACHE_MAX_AGE), and a write goes to the cache and is uploaded when
  it can be, so saving works offline too. --vfs-fast-fingerprint keeps rclone from hashing files over the network.
lib/offline_test.py holds this to account: a mount whose connection stops answering must fail fast on every call.
"""
import os
import socket
import subprocess
import time

import drives

CONNECT_TIMEOUT = 5        # s: connecting (ssh's ConnectTimeout, rclone's --contimeout)
ALIVE_INTERVAL = 3         # s between ssh's keepalives
ALIVE_COUNT = 2            # unanswered keepalives before ssh drops the link
IO_TIMEOUT = "15s"         # rclone: a transfer silent this long is dropped (remotes over http)
DIR_CACHE = "1m"           # a listing is read again after this (changes made elsewhere show within it)
CACHE_MAX_AGE = "168h"     # a cached file unused this long is dropped
CACHE_MAX_SIZE = "20G"     # the cache of one drive at most (the oldest go first)
WRITE_BACK = "5s"          # a saved file is uploaded this long after it was closed
# Hidden in an ssh drive: the account's own keys (a Storage Box keeps its authorized_keys there), so they can't be
# deleted by accident and lock the account out of key logins
SSH_HIDDEN = ["/.ssh/**"]
# ssh behind a circuit breaker: after a failed try, the next ones fail at once for a while (its header says why)
BREAKER = os.path.join(os.path.dirname(os.path.realpath(__file__)), "ssh-breaker")
WAIT_MAX = 60              # s: the longest pause between tries while the host doesn't answer


def runtime_dir():
    return os.path.join(os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}", "netdrive")


def breaker_flag(d):
    """Set while the drive's host doesn't answer (lib/ssh-breaker)"""
    return os.path.join(runtime_dir(), f"{d['name']}.down")


def rc_socket(d):
    """rclone's remote control for the drive (pending uploads, refresh), a socket only this user can reach"""
    return os.path.join(runtime_dir(), f"{d['name']}.sock")


def cache_dir(d):
    """One cache per drive: rclone names its cache by the remote, and two ssh drives would both be ":sftp" """
    base = os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache")
    return os.path.join(base, "netdrive", d["name"])


def ssh_command(host, extra=()):
    """The ssh rclone runs (its external ssh: ~/.ssh/config, the key and its agent as ssh has them). BatchMode: it never
    waits for a password no one can type. extra: options before the host (the tests' own key and port)."""
    return ["ssh", "-o", "BatchMode=yes", "-o", f"ConnectTimeout={CONNECT_TIMEOUT}",
            "-o", f"ServerAliveInterval={ALIVE_INTERVAL}", "-o", f"ServerAliveCountMax={ALIVE_COUNT}", *extra, host]


def remote(d):
    if d.get("ssh"):
        return ":sftp:" + d.get("root", "")
    return d["remote"]


def space_list(args):
    """One string as rclone reads a list option: split on spaces like a CSV line, so a part with a space or a quote in
    it goes in double quotes, a quote in it doubled (shell quoting would reach ssh as part of the argument)"""
    return " ".join('"' + a.replace('"', '""') + '"' if not a or any(c in a for c in ' "') else a for a in args)


def connection_flags(d, ssh=None):
    """How rclone connects and gives up (the module's docstring): the mount's and netdrive add's check alike. ssh: the
    ssh argv in place of ssh_command's (the tests' own key and port)."""
    flags = ["--contimeout", f"{CONNECT_TIMEOUT}s", "--timeout", IO_TIMEOUT, "--low-level-retries", "1"]
    if d.get("ssh"):
        guarded = [BREAKER, breaker_flag(d), *(ssh or ssh_command(d["ssh"]))]
        flags += ["--sftp-ssh", space_list(guarded),
                  "--sftp-shell-type", "none", "--sftp-disable-hashcheck", "--sftp-known-hosts-file", "none"]
    return flags


def argv(d, ssh=None):
    """rclone mount's argv for the drive"""
    cmd = ["rclone", "mount", remote(d), drives.mountpoint(d),
           "--vfs-cache-mode", "full", "--vfs-cache-max-age", CACHE_MAX_AGE, "--vfs-cache-max-size", CACHE_MAX_SIZE,
           "--vfs-write-back", WRITE_BACK, "--vfs-fast-fingerprint", "--dir-cache-time", DIR_CACHE,
           *connection_flags(d, ssh), "--disable", "About", "--cache-dir", cache_dir(d),
           "--rc", "--rc-addr", "unix://" + rc_socket(d), "--rc-no-auth",
           "--devname", f"netdrive:{d['name']}", "--log-level", "NOTICE"]
    if d.get("read_only"):
        cmd.append("--read-only")
    if d.get("ssh"):
        for pattern in SSH_HIDDEN:
            cmd += ["--exclude", pattern]
    return cmd


def ssh_target(host):
    """(hostname, port) ssh would connect to, from ssh -G; None when it goes through a proxy (no direct test then)"""
    r = subprocess.run(["ssh", "-G", host], capture_output=True, text=True, timeout=10)
    if r.returncode != 0:
        raise drives.Refused(r.stderr.strip() or f"ssh doesn't know {host}.")
    conf = dict(line.split(" ", 1) for line in r.stdout.splitlines() if " " in line)
    if conf.get("proxycommand", "none") != "none" or conf.get("proxyjump", "none") != "none":
        return None
    return conf.get("hostname", host), int(conf.get("port", 22))


def reachable(target):
    """True when the host takes a connection within CONNECT_TIMEOUT"""
    try:
        with socket.create_connection(target, timeout=CONNECT_TIMEOUT):
            return True
    except OSError:
        return False


def wait_for(target, notify=lambda text: None, sleep=time.sleep):
    """Returns once the host answers, trying again with a longer pause each time (up to WAIT_MAX). Before the mount, so
    that a computer started without a network waits quietly instead of failing the service over and over; the folder
    meanwhile is an empty local folder, and nothing hangs on it."""
    pause = 2
    while not reachable(target):
        notify(f"Waiting for {target[0]} to answer")
        sleep(pause)
        pause = min(pause * 2, WAIT_MAX)
