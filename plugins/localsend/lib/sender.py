"""Sending (localsend send, send-clipboard, send-pick): to the devices that announced themselves to the receiver
(common.DEVICES). A device is trusted by its certificate: the first send to it asks, and from then on its TLS
certificate has to match the fingerprint pinned then, before anything is sent. Anyone on the network can announce a
device under any name and fingerprint, the phone's own included; without the certificate's key it can't pass."""
import html
import http.client
import json
import mimetypes
import os
import re
import secrets
import socket
import subprocess
import time
import urllib.parse

from common import GROUP, PORT, STATE, client_context, fingerprint_of, human, info, load_devices, notify

TRUSTED = os.path.join(STATE, "trusted.json")   # fingerprint → {"alias", "deviceModel", "since"}: localsend forget
FRESH = 900                  # seconds a device counts as present after it was last seen
DISCOVER_WAIT = 2.0          # seconds a send waits for the devices to answer its announcement
SEND_ASK_TIMEOUT = 120       # seconds the phone's user has to accept a send


class Mismatch(Exception):
    """The device's certificate isn't the one its fingerprint names."""


def load_trusted():
    try:
        with open(TRUSTED) as f:
            d = json.load(f)
        return d if isinstance(d, dict) else {}
    except (OSError, ValueError):
        return {}


def trust(dev):
    t = load_trusted()
    t[dev["id"]] = {"alias": dev["alias"], "deviceModel": dev.get("deviceModel"), "since": int(time.time())}
    os.makedirs(STATE, mode=0o700, exist_ok=True)
    tmp = TRUSTED + ".tmp"
    with open(tmp, "w") as f:
        json.dump(t, f, ensure_ascii=False)
    os.replace(tmp, TRUSTED)


def forget():
    try:
        os.remove(TRUSTED)
    except FileNotFoundError:
        pass


def verifiable(dev):
    """HTTPS with a fingerprint to check the certificate against (LocalSend with encryption off has neither)."""
    return dev.get("protocol", "https") == "https" and bool(re.fullmatch(r"[0-9A-Fa-f]{64}", dev["id"]))


def discover():
    """The devices present: an announcement makes the open LocalSend apps register again with the receiver (the
    service), which keeps them in DEVICES."""
    d = dict(info(), announce=True, announcement=True)
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
    s.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_TTL, 1)
    try:
        s.sendto(json.dumps(d).encode(), (GROUP, PORT))
    except OSError:
        pass
    s.close()
    time.sleep(DISCOVER_WAIT)
    trusted = load_trusted()
    devs = load_devices()
    return sorted(({"id": k, **v, "trusted": k in trusted and verifiable({"id": k, **v})}
                   for k, v in devs.items() if time.time() - v.get("seen", 0) < FRESH), key=lambda v: -v["seen"])


def zenity(*a):
    return subprocess.run(["zenity", *a], capture_output=True, text=True)


def confirm(dev):
    """Asks before the first send to a device (and every send to one that can't be verified)."""
    where = f"{dev.get('deviceModel') or 'device'}, {dev['ip']}"
    same = [t for k, t in load_trusted().items() if t.get("alias") == dev["alias"] and k != dev["id"]]
    if not verifiable(dev):
        text = (f"{dev['alias']} ({where}) has encryption turned off in LocalSend, so this computer can't tell it from "
                "another device using its name. What you send can be read on the network.\n\nSend anyway?")
    elif same:
        text = (f"{dev['alias']} ({where}) has a different key than when you last sent to it. Either LocalSend was "
                "reinstalled there, or another device on this network is using its name.\n\n"
                "Send only if you know LocalSend was reinstalled. It will be trusted from now on.")
    else:
        text = (f"First send to {dev['alias']} ({where}).\n\nIt will be trusted from now on: a later send goes to it "
                "without asking, and another device that only takes its name is asked about again.")
    return zenity("--question", "--no-markup", "--title=Send with LocalSend", f"--text={text}", "--ok-label=Send",
                  "--cancel-label=Cancel").returncode == 0


def pick_device(status):
    """The device to send to: a lone trusted one as it is, others from a list; a new one asked about first."""
    if status != "on":      # off, or off with why and what turns it on
        notify("LocalSend is off", status[5:-1].capitalize() if status.startswith("off (") else
               "Turn it on in the launcher: Install › Plugins › LocalSend", urgency="normal")
        return None
    devs = discover()
    if not devs:
        notify("No device found", "Open LocalSend on the phone, on the same network, and try again")
        return None
    if len(devs) == 1:
        dev = devs[0]
    else:
        rows = []
        for d in devs:
            rows += [d["id"], d["alias"], (d.get("deviceModel") or "") + ("" if d["trusted"] else f" · new · {d['ip']}")]
        out = zenity("--list", "--title=Send with LocalSend", "--text=Send to", "--column=id", "--column=Device",
                     "--column=Model", "--hide-column=1", "--print-column=1", *rows).stdout.strip()
        dev = next((d for d in devs if d["id"] == out), None)
    if dev and not dev["trusted"] and not confirm(dev):
        return None
    return dev


def ask_pin(who, wrong):
    """The code the receiver shows, typed here ("" for Cancel)."""
    text = html.escape(f"{'Wrong code. ' if wrong else ''}Type the code {who} shows")   # --text is Pango markup
    return zenity("--entry", "--title=Send with LocalSend", f"--text={text}", "--ok-label=Send").stdout.strip()


def connect(dev, timeout):
    """A connection to the device whose certificate is the one its fingerprint names (Mismatch otherwise): checked
    after the handshake, before a byte of the request goes out."""
    if dev.get("protocol", "https") != "https":
        return http.client.HTTPConnection(dev["ip"], dev.get("port") or PORT, timeout=timeout)
    conn = http.client.HTTPSConnection(dev["ip"], dev.get("port") or PORT, timeout=timeout, context=client_context())
    conn.connect()
    if verifiable(dev) and fingerprint_of(conn.sock.getpeercert(binary_form=True)) != dev["id"].upper():
        conn.close()
        raise Mismatch()
    return conn


def request(dev, path, body=b"", length=None, timeout=10):
    """A POST to the device: (status, the JSON answer or None). body is bytes or an open file (sent in pieces)."""
    conn = connect(dev, timeout)
    try:
        kind = "application/octet-stream" if "/upload?" in path else "application/json"
        conn.request("POST", path, body=body,
                     headers={"Content-Type": kind, "Content-Length": str(len(body) if length is None else length)})
        res = conn.getresponse()
        data = res.read(1 << 20)
        try:
            return res.status, json.loads(data) if data else None
        except ValueError:
            return res.status, None
    finally:
        conn.close()


def send(items, dev):
    """Sends items ({"name", "size", "type", and "path" or "text"}) to dev, following it in one notification."""
    who = dev["alias"]
    files = {}
    for it in items:
        fid = secrets.token_hex(8)
        files[fid] = dict(it, id=fid)
    meta = {fid: {"id": fid, "fileName": f["name"], "size": f["size"], "fileType": f["type"], "sha256": None,
                  "preview": f.get("text")} for fid, f in files.items()}
    body = json.dumps({"info": info(), "files": meta}).encode()
    _, nid = notify(f"Waiting for {who}", "Accept on the phone (LocalSend has to be open there)", timeout=0)
    pin = ""
    while True:
        # A receiver that wants a PIN (another Nightdrive shows its code, LocalSend's "Require PIN") answers 401
        path = "/api/localsend/v2/prepare-upload" + ("?" + urllib.parse.urlencode({"pin": pin}) if pin else "")
        try:
            status, answer = request(dev, path, body, timeout=SEND_ASK_TIMEOUT)
        except Mismatch:
            notify(f"Not sent to {who}", "Its certificate doesn't match the key it gave: it may be another device "
                   "using its name. Nothing was sent.", urgency="critical", replace=nid)
            return 1
        except (OSError, http.client.HTTPException):
            notify(f"{who} didn't answer", "Open LocalSend on the phone and try again", replace=nid)
            return 1
        if not dev["trusted"] and verifiable(dev):
            trust(dev)   # it passed the certificate check and the user said yes (pick_device)
            dev["trusted"] = True
        if status != 401:
            break
        pin = ask_pin(who, wrong=bool(pin))
        if not pin:
            notify(f"Not sent to {who}", "", replace=nid)
            return 1
    if status == 204:
        notify(f"Sent to {who}", "", replace=nid)
        return 0
    if status != 200 or not isinstance(answer, dict):
        why = {403: "Declined", 409: "It's busy with another transfer", 507: "It has no room for it",
               429: "Too many wrong codes: try again in a minute"}
        notify(f"{who} didn't take it", why.get(status, f"Error {status}"), replace=nid)
        return 1
    sid, tokens = str(answer.get("sessionId", "")), answer.get("files") if isinstance(answer.get("files"), dict) else {}
    todo = [f for fid, f in files.items() if fid in tokens]   # the receiver may take only some
    for i, f in enumerate(todo, 1):
        if len(todo) > 1:
            notify(f"Sending to {who}", f"{i} of {len(todo)}: {f['name']}", replace=nid, timeout=0)
        else:
            notify(f"Sending to {who}", f"{f['name']} · {human(f['size'])}", replace=nid, timeout=0)
        q = urllib.parse.urlencode({"sessionId": sid, "fileId": f["id"], "token": str(tokens[f["id"]])})
        try:
            if "text" in f:   # a text the receiver wants uploaded after all (most show the preview and answer 204)
                status, _ = request(dev, "/api/localsend/v2/upload?" + q, f["text"].encode(), timeout=60)
            else:
                with open(f["path"], "rb") as fh:
                    status, _ = request(dev, "/api/localsend/v2/upload?" + q, fh, f["size"], timeout=60)
        except (OSError, http.client.HTTPException, Mismatch) as e:
            status = str(e) or "certificate changed"
        if status != 200:
            try:
                request(dev, "/api/localsend/v2/cancel?" + urllib.parse.urlencode({"sessionId": sid}))
            except (OSError, http.client.HTTPException, Mismatch):
                pass
            notify(f"Sending to {who} stopped", f"{f['name']}: {status}", replace=nid)
            return 1
    what = todo[0]["name"] if len(todo) == 1 else f"{len(todo)} files"
    notify(f"Sent {what} to {who}", "", replace=nid)
    return 0


def file_items(paths):
    """Files to send; a folder becomes its files, named with the folder's relative path ("Trip/IMG_1.HEIC")."""
    out = []
    for p in paths:
        p = os.path.abspath(p)
        if os.path.isdir(p):
            base = os.path.dirname(p.rstrip("/"))
            for root, _, names in os.walk(p):
                for n in sorted(names):
                    full = os.path.join(root, n)
                    out.append(file_item(full, os.path.relpath(full, base)))
        elif os.path.isfile(p):
            out.append(file_item(p, os.path.basename(p)))
    return out


def file_item(path, name):
    return {"name": name, "path": path, "size": os.path.getsize(path),
            "type": mimetypes.guess_type(path)[0] or "application/octet-stream"}


def send_files(paths, status):
    items = file_items(paths)
    if not items:
        notify("Nothing to send", "Pick files or folders")
        return 1
    dev = pick_device(status)
    return send(items, dev) if dev else 1


def send_clipboard(status):
    text = subprocess.run(["wl-paste", "--no-newline", "--type", "text"], capture_output=True, text=True).stdout
    if not text.strip():
        notify("The clipboard has no text", "Copy a text or a link first")
        return 1
    dev = pick_device(status)
    if not dev:
        return 1
    fid = secrets.token_hex(8)
    return send([{"name": fid + ".txt", "size": len(text.encode()), "type": "text/plain", "text": text}], dev)


def send_pick(status):
    out = zenity("--file-selection", "--multiple", "--separator=\n", "--title=Send with LocalSend").stdout
    paths = [p for p in out.splitlines() if p]
    return send_files(paths, status) if paths else 0
