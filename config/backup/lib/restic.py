#!/usr/bin/env python3
"""restic, run for `nightdrive backup` (docs/backup.md): the repository and its password from backup.conf, and the
answer to "is the repository there at all?" before a run, so a laptop away from the network isn't an error."""
import json
import os
import shutil
import socket
import subprocess
from pathlib import Path
from urllib.parse import urlparse

# Seconds to wait for the repository's host before calling it out of reach
CONNECT_TIMEOUT = 10
# Not ours to back up, whatever the excludes file says: restic's own lock-free cache, other disks and network mounts
# (--one-file-system: a mounted Storage Box would otherwise go into its own backup), and folders marked CACHEDIR.TAG
BACKUP_FLAGS = ["--one-file-system", "--exclude-caches"]


class Missing(RuntimeError):
    """restic isn't installed."""


class Offline(RuntimeError):
    """The repository's host or disk isn't reachable now."""


def env(cfg):
    e = dict(os.environ, RESTIC_REPOSITORY=cfg["repository"], RESTIC_PASSWORD_COMMAND=cfg["password-cmd"])
    # A password left in the environment would win over the command and could open another repository by mistake
    e.pop("RESTIC_PASSWORD", None), e.pop("RESTIC_PASSWORD_FILE", None)
    return e


def binary():
    path = shutil.which("restic")
    if not path:
        raise Missing("restic isn't installed: sudo dnf install restic")
    return path


def run(cfg, args, capture=True, check=True):
    """restic ARGS against the configured repository. Raises RuntimeError with restic's own last error line."""
    r = subprocess.run([binary()] + args, env=env(cfg), text=True, stdin=subprocess.DEVNULL,
                       capture_output=capture)
    if check and r.returncode:
        raise RuntimeError("restic %s: %s" % (args[0], last_error(r.stderr or "") or "exit %d" % r.returncode))
    return r


def last_error(stderr):
    lines = [ln.strip() for ln in stderr.splitlines() if ln.strip()]
    for ln in reversed(lines):
        if ln.startswith(("Fatal:", "error:", "Error:")) or "unable to" in ln:
            return ln
    return lines[-1] if lines else ""


def exists(cfg):
    """True when the repository has been initialised (restic cat config reads its config file)."""
    return run(cfg, ["cat", "config"], check=False).returncode == 0


def init(cfg):
    run(cfg, ["init"])


def backup(cfg, excludes, tag):
    """One backup of the configured paths. Returns restic's summary: files_new, files_changed, data_added,
    total_files_processed, total_bytes_processed, total_duration, snapshot_id. Exit 3 (some files couldn't be read,
    a socket or a file removed mid-run) still made a snapshot, so it isn't a failure; the count is in "unreadable"."""
    args = ["backup", "--json", "--tag", tag, "--exclude-file", str(excludes)] + BACKUP_FLAGS + cfg["path"]
    r = run(cfg, args, check=False)
    summary, unreadable = None, 0
    for line in (r.stdout or "").splitlines():
        try:
            msg = json.loads(line)
        except ValueError:
            continue
        if msg.get("message_type") == "summary":
            summary = msg
        elif msg.get("message_type") == "error":
            unreadable += 1
    if r.returncode not in (0, 3) or not summary:
        raise RuntimeError("restic backup: %s" % (last_error(r.stderr or "") or "exit %d" % r.returncode))
    summary["unreadable"] = unreadable
    return summary


def forget(cfg, tag):
    """Lets go of the snapshots the keep-* settings don't keep, and frees their space. Only this machine's (its host
    name, as restic records it) and only Nightdrive's (the tag), so two machines sharing a repository, or snapshots
    made by hand, are never pruned by it."""
    keep = []
    for key in ("keep-daily", "keep-weekly", "keep-monthly", "keep-yearly"):
        keep += ["--" + key, str(cfg[key])]
    run(cfg, ["forget", "--host", socket.gethostname(), "--tag", tag, "--group-by", "host,tags", "--prune"] + keep)


def check(cfg, subset):
    """The repository's structure, and SUBSET (e.g. "5%") of its data read back and verified."""
    run(cfg, ["check", "--read-data-subset", subset])


def snapshots(cfg):
    return json.loads(run(cfg, ["snapshots", "--json"]).stdout or "[]")


def reachable(cfg, timeout=CONNECT_TIMEOUT):
    """Raises Offline when the repository can't be reached now: its host doesn't answer, or its folder's disk isn't
    there. Backends this can't tell about (rclone:) are left for restic to find out."""
    repo = cfg["repository"]
    kind, _, rest = repo.partition(":")
    if kind == "sftp":
        host, port = ssh_target(rest)
        connect(host, port, timeout)
    elif kind in ("rest", "s3", "b2", "azure", "gs", "swift"):
        host = urlparse(rest).hostname if "://" in rest else None
        if host:
            connect(host, urlparse(rest).port or 443, timeout)
    elif kind == "rclone":
        return
    else:
        # A local repository: its parent folder is there unless the disk holding it isn't mounted
        parent = Path(repo).expanduser().parent
        if not parent.is_dir():
            raise Offline("%s isn't there (a disk not mounted?)" % parent)


def ssh_target(rest):
    """(host, port) of sftp:[user@]host:/path or sftp://[user@]host[:port]/path, resolved through ~/.ssh/config as
    ssh would (`ssh -G`): an alias such as storage-backup has its HostName and Port there."""
    if rest.startswith("//"):
        u = urlparse("sftp:" + rest)
        alias, port = u.hostname, u.port
    else:
        alias, port = rest.split(":", 1)[0].rsplit("@", 1)[-1], None
    host = alias
    try:
        out = subprocess.run(["ssh", "-G", alias], capture_output=True, text=True, timeout=5).stdout
        for line in out.splitlines():
            k, _, v = line.partition(" ")
            if k == "hostname":
                host = v
            elif k == "port" and not port:
                port = int(v)
    except (OSError, subprocess.SubprocessError, ValueError):
        pass
    return host, port or 22


def connect(host, port, timeout):
    try:
        socket.create_connection((host, port), timeout).close()
    except OSError as e:
        raise Offline("%s:%s out of reach (%s)" % (host, port, e.strerror or e)) from None
