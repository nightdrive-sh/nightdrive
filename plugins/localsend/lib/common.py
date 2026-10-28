"""What the receiver (receiver.py) and sending (sender.py) share: the certificate, our device info, the devices seen and
the notifications."""
import hashlib
import json
import os
import re
import socket
import ssl
import subprocess
import threading
import time

PORT = 53317                 # LocalSend's port, for both the multicast discovery and HTTPS
GROUP = "224.0.0.167"        # LocalSend's multicast group
STATE = os.path.expanduser("~/.local/share/nightdrive/localsend")   # the certificate, its key and the trusted devices
APP = "LocalSend"            # the notifications' app name
ICON = "smartphone"
DEVICES = os.path.expanduser("~/.cache/nightdrive/localsend-devices.json")   # the devices seen, for sending
KEEP_DEVICES = 7 * 86400     # seconds a device seen once stays in DEVICES
ALIAS_MAX = 40               # characters of a sender's name shown (it names itself)


def alias():
    try:
        pretty = subprocess.run(["hostnamectl", "--pretty"], capture_output=True, text=True).stdout.strip()
    except OSError:
        pretty = ""
    return pretty or socket.gethostname().split(".")[0].capitalize()


def certificate():
    """The self-signed certificate (made once) and its fingerprint: the SHA-256 of the DER certificate, as LocalSend.
    It has to stay the same: the phone pins us to it."""
    cert, key = os.path.join(STATE, "cert.pem"), os.path.join(STATE, "key.pem")
    if not (os.path.exists(cert) and os.path.exists(key)):
        os.makedirs(STATE, mode=0o700, exist_ok=True)
        subprocess.run(["openssl", "req", "-x509", "-newkey", "ec", "-pkeyopt", "ec_paramgen_curve:prime256v1", "-nodes",
                        "-days", "3650", "-subj", "/CN=LocalSend User", "-keyout", key, "-out", cert],
                       check=True, capture_output=True)
        os.chmod(key, 0o600)
    with open(cert) as f:
        der = ssl.PEM_cert_to_DER_cert(f.read())
    return cert, key, fingerprint_of(der)


def fingerprint_of(der):
    return hashlib.sha256(der).hexdigest().upper()


def info(full=True):
    d = {"alias": alias(), "version": "2.1", "deviceModel": "Nightdrive", "deviceType": "desktop",
         "fingerprint": certificate()[2], "download": False}
    if full:
        d.update({"port": PORT, "protocol": "https"})
    return d


def client_context():
    """TLS for talking to another device. Its certificate is self-signed, so no CA can vouch for it: the sender checks
    it against the device's pinned fingerprint after the handshake instead (sender.connect)."""
    ctx = ssl.create_default_context()
    ctx.check_hostname, ctx.verify_mode = False, ssl.CERT_NONE
    ctx.load_cert_chain(*certificate()[:2])   # the iPhone app wants ours too (TLS "certificate required")
    return ctx


def clean(s, n=ALIAS_MAX):
    """A name a device gave itself, fit to show: one line, no control characters, not too long."""
    s = re.sub(r"[\x00-\x1f\x7f]", " ", str(s or "")).strip()
    return s if len(s) <= n else s[:n - 1] + "…"


def port_of(v):
    """A port a device gave, or LocalSend's (a broken one mustn't stop the discovery thread)."""
    try:
        p = int(v)
    except (TypeError, ValueError):
        return PORT
    return p if 0 < p < 65536 else PORT


def human(n):
    for unit in ("B", "KB", "MB", "GB"):
        if n < 1000 or unit == "GB":
            return f"{n:.0f} {unit}" if unit == "B" else f"{n:.1f} {unit}"
        n /= 1000


# --- Notifications --------------------------------------------------------------------------------------------------
def notify(summary, body="", actions=(), wait=False, timeout=None, urgency=None, replace=""):
    """A notification (replacing the one with id replace). Returns (process, its id); with actions or wait the process
    waits for a button."""
    cmd = ["notify-send", "-a", APP, "-i", ICON, "-p"] + (["-r", replace] if replace.isdigit() else [])
    if urgency:
        cmd += ["-u", urgency]
    if timeout is not None:
        cmd += ["-t", str(timeout)]
    for key, label in actions:
        cmd += ["-A", f"{key}={label}"]
    if actions or wait:
        cmd.append("--wait")
    cmd += ["--", summary, body]
    p = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
    nid = p.stdout.readline().strip()   # -p prints the id as soon as it's shown
    if not (actions or wait):
        p.wait()
    return p, nid


def close_notification(nid):
    if nid.isdigit():
        subprocess.run(["gdbus", "call", "--session", "--dest", "org.freedesktop.Notifications", "--object-path",
                        "/org/freedesktop/Notifications", "--method", "org.freedesktop.Notifications.CloseNotification",
                        nid], capture_output=True)


def answer(p, timeout):
    """The button pressed on a notification from notify(…, wait=True), or "" (closed, timed out)."""
    try:
        out, _ = p.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        p.kill()
        p.communicate()
        return ""
    return out.strip().splitlines()[-1] if out.strip() else ""


def follow(p, actions):
    """Runs the button's command when one is pressed (a background thread, so the notification can wait)."""
    def wait():
        key = answer(p, None)
        if key in actions:
            actions[key]()
    threading.Thread(target=wait, daemon=True).start()


# --- The devices seen -----------------------------------------------------------------------------------------------
_devices_lock = threading.Lock()


def load_devices():
    try:
        with open(DEVICES) as f:
            d = json.load(f)
        return d if isinstance(d, dict) else {}
    except (OSError, ValueError):
        return {}


def remember(ip, msg, own):
    """A device that announced or registered itself: kept by the fingerprint it gives, with the address it came from.
    Anyone can claim any fingerprint here; sending checks the certificate behind it (sender.connect)."""
    fp = str(msg.get("fingerprint") or ip)
    if fp == own or not msg.get("alias"):
        return
    with _devices_lock:
        devs = load_devices()
        old = devs.get(fp, {})
        proto = msg.get("protocol") if msg.get("protocol") in ("http", "https") else old.get("protocol", "https")
        devs[fp] = {"alias": clean(msg["alias"]), "deviceModel": clean(msg.get("deviceModel") or old.get("deviceModel")),
                    "deviceType": clean(msg.get("deviceType") or old.get("deviceType")), "ip": ip,
                    "port": port_of(msg.get("port") or old.get("port")), "protocol": proto, "seen": time.time()}
        devs = {k: v for k, v in devs.items() if time.time() - v.get("seen", 0) < KEEP_DEVICES}
        os.makedirs(os.path.dirname(DEVICES), exist_ok=True)
        tmp = DEVICES + ".tmp"
        with open(tmp, "w") as f:
            json.dump(devs, f, ensure_ascii=False)
        os.replace(tmp, DEVICES)
