"""Each drive's state: its service (systemd), whether its folder is mounted (/proc/self/mounts) and what rclone has
waiting to upload (its remote control socket).

Nothing here touches the drive's folder itself: a stat on a network folder is the very call that can wait on the
network, and the top bar asks every few seconds.
"""
import http.client
import json
import socket
import subprocess

import drives
import mountcmd

UNIT = "nightdrive-netdrive@{}.service"
RC_TIMEOUT = 1   # s: rclone answers its socket at once; one that doesn't is reported, not waited for


def unescape(field):
    """/proc/self/mounts writes a space as \\040 (and tab, newline, backslash likewise)"""
    out, i = "", 0
    while i < len(field):
        if field[i] == "\\" and field[i + 1:i + 4].isdigit():
            out += chr(int(field[i + 1:i + 4], 8))
            i += 4
        else:
            out += field[i]
            i += 1
    return out


def mounts(text=None):
    """{mountpoint: fstype} of what is mounted now"""
    if text is None:
        with open("/proc/self/mounts") as f:
            text = f.read()
    out = {}
    for line in text.splitlines():
        parts = line.split()
        if len(parts) >= 3:
            out[unescape(parts[1])] = parts[2]
    return out


def units(names):
    """{name: {ActiveState, SubState, Result, StatusText, UnitFileState}} in one systemctl call"""
    if not names:
        return {}
    props = "Id,ActiveState,SubState,Result,StatusText,UnitFileState"
    r = subprocess.run(["systemctl", "--user", "show", "-p", props, *[UNIT.format(n) for n in names]],
                       capture_output=True, text=True, timeout=10)
    out = {}
    for block in r.stdout.strip().split("\n\n"):
        kv = dict(line.split("=", 1) for line in block.splitlines() if "=" in line)
        name = kv.get("Id", "").removeprefix("nightdrive-netdrive@").removesuffix(".service")
        if name:
            out[name] = kv
    return out


class _UnixHTTP(http.client.HTTPConnection):
    def __init__(self, path):
        super().__init__("localhost", timeout=RC_TIMEOUT)
        self.path = path

    def connect(self):
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.settimeout(RC_TIMEOUT)
        self.sock.connect(self.path)


def rc(d, method, params=None):
    """rclone's remote control: the answer as a dict, None when it can't be reached"""
    try:
        c = _UnixHTTP(mountcmd.rc_socket(d))
        c.request("POST", "/" + method, body=json.dumps(params or {}), headers={"Content-Type": "application/json"})
        r = c.getresponse()
        data = json.loads(r.read() or b"{}")
        c.close()
        return data if r.status == 200 else None
    except (OSError, ValueError, http.client.HTTPException):
        return None


def describe(d, unit, mounted):
    """The drive's row: {name, source, key, path, read_only, enabled, state, detail, uploads, failed_uploads}.
    state: mounted, connecting (waiting for the host, or rclone starting), failed, off, or stale (the folder still
    mounted while the service isn't running: `netdrive start NAME` mounts it again)."""
    path = drives.mountpoint(d)
    active = unit.get("ActiveState", "")
    row = {"name": d["name"], "source": f"ssh {d['ssh']}" if d.get("ssh") else d.get("remote", ""),
           "key": bool(d.get("key")), "path": path,
           "read_only": bool(d.get("read_only")), "enabled": unit.get("UnitFileState") == "enabled",
           "detail": unit.get("StatusText", ""), "uploads": 0, "failed_uploads": 0}
    is_mounted = mounted.get(path, "").startswith("fuse")
    if active == "active" and is_mounted:
        row["state"] = "mounted"
        stats = rc(d, "vfs/stats") or {}
        cache = stats.get("diskCache") or {}
        row["uploads"] = int(cache.get("uploadsQueued", 0)) + int(cache.get("uploadsInProgress", 0))
        row["failed_uploads"] = int(cache.get("erroredFiles", 0))
    elif active in ("activating", "active", "reloading"):
        row["state"] = "connecting"
    elif active == "failed":
        row["state"] = "failed"
        row["detail"] = row["detail"] or f"stopped: {unit.get('Result', 'failed')}"
    elif is_mounted:
        row["state"] = "stale"
    else:
        row["state"] = "off"
    return row


def all_rows():
    ds = drives.load()
    us = units([d["name"] for d in ds])
    m = mounts()
    return [describe(d, us.get(d["name"], {}), m) for d in ds]


def summary(rows):
    """(icon, text, class) for the top bar, or None when all is well: it shows only what needs a look. A drive turned
    off on purpose (off and not enabled) is fine; one that should be on and isn't is not."""
    trouble = [r for r in rows if r["state"] in ("failed", "stale") or r["failed_uploads"]
               or (r["enabled"] and r["state"] in ("connecting", "off"))]
    if trouble:
        failed = any(r["state"] in ("failed", "stale") or r["failed_uploads"] for r in trouble)
        return "cloud-off", "", "critical" if failed else "warning"
    uploads = sum(r["uploads"] for r in rows)
    if uploads:
        return "cloud-upload", str(uploads), "pulse"
    return None


def line(rows):
    """One sentence for a person (and Claude)"""
    if not rows:
        return "No network drives: netdrive add NAME --ssh HOST adds one."
    parts = []
    for r in rows:
        s = {"mounted": "mounted", "connecting": "connecting", "failed": "failed", "off": "off",
             "stale": "stale mount"}[r["state"]]
        if r["uploads"]:
            s += f", {r['uploads']} to upload"
        if r["failed_uploads"]:
            s += f", {r['failed_uploads']} failed to upload"
        parts.append(f"{r['name']} {s}")
    return "; ".join(parts) + "."
