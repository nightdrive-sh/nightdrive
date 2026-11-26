#!/usr/bin/env python3
"""Text onto a running VM's clipboard, through the guest agent inside it (#3117), for garage-ctl clip (lib/clip.sh):

    guestclip.py SOCKET VM [--clipboard] [--sent FILE KEY [--if-changed]]

The text is stdin's, or with --clipboard the host's clipboard (wl-paste): text only, at most MAX_BYTES, and not what a
password manager marked as secret (x-kde-passwordManagerHint), so a password copied on the host doesn't land in a VM
by itself. --sent: FILE remembers what went last (KEY, its qemu's pid, and the text's hash, never the text); with
--if-changed the same again prints "same" and sends nothing, as the automatic send on focus would otherwise go out at
every click (a send by hand always goes: the guest's own clipboard may have changed since).

Two ways into the guest, whichever its agent allows (guest-info says):
  exec   guest-exec runs a shell script as root that hands the text to wl-copy as the user whose Wayland desktop is
         running (Arch, Omarchy: their qemu-guest-agent allows it)
  file   Fedora's agent blocks guest-exec (and SELinux confines it), but writes in /run: the text goes to CLIP_FILE,
         after a line with the time, and Nightdrive in the guest puts it on its clipboard (config/hypr/scripts/
         vm-clipboard). Another desktop on Fedora gets nothing this way: the README says so
Prints the way it went. Exit 1 with a line for the window's error line, 3 when the guest agent doesn't answer.
"""
import base64
import hashlib
import importlib.util
import os
import subprocess
import sys
import time

MAX_BYTES = 256 * 1024          # a page of text many times over; the agent's JSON carries it as base64
EXEC_WAIT = 5                   # seconds for the guest's script to hand it over
CLIP_FILE = "/run/nightdrive-host-clipboard"
CLIP_HEADER = b"nightdrive-clipboard"
SECRET_HINT = "x-kde-passwordManagerHint"
# The host clipboard's text types, best first
TEXT_TYPES = ["text/plain;charset=utf-8", "text/plain", "UTF8_STRING", "STRING", "TEXT"]
NO_WL_COPY, NO_DESKTOP = 4, 5   # the guest script's exit codes

# As root in the guest: the first desktop's Wayland socket that a user (uid 1000 or more: not a login screen's) owns,
# and wl-copy as that user. wl-copy stays behind to serve the clipboard: its output goes nowhere, so the agent isn't
# left waiting for it to close
GUEST_SCRIPT = r'''
command -v wl-copy >/dev/null 2>&1 || exit 4
for s in /run/user/[0-9]*/wayland-[0-9]; do
  [ -S "$s" ] || continue
  dir=${s%/*}; uid=${dir##*/}
  [ "$uid" -ge 1000 ] || continue
  user=$(getent passwd "$uid" | cut -d: -f1)
  [ -n "$user" ] || continue
  exec runuser -u "$user" -- env XDG_RUNTIME_DIR="$dir" WAYLAND_DISPLAY="${s##*/}" wl-copy >/dev/null 2>&1
done
exit 5
'''


class Refused(Exception):
    """Something the user is told, on the window's error line"""


def load_monitor():
    # monitor.py's QMP/QGA client; -I leaves this folder out of sys.path, so it is loaded by its path
    spec = importlib.util.spec_from_file_location("monitor", os.path.join(os.path.dirname(__file__), "monitor.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def pick_type(types):
    """The text type to paste from the host clipboard's offered types, or Refused with why not"""
    if SECRET_HINT in types:
        raise Refused("The clipboard holds a password (its password manager says so): not sent")
    for t in TEXT_TYPES:
        if t in types:
            return t
    raise Refused("Nothing to send: the clipboard has no text")


def host_clipboard():
    try:
        types = subprocess.run(["wl-paste", "-l"], capture_output=True, text=True, timeout=5).stdout.split("\n")
    except (OSError, subprocess.TimeoutExpired):
        raise Refused("Nothing to send: the clipboard has no text")
    t = pick_type([x.strip() for x in types if x.strip()])
    r = subprocess.run(["wl-paste", "-n", "-t", t], capture_output=True, timeout=5)
    return r.stdout


def check(text, where="the clipboard"):
    """where: what the text came from, for the line the user reads"""
    if not text:
        raise Refused(f"Nothing to send: {where} has no text")
    if len(text) > MAX_BYTES:
        raise Refused(f"The text is over {MAX_BYTES // 1024} KB: not sent")
    try:
        text.decode("utf-8")
    except UnicodeDecodeError:
        raise Refused(f"Nothing to send: {where} has no text")


def fingerprint(key, text):
    return f"{key} {hashlib.sha256(text).hexdigest()}"


def already_sent(path, key, text):
    try:
        with open(path) as f:
            return f.read().strip() == fingerprint(key, text)
    except OSError:
        return False


def remember(path, key, text):
    os.makedirs(os.path.dirname(path), mode=0o700, exist_ok=True)
    with open(path + ".new", "w") as f:
        f.write(fingerprint(key, text) + "\n")
    os.replace(path + ".new", path)


def enabled_commands(info):
    return {c["name"] for c in info.get("supported_commands", []) if c.get("enabled", True)}


def route(vm, enabled):
    """exec, file, or Refused: what the guest agent allows"""
    if {"guest-exec", "guest-exec-status"} <= enabled:
        return "exec"
    if {"guest-file-open", "guest-file-write", "guest-file-close"} <= enabled:
        return "file"
    raise Refused(f"{vm}'s guest agent allows neither guest-exec nor writing a file: `v` types the text instead")


def exec_failure(vm, status):
    code = status.get("exitcode")
    if code == NO_WL_COPY:
        return f"{vm} has no wl-copy: install wl-clipboard in it"
    if code == NO_DESKTOP:
        return f"No one is logged in to a Wayland desktop in {vm}"
    err = base64.b64decode(status.get("err-data", "")).decode("utf-8", "replace").strip()
    what = f"exit {code}" if code is not None else f"signal {status.get('signal')}"
    return f"{vm} didn't take the clipboard ({what}{': ' + err if err else ''})"


class Agent:
    """One connection to the guest agent: call() returns a command's value, or raises Refused with its error"""
    def __init__(self, mon, f, vm):
        self.mon, self.f, self.vm = mon, f, vm

    def call(self, cmd, args=None):
        self.mon.send(self.f, cmd, args)
        r = self.mon.answer(self.f)
        if "error" in r:
            e = r["error"]
            raise Refused(f"{self.vm}: {e.get('desc', e) if isinstance(e, dict) else e}")
        return r["return"]

    def sync(self):
        token = int.from_bytes(os.urandom(4), "big") >> 1
        self.mon.send(self.f, "guest-sync", {"id": token})
        while self.mon.answer(self.f).get("return") != token:
            pass


def deliver(agent, text, now_ns):
    agent.sync()
    how = route(agent.vm, enabled_commands(agent.call("guest-info")))
    data = base64.b64encode(text).decode()
    if how == "exec":
        pid = agent.call("guest-exec", {"path": "/bin/sh", "arg": ["-c", GUEST_SCRIPT],
                                        "input-data": data, "capture-output": True})["pid"]
        until = time.monotonic() + EXEC_WAIT
        while True:
            st = agent.call("guest-exec-status", {"pid": pid})
            if st.get("exited"):
                break
            if time.monotonic() > until:
                raise Refused(f"{agent.vm} didn't take the clipboard in {EXEC_WAIT} s")
            time.sleep(0.05)
        if st.get("exitcode") != 0:
            raise Refused(exec_failure(agent.vm, st))
    else:
        body = CLIP_HEADER + b" " + str(now_ns).encode() + b"\n" + text
        h = agent.call("guest-file-open", {"path": CLIP_FILE, "mode": "w"})
        try:
            agent.call("guest-file-write", {"handle": h, "buf-b64": base64.b64encode(body).decode()})
        finally:
            agent.call("guest-file-close", {"handle": h})
    return how


def main(argv):
    if len(argv) < 3:
        sys.exit(__doc__)
    sock, vm, rest = argv[1], argv[2], argv[3:]
    from_clipboard = "--clipboard" in rest
    sent = None
    if "--sent" in rest:
        i = rest.index("--sent")
        sent = rest[i + 1:i + 3]
        if len(sent) != 2:
            sys.exit("--sent FILE KEY")
    mon = load_monitor()
    try:
        text = host_clipboard() if from_clipboard else sys.stdin.buffer.read(MAX_BYTES + 1)
        check(text, "the clipboard" if from_clipboard else "the input")
        if sent and "--if-changed" in rest and already_sent(sent[0], sent[1], text):
            print("same")
            return
        mon.deadline = time.monotonic() + mon.DEADLINE
        import socket
        s = socket.socket(socket.AF_UNIX)
        s.settimeout(mon.TIMEOUT)
        try:
            s.connect(sock)
            how = deliver(Agent(mon, s.makefile("rw"), vm), text, time.time_ns())
        except socket.timeout:
            sys.exit(mon.NO_AGENT)
        except (OSError, ValueError) as e:
            raise Refused(f"{vm} doesn't answer ({getattr(e, 'strerror', None) or e})")
        if sent:
            remember(sent[0], sent[1], text)
        print(how)
    except Refused as e:
        sys.exit(str(e))


if __name__ == "__main__":
    main(sys.argv)
