"""Network Drives (plugins/netdrive) in Files' sidebar, among the disks: each drive with a cloud, mounted or not.

Gio lists a mounted drive as a disk of its own, and its eject would only unmount it under its service. So places.py
asks here: a drive is known by its mount's device, netdrive:NAME (/proc/self/mounts; rclone's --devname), its row
takes Gio's place, a drive that is stopped stays as a row to mount, and mounting or unmounting one goes through the
netdrive command (start / stop: its service, so it also stays so at the next login).
Without the plugin (no command, no drives) there are none, and nothing here runs.
"""
import json
import os
import subprocess
import time

import trash

PREFIX = "netdrive:"
MOUNT_WAIT = 30   # s: a drive's service checks its host, then rclone mounts it


def command():
    """The plugin's command; Files may run without ~/.local/bin in its PATH"""
    path = os.path.expanduser("~/.local/bin/netdrive")
    return path if os.access(path, os.X_OK) else ""


def mounted(text=None):
    """{mountpoint: drive name} of the drives mounted now"""
    if text is None:
        try:
            with open("/proc/self/mounts") as f:
                text = f.read()
        except OSError:
            return {}
    out = {}
    for line in text.splitlines():
        parts = line.split()
        if len(parts) >= 3 and parts[0].startswith(PREFIX):
            out[parts[1].replace("\\040", " ")] = parts[0][len(PREFIX):]
    return out


def rows():
    """[{name, path ("" unmounted), device (netdrive:NAME), glyph, unmount}] for the sidebar: every drive the plugin has,
    one that isn't mounted (stopped, or waiting for its host) as a row that mounts it"""
    cmd = command()
    if not cmd:
        return []
    try:
        r = subprocess.run([cmd, "list", "--json"], capture_output=True, text=True, timeout=10)
        drives = json.loads(r.stdout).get("drives", [])
    except (OSError, ValueError, subprocess.TimeoutExpired):
        return []
    now = mounted()
    out = []
    for d in drives:
        is_mounted = now.get(d.get("path", "")) == d.get("name")
        out.append({"name": d["name"], "path": d["path"] if is_mounted else "", "device": PREFIX + d["name"],
                    "glyph": "cloud" if is_mounted else "cloud-off", "unmount": is_mounted})
    return out


def mount(device):
    """Starts the drive's service and waits for its folder: {path}"""
    name = device[len(PREFIX):]
    r = subprocess.run([command(), "start", name], capture_output=True, text=True, timeout=30)
    if r.returncode != 0:
        raise trash.Refused(r.stderr.strip().removeprefix("netdrive: ") or f"{name} couldn't be started.")
    end = time.monotonic() + MOUNT_WAIT
    while time.monotonic() < end:
        for path, n in mounted().items():
            if n == name:
                return {"path": path}
        time.sleep(0.3)
    raise trash.Refused(f"{name} isn't answering: it mounts once its server does (the top bar's menu shows it).")


def unmount(path):
    """Stops the drive's service: {unmounted, said}"""
    name = mounted().get(path)
    r = subprocess.run([command(), "stop", name], capture_output=True, text=True, timeout=30)
    if r.returncode != 0:
        raise trash.Refused(r.stderr.strip().removeprefix("netdrive: ") or f"{name} couldn't be stopped.")
    return {"unmounted": path, "said": f"{name} disconnected"}
