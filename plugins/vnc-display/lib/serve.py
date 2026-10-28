#!/usr/bin/python3
"""One device's screen, as nightdrive-vnc-display@NAME.service runs it (`vnc-display run NAME`).

Makes the device's headless output (its size, place and workspace come from config/hypr/virtual-display.lua, which reads
the same state file at the reload the new output brings), then runs wayvnc on it: one on each of the Tailscale addresses
(IPv4 and IPv6: the computer's Tailscale name gives both, and a device may try either), and one on the home network's address while the computer is on that network, if the device was added with --home. Both are
checked every TICK seconds, so a Tailscale that comes up later, or a move to another network, is followed.

The output going away stops everything at once: wayvnc would otherwise move to the desk's own screen ("Selected output
went away, rotating to previous output") and show it to the device. Hyprland's event socket tells us.
"""
import json
import os
import select
import signal
import socket
import subprocess
import sys
import time

CONF_DIR = os.path.join(os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config"), "nightdrive", "vnc-display")
RUN_DIR = os.path.join(os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}", "nightdrive-vnc-display")
KEY = os.path.join(CONF_DIR, "rsa_key.pem")   # install.sh makes it: the computer's identity, the same for every device
TICK = 15    # seconds between the checks of the addresses
FPS = 60


def log(msg):
    print(msg, flush=True)


def read_conf(name):
    conf = {}
    with open(os.path.join(CONF_DIR, name + ".conf")) as f:
        for line in f:
            if "=" in line and not line.startswith("#"):
                k, v = line.rstrip("\n").split("=", 1)
                conf[k] = v
    return conf


def out(*cmd):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=10).stdout.strip()
    except (OSError, subprocess.TimeoutExpired):
        return ""


def outputs():
    try:
        return {m["name"] for m in json.loads(out("hyprctl", "-j", "monitors", "all"))}
    except ValueError:
        return set()


def tailscale_address(family):
    return out("tailscale", "ip", family).split("\n")[0]


def home_address(uuid):
    """The computer's address on the home network (the NetworkManager connection the device was added on), or "" while
    that connection isn't the active one: never a café's network that happens to hand out the same address."""
    if not uuid:
        return ""
    return out("nmcli", "-g", "IP4.ADDRESS", "connection", "show", uuid).split(" | ")[0].split("/")[0]


def local(address):
    """The address is this computer's now: `tailscale ip` still gives it after `tailscale down`, and a wayvnc started on
    it would only exit."""
    try:
        with socket.socket(socket.AF_INET6 if ":" in address else socket.AF_INET) as s:
            s.bind((address, 0))
        return True
    except OSError:
        return False


def keyboard():
    """The desk's layout: wayvnc types with a virtual keyboard of its own, and a different layout there would switch the
    desk's keymap too as it types."""
    def opt(name):
        try:
            v = json.loads(out("hyprctl", "-j", "getoption", f"input:{name}")).get("str", "")
        except ValueError:
            v = ""
        return v.split(",")[0].strip()
    # In wayvnc's config, not its -k LAYOUT-VARIANT: a layout's own name may have a "-" (fi-viivat)
    return {"xkb_layout": opt("kb_layout"), "xkb_variant": opt("kb_variant")}


class Listener:
    """One wayvnc on one address. relax: Apple's own login (Diffie-Hellman, used by e.g. the Screens app) then leaves the
    picture unencrypted, which is fine inside Tailscale's encryption but not on the home network."""

    def __init__(self, name, kind, conf, relax):
        self.name, self.kind, self.conf, self.relax = name, kind, conf, relax
        self.proc, self.address = None, ""

    def path(self, ext):
        return os.path.join(RUN_DIR, f"{self.name}-{self.kind}.{ext}")

    def start(self, address, kb):
        # wayvnc's own config, with the password: in the runtime folder, readable only by the user (0600 from the start)
        fd = os.open(self.path("conf"), os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(fd, "w") as f:
            f.write(f"enable_auth=true\nusername={self.conf['username']}\npassword={self.conf['password']}\n"
                    f"rsa_private_key_file={KEY}\nrelax_encryption={'true' if self.relax else 'false'}\n")
            f.writelines(f"{k}={v}\n" for k, v in kb.items() if v)
        # Not -r (the pointer drawn into the picture): with it, wayvnc dies ("Fatal error while capturing") as soon as the
        # client moves the pointer onto this screen, as RealVNC does on connecting. Without it the client draws the
        # pointer itself. -R keeps the size the device was added with: a client asking for another would fight
        # virtual-display.lua.
        cmd = ["wayvnc", "-C", self.path("conf"), "-o", self.conf["output"], "-R", "-f", str(FPS),
               "-S", self.path("sock")]
        self.proc, self.address = subprocess.Popen(cmd + [address, self.conf["port"]]), address
        log(f"listening on {address}:{self.conf['port']} ({self.kind})")

    def stop(self):
        if self.proc:
            self.proc.terminate()
            try:
                self.proc.wait(3)
            except subprocess.TimeoutExpired:
                self.proc.kill()
                self.proc.wait()
            log(f"stopped listening on {self.address}:{self.conf['port']} ({self.kind})")
        self.proc, self.address = None, ""
        for ext in ("conf", "sock"):
            try:
                os.remove(self.path(ext))
            except FileNotFoundError:
                pass

    def follow(self, address, kb):
        """Listens on address, or nowhere if it is "": moved when the address changed, started again if wayvnc died."""
        if address and not local(address):
            address = ""
        if self.proc and (self.proc.poll() is not None or self.address != address):
            if self.proc.poll() is not None:
                log(f"wayvnc ({self.kind}) exited with {self.proc.returncode}")
            self.stop()
        if address and not self.proc:
            self.start(address, kb)


def events():
    sig = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE", "")
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.connect(os.path.join(os.path.dirname(RUN_DIR), "hypr", sig, ".socket2.sock"))
    return s


def removed(line, output):
    """monitorremoved>>NAME, or monitorremovedv2>>ID,NAME,DESCRIPTION"""
    ev, _, data = line.partition(">>")
    return (ev == "monitorremoved" and data == output) or (ev == "monitorremovedv2" and data.split(",")[1:2] == [output])


def main(name):
    conf = read_conf(name)
    output = conf["output"]
    os.makedirs(RUN_DIR, mode=0o700, exist_ok=True)
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
    ev = events()   # before the output is made, so its removal can't slip past
    if output not in outputs():
        out("hyprctl", "output", "create", "headless", output)
        for _ in range(20):
            if output in outputs():
                break
            time.sleep(0.25)
        else:
            log(f"couldn't make the output {output}")
            return 1
    log(f"{output} is there")
    kb = keyboard()
    listeners = [(Listener(name, "tailscale", conf, True), lambda: tailscale_address("-4")),
                 (Listener(name, "tailscale6", conf, True), lambda: tailscale_address("-6")),
                 (Listener(name, "home", conf, False), lambda: home_address(conf.get("home", "")))]
    buf, due = b"", 0.0
    try:
        while True:
            if time.monotonic() >= due:
                for listener, address in listeners:
                    listener.follow(address(), kb)
                due = time.monotonic() + TICK
            if not select.select([ev], [], [], min(1.0, max(0.0, due - time.monotonic())))[0]:
                # A wayvnc that died is started again within a second, not at the next check: the device reconnects
                if any(listener.proc and listener.proc.poll() is not None for listener, _ in listeners):
                    due = 0.0
                continue
            data = ev.recv(65536)
            if not data:
                log("Hyprland is gone")
                return 0
            *lines, buf = (buf + data).split(b"\n")
            if any(removed(line.decode(errors="replace"), output) for line in lines):
                log(f"{output} went away: stopping before wayvnc moves to another screen")
                return 1   # systemd starts it again, with a new output: `vnc-display off` is the way to end it
    finally:
        for listener, _ in listeners:
            listener.stop()
        if output in outputs():
            out("hyprctl", "output", "remove", output)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
