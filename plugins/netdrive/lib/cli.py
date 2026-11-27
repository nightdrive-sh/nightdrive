"""netdrive: network drives as folders, with rclone mount (plugins/netdrive/README.md).

    netdrive list|status [--json]          the drives and their state
    netdrive add NAME --ssh HOST [--root DIR] | --remote NAME:PATH  [--path DIR] [--read-only] [--no-start]
    netdrive remove NAME                   stops it and forgets it (the files on the server stay)
    netdrive start|stop|restart NAME|all   mount (and at every login), unmount (and not at login), connect again
                                           (restart all: the drives that are on)
    netdrive refresh NAME                  read its folders again now, not in a minute
    netdrive key NAME|all [--off]          log in with Network Drives' own key, not 1Password's (lib/sshkey.py)
    netdrive bar                           the top bar's line (status): ICON CLASS [TEXT], or nothing
    netdrive run NAME | release NAME       the service's own (nightdrive-netdrive@.service)
    netdrive init                          an empty list (the installer)
"""
import argparse
import json
import os
import socket
import subprocess
import sys

import drives
import mountcmd
import sshkey
import state

UNIT = state.UNIT


def systemctl(*a):
    return subprocess.run(["systemctl", "--user", *a], capture_output=True, text=True)


def notify(text):
    """The service's status line (systemctl status, the bar's menu), while it waits"""
    addr = os.environ.get("NOTIFY_SOCKET")
    if not addr:
        return
    if addr.startswith("@"):
        addr = "\0" + addr[1:]
    try:
        with socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM) as s:
            s.sendto(f"STATUS={text}".encode(), addr)
    except OSError:
        pass


def unmount(path):
    """Lazy: it goes at once, and a program still in the folder keeps its open files until it lets go"""
    if state.mounts().get(path, "").startswith("fuse"):
        subprocess.run(["fusermount3", "-uz", path], capture_output=True)


def prepare(d):
    """The folder before the mount: made if missing, and a leftover mount taken away (a crashed rclone leaves one that
    answers every call with an error). Something saved into the folder while it wasn't mounted is refused, said in the
    service's status and the menu, rather than hidden under the drive (rclone won't mount over it anyway). The folder
    can't simply be read-only meanwhile: fusermount3 mounts only on a folder the user can write to."""
    path = drives.mountpoint(d)
    unmount(path)
    os.makedirs(path, exist_ok=True)
    os.chmod(path, 0o755)
    if os.listdir(path):
        raise drives.Refused(f"{path} has files of its own: move them away, then netdrive start {d['name']}.")
    os.makedirs(mountcmd.runtime_dir(), mode=0o700, exist_ok=True)
    try:
        os.unlink(mountcmd.rc_socket(d))
    except FileNotFoundError:
        pass


def run(name):
    d = drives.get(name)
    try:
        prepare(d)
    except drives.Refused as e:
        notify(str(e))                        # the service's status line, which the menu shows
        raise
    if d.get("ssh"):
        target = mountcmd.ssh_target(d["ssh"])
        if target:
            mountcmd.wait_for(target, notify)
    if d.get("key"):
        try:
            sshkey.load(d["key"], notify)
        except drives.Refused as e:
            notify(str(e))
            raise
    notify("Mounting")
    cmd = mountcmd.argv(d)
    os.execvp(cmd[0], cmd)


def check(d):
    """Lists the drive's top folder once with the mount's own settings, so a wrong host or remote is said at once"""
    lsf = ["rclone", "lsf", "--max-depth", "1", mountcmd.remote(d), *mountcmd.connection_flags(d)]
    try:
        r = subprocess.run(lsf, capture_output=True, text=True, timeout=60)
    except subprocess.TimeoutExpired:
        raise drives.Refused(f"{d['name']} didn't answer in a minute.")
    if r.returncode != 0:
        last = [ln for ln in r.stderr.strip().splitlines() if ln][-1:] or ["rclone failed"]
        raise drives.Refused(f"{d['name']} can't be reached: {last[0]}")


def names(arg, enabled_only=False):
    """The drives NAME or all stand for; with enabled_only, all leaves out the ones turned off (stop)"""
    if arg != "all":
        return [drives.get(arg)["name"]]
    every = [d["name"] for d in drives.load()]
    if not enabled_only:
        return every
    return [n for n, u in state.units(every).items() if u.get("UnitFileState") == "enabled"]


def start(name):
    """Enabled (at every login) and started without waiting: offline the service waits for its host, as long as it
    takes, and a command (or Files' mount) mustn't wait with it"""
    systemctl("daemon-reload")
    r = systemctl("enable", "--now", "--no-block", UNIT.format(name))
    if systemctl("is-enabled", "-q", UNIT.format(name)).returncode:
        raise drives.Refused(f"Couldn't start {name}: {r.stderr.strip()} (systemctl --user status {UNIT.format(name)})")


def cmd_add(a):
    d = drives.add(a.name, ssh=a.ssh or "", remote=a.remote or "", path=a.path or "", root=a.root or "",
                   read_only=a.read_only)
    try:
        check(d)
    except drives.Refused:
        drives.remove(d["name"])
        raise
    if not a.no_start:
        start(d["name"])
    return d


def cmd_remove(a):
    d = drives.get(a.name)
    systemctl("disable", "--now", UNIT.format(a.name))
    path = drives.mountpoint(d)
    unmount(path)
    out = drives.remove(a.name)
    try:                                       # the empty folder goes too; one with files of its own stays
        os.chmod(path, 0o755)
        os.rmdir(path)
    except OSError:
        pass
    return out


def cmd_switch(a):
    done = []
    for n in names(a.name, enabled_only=a.cmd == "restart"):
        if a.cmd == "start":
            start(n)
        elif a.cmd == "stop":
            systemctl("disable", "--now", UNIT.format(n))
            unmount(drives.mountpoint(drives.get(n)))
        else:
            systemctl("restart", "--no-block", UNIT.format(n))
        done.append(n)
    return {a.cmd: done}


def cmd_key(a):
    """The drives' own key for each drive (made the first time), put on its host if it doesn't log in yet, then the
    drive connected again with it. --off: back to the Host's own key (the key stays on the host until removed there)."""
    done = []
    for n in names(a.name):
        d = drives.get(n)
        if not d.get("ssh"):
            raise drives.Refused(f"{n} isn't an ssh drive: its login is rclone's (rclone config).")
        if a.off:
            drives.set_key(n, "")
        else:
            sshkey.make()
            keyed = {**d, "key": sshkey.KEY}
            sshkey.load()
            try:
                check(keyed)
            except drives.Refused:
                sshkey.copy_id(d["ssh"])
                try:                           # the failed try left the circuit breaker set (lib/ssh-breaker)
                    os.unlink(mountcmd.breaker_flag(d))
                except FileNotFoundError:
                    pass
                check(keyed)
            drives.set_key(n, sshkey.KEY)
        systemctl("restart", "--no-block", UNIT.format(n))
        done.append(n)
    return {"key": "off" if a.off else sshkey.path(), "drives": done}


def cmd_refresh(a):
    d = drives.get(a.name)
    if state.rc(d, "vfs/refresh", {"recursive": "false"}) is None:
        raise drives.Refused(f"{a.name} isn't mounted: netdrive start {a.name}.")
    return {"refreshed": a.name}


def main(argv=None):
    p = argparse.ArgumentParser(prog="netdrive", description="Network drives as folders (rclone mount).")
    sub = p.add_subparsers(dest="cmd", required=True)
    for c in ("list", "status"):
        sub.add_parser(c, help="the drives and their state").add_argument("--json", action="store_true")
    s = sub.add_parser("add", help="add a drive and mount it")
    s.add_argument("name")
    s.add_argument("--ssh", help="a Host of ~/.ssh/config (its key and agent; no password is stored)")
    s.add_argument("--root", help="a folder on the ssh host to mount instead of its home")
    s.add_argument("--remote", help="any rclone remote, NAME:PATH (rclone config)")
    s.add_argument("--path", help=f"the folder (default {drives.DEFAULT_PARENT}/NAME)")
    s.add_argument("--read-only", action="store_true", help="nothing can be changed through it")
    s.add_argument("--no-start", action="store_true", help="add it without mounting it")
    sub.add_parser("remove", help="stop a drive and forget it").add_argument("name")
    for c in ("start", "stop", "restart"):
        sub.add_parser(c, help=f"{c} a drive (or all)").add_argument("name")
    sub.add_parser("refresh", help="read its folders again now").add_argument("name")
    s = sub.add_parser("key", help="log in with Network Drives' own key (no 1Password)")
    s.add_argument("name")
    s.add_argument("--off", action="store_true", help="back to the Host's own key")
    sub.add_parser("bar", help="the top bar's line")
    sub.add_parser("run", help="the service: mount it (in the foreground)").add_argument("name")
    sub.add_parser("release", help="the service: take a leftover mount away").add_argument("name")
    sub.add_parser("init", help="an empty list, if there is none")
    a = p.parse_args(argv)

    try:
        if a.cmd in ("list", "status"):
            rows = state.all_rows()
            if a.json:
                print(json.dumps({"line": state.line(rows), "drives": rows}, indent=2))
            else:
                print(state.line(rows))
            return 0
        if a.cmd == "bar":
            s = state.summary(state.all_rows()) if drives.config_file().exists() else None
            print(f"{s[0]} {s[2]} {s[1]}".strip() if s else "")    # ICON CLASS [TEXT]: the text may be empty
            return 0
        if a.cmd == "run":
            run(a.name)                           # becomes rclone
        if a.cmd == "release":
            unmount(drives.mountpoint(drives.get(a.name)))
            return 0
        out = {"add": cmd_add, "remove": cmd_remove, "start": cmd_switch, "stop": cmd_switch,
               "restart": cmd_switch, "refresh": cmd_refresh, "key": cmd_key, "init": lambda _: drives.init()}[a.cmd](a)
        print(json.dumps(out))
        return 0
    except drives.Refused as e:
        print(f"netdrive: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
