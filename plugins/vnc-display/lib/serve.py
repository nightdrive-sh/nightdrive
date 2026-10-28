#!/usr/bin/python3
"""One device's screen, as nightdrive-vnc-display@NAME.service runs it (`vnc-display run NAME`).

Listens for the device on each of the Tailscale addresses (IPv4 and IPv6: the computer's Tailscale name gives both, and
a device may try either), and on the home network's address while the computer is on that network, if the device was
added with --home. The addresses are checked every TICK seconds, so a Tailscale that comes up later, or a move to another
network, is followed.

The display is there only while the device is connected: a screen nobody watches would hide its windows and catch the
pointer. So this listens itself (lib/listener.py), and when a device connects, makes the headless output (its size,
place and workspace come from config/hypr/virtual-display.lua, which reads the same state file at the reload the new
output brings), starts wayvnc on it and relays the connection to it. Once no connection is left for GRACE seconds,
wayvnc stops, the windows on the display go to workspace 1, and the output is removed: its icon leaves the top bar.

The output going away while it's in use stops wayvnc at once: it would otherwise move to the desk's own screen ("Selected
output went away, rotating to previous output") and show it to the device. Hyprland's event socket tells us.
"""
import json
import os
import select
import signal
import socket
import subprocess
import sys
import time

from listener import Listener

CONF_DIR = os.path.join(os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config"), "nightdrive", "vnc-display")
RUN_DIR = os.path.join(os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}", "nightdrive-vnc-display")
STATE = os.path.expanduser("~/.local/state/nightdrive/virtual-displays")   # bin/vnc-display, virtual-display.lua
KEY = os.path.join(CONF_DIR, "rsa_key.pem")   # install.sh makes it: the computer's identity, the same for every device
TICK = 15    # seconds between the checks of the addresses
GRACE = 5    # seconds the display waits for the device once its last connection is gone: a reconnect doesn't flicker it
SETTLE = 0.3   # seconds after the display has its workspace before wayvnc starts on it (make_output)
MAIN_WORKSPACE = 1   # where the display's windows go when it goes: the main screen's, as virtual-display.lua keeps it
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


def events():
    sig = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE", "")
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.connect(os.path.join(os.path.dirname(RUN_DIR), "hypr", sig, ".socket2.sock"))
    return s


def removed(line, output):
    """monitorremoved>>NAME, or monitorremovedv2>>ID,NAME,DESCRIPTION"""
    ev, _, data = line.partition(">>")
    return (ev == "monitorremoved" and data == output) or (ev == "monitorremovedv2" and data.split(",")[1:2] == [output])


def wanted(output):
    """What the state file gives the output once Hyprland has set it up: (width, height, scale, workspace), or None."""
    try:
        with open(STATE) as f:
            for line in f:
                w = line.split()
                if len(w) >= 5 and w[0] == output:
                    width, height = w[1].split("@")[0].split("x")
                    return int(width), int(height), float(w[2]), int(w[4])
    except (OSError, ValueError):
        pass
    return None


def current(output):
    """The same as Hyprland has it now, or None while the output isn't there."""
    try:
        for m in json.loads(out("hyprctl", "-j", "monitors", "all")):
            if m["name"] == output:
                return m["width"], m["height"], float(m["scale"]), m["activeWorkspace"]["id"]
    except (ValueError, KeyError, TypeError):
        pass
    return None


def make_output(output):
    """The output, once Hyprland has settled it: a new output reloads the config and moves the workspaces
    (hyprland.lua's monitor.added), and wayvnc capturing then, as the client moves its pointer, dies ("Fatal error while
    capturing", #1801). A headless output also comes at a size of its own, the device's only after the reload. So
    wayvnc waits for the output to have its size, scale and workspace, and SETTLE more; the device waits on the socket
    meanwhile."""
    start = time.monotonic()
    if output not in outputs():
        out("hyprctl", "output", "create", "headless", output)
    want = wanted(output)
    for _ in range(40):
        now = current(output)
        if now is not None and (want is None or now == want):
            log(f"{output} set up in {time.monotonic() - start:.1f} s")
            time.sleep(SETTLE)
            return True
        time.sleep(0.25)
    log(f"{output} not as the state file has it after 10 s: {current(output)}, not {want}")
    return output in outputs()   # better a display than none


def remove_output(output):
    """Its windows to the main screen's workspace first, quietly (the desk's focus stays): once the output is gone,
    Hyprland would move its workspace to the desk's screen as a workspace of its own, with an icon in the bar."""
    try:
        here = {w["id"] for w in json.loads(out("hyprctl", "-j", "workspaces")) if w.get("monitor") == output}
        windows = [c["address"] for c in json.loads(out("hyprctl", "-j", "clients"))
                   if c.get("workspace", {}).get("id") in here]
    except ValueError:
        windows = []
    for a in windows:
        out("hyprctl", "dispatch",
            f'hl.dsp.window.move({{ workspace = {MAIN_WORKSPACE}, follow = false, window = "address:{a}" }})')
    if output in outputs():
        out("hyprctl", "output", "remove", output)


def main(name):
    conf = read_conf(name)
    output = conf["output"]
    os.makedirs(RUN_DIR, mode=0o700, exist_ok=True)
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
    ev = events()   # before the output is made, so its removal can't slip past
    # Left over from a run that didn't end cleanly: the display comes only with a device
    remove_output(output)
    kb = keyboard()
    listeners = [(Listener(name, "tailscale", conf, True, RUN_DIR, KEY, FPS), lambda: tailscale_address("-4")),
                 (Listener(name, "tailscale6", conf, True, RUN_DIR, KEY, FPS), lambda: tailscale_address("-6")),
                 (Listener(name, "home", conf, False, RUN_DIR, KEY, FPS), lambda: home_address(conf.get("home", "")))]
    shown, last_seen = False, 0.0   # shown: the output is there

    def hide(why):
        nonlocal shown
        for listener, _ in listeners:
            listener.stop()   # before the output goes, or wayvnc moves to the desk's screen
        remove_output(output)
        shown = False
        log(f"{why}: {output} is gone, its windows on workspace {MAIN_WORKSPACE}")

    buf, due = b"", 0.0
    try:
        while True:
            if time.monotonic() >= due:
                for listener, address in listeners:
                    listener.follow(address())
                due = time.monotonic() + TICK
            if shown:
                if any(listener.open for listener, _ in listeners):
                    last_seen = time.monotonic()
                elif time.monotonic() - last_seen > GRACE:
                    hide("the device disconnected")
            socks = [listener.sock for listener, _ in listeners if listener.sock]
            ready = select.select([ev] + socks, [], [], min(1.0, max(0.0, due - time.monotonic())))[0]
            for listener, _ in listeners:
                if not (listener.sock and listener.sock in ready):
                    continue
                client = listener.accept()
                if not client:
                    continue
                if not shown:
                    if not make_output(output):
                        log(f"a device connected, but the output {output} couldn't be made")
                        client.close()
                        continue
                    shown = True
                    log(f"a device connected: {output} is there")
                if listener.start(output, kb):
                    listener.relay(client)
                else:
                    log(f"wayvnc ({listener.kind}) didn't start")
                    client.close()
                last_seen = time.monotonic()
            if ev not in ready:
                continue
            data = ev.recv(65536)
            if not data:
                log("Hyprland is gone")
                return 0
            *lines, buf = (buf + data).split(b"\n")
            if shown and any(removed(line.decode(errors="replace"), output) for line in lines):
                hide(f"{output} went away")
    finally:
        for listener, _ in listeners:
            listener.close()
        if shown:
            remove_output(output)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
