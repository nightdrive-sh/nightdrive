"""The receiver (localsend run, the service): answers the multicast discovery and takes sends over HTTPS (server.py).
A send needs the code shown on the screen (codes.py); files go to Downloads, a text shows in a notification."""
import hashlib
import json
import os
import re
import secrets
import select
import shutil
import socket
import struct
import subprocess
import threading
import time
import urllib.request

from codes import Codes
from common import (GROUP, PORT, certificate, clean, client_context, close_notification, follow, human, info, notify,
                    port_of, remember)

SESSION_IDLE = 300           # seconds without an upload before a session is dropped (the sender went away)
REJOIN = 30                  # seconds between multicast re-joins: a Wi-Fi reconnect drops the membership
ANNOUNCE_EVERY = 600         # seconds between own announcements (also sent at start)
TEXT_MAX = 64 * 1024         # characters of a text shown and copied


class TooBig(ValueError):
    """An upload longer than the size its prepare-upload gave (server.py answers 413)."""


def downloads():
    try:
        d = subprocess.run(["xdg-user-dir", "DOWNLOAD"], capture_output=True, text=True).stdout.strip()
    except OSError:
        d = ""
    return d if d and d != os.path.expanduser("~") else os.path.expanduser("~/Downloads")


def safe_path(root, name):
    """A file name from the sender inside root: a folder send has subfolders ("dir/file"), never "..", never absolute."""
    parts = [re.sub(r'[\x00-\x1f]', "", p).strip() for p in name.replace("\\", "/").split("/")]
    parts = [p for p in parts if p and p not in (".", "..")] or ["file"]
    return os.path.join(root, *parts)


def unique(path, taken):
    """path, or "name (2).ext" when it exists or another file of this send already has it."""
    base, ext = os.path.splitext(path)
    n = 1
    while os.path.exists(path) or path in taken:
        n += 1
        path = f"{base} ({n}){ext}"
    return path


def size_of(f):
    """A file's size as the sender gave it, or None when it isn't a whole number ≥ 0."""
    try:
        n = int(f.get("size") or 0)
    except (TypeError, ValueError):
        return None
    return n if n >= 0 else None


class Session:
    def __init__(self, sender, ip, files):
        self.id = secrets.token_hex(8)
        self.sender, self.ip = sender, ip
        self.files = files          # id → {"token", "path", "size", "sha256", "done"}
        self.touched = time.monotonic()
        self.nid = ""               # the Receiving notification

    def finished(self):
        return all(f["done"] for f in self.files.values())


class Receiver:
    def __init__(self):
        self.cert, self.key, self.fingerprint = certificate()
        self.dest = downloads()
        self.lock = threading.Lock()
        self.session = None     # the one transfer at a time (LocalSend's 409 for another)
        self.codes = Codes()

    # --- Discovery ---------------------------------------------------------------------------------------------
    def multicast(self):
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
        s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEPORT, 1)
        s.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_TTL, 1)
        s.bind(("", PORT))
        mreq = struct.pack("4s4s", socket.inet_aton(GROUP), socket.inet_aton("0.0.0.0"))
        last = 0.0
        while True:
            # Re-join every round: after a Wi-Fi reconnect the old membership is gone (dropping a missing one fails)
            for opt in (socket.IP_DROP_MEMBERSHIP, socket.IP_ADD_MEMBERSHIP):
                try:
                    s.setsockopt(socket.IPPROTO_IP, opt, mreq)
                except OSError:
                    pass
            if time.monotonic() - last > ANNOUNCE_EVERY:
                last = time.monotonic()
                self.send_multicast(s, announce=True)
            if not select.select([s], [], [], REJOIN)[0]:
                continue
            data, (ip, _) = s.recvfrom(65535)
            try:
                msg = json.loads(data)
            except ValueError:
                continue
            if not isinstance(msg, dict) or msg.get("fingerprint") == self.fingerprint:
                continue
            remember(ip, msg, self.fingerprint)
            if msg.get("announce") or msg.get("announcement"):
                threading.Thread(target=self.reply, args=(s, ip, msg), daemon=True).start()

    def send_multicast(self, s, announce):
        d = info()
        d.update({"announce": announce, "announcement": announce})   # "announcement": LocalSend before 2.0
        try:
            s.sendto(json.dumps(d).encode(), (GROUP, PORT))
        except OSError:
            pass

    def reply(self, s, ip, msg):
        """An announcement from another device: introduce ourselves over HTTP(S), or by multicast when that fails.
        This sends only what the multicast announces anyway, so the certificate behind it isn't checked."""
        proto = msg.get("protocol") if msg.get("protocol") in ("http", "https") else "https"
        url = f"{proto}://{ip}:{port_of(msg.get('port'))}/api/localsend/v2/register"
        req = urllib.request.Request(url, json.dumps(info()).encode(), {"Content-Type": "application/json"})
        try:
            answer = json.loads(urllib.request.urlopen(req, timeout=3, context=client_context()).read(65536) or b"{}")
            if isinstance(answer, dict):
                remember(ip, dict(answer, port=msg.get("port"), protocol=proto), self.fingerprint)
        except Exception:
            self.send_multicast(s, announce=False)

    # --- Transfers ---------------------------------------------------------------------------------------------
    def current(self):
        """The session, or None once it has been idle too long (the sender went away mid-transfer)."""
        s = self.session
        if s and time.monotonic() - s.touched > SESSION_IDLE:
            self.end(s, interrupted=True)
            return None
        return s

    def prepare(self, ip, body, pin):
        """A send: (status, answer). Nothing happens before the sender has typed the code shown on the screen."""
        sender = body.get("info") if isinstance(body.get("info"), dict) else {}
        files = body.get("files")
        if not isinstance(files, dict) or not files or not all(isinstance(f, dict) for f in files.values()):
            return 400, None
        items = list(files.values())
        sizes = [size_of(f) for f in items]
        if None in sizes:
            return 400, None
        who = clean(sender.get("alias")) or ip

        with self.lock:
            s = self.current()
        if s and s.ip == ip:
            self.end(s, quiet=True)   # the same sender again: its last send failed on its side and was left open
        elif s:
            return 409, None

        # A text (LocalSend's "Text" / a shared link): one text file whose content is in the preview, nothing to upload
        text = items[0].get("preview") if len(items) == 1 and str(items[0].get("fileType", "")).startswith("text/") \
            else None
        names = [clean(os.path.basename(str(f.get("fileName") or "file")), 60) for f in items]
        total = sum(sizes)
        if text:
            what = f"{who} wants to send a text"
        else:
            what = f"{who} wants to send {names[0] if len(items) == 1 else f'{len(items)} files'} ({human(total)})"
        verdict = self.codes.check(ip, pin, what)
        if verdict != "ok":
            return {"ask": 401, "busy": 409, "wait": 429}[verdict], None
        room = shutil.disk_usage(self.dest if os.path.isdir(self.dest) else os.path.expanduser("~")).free
        if not text and total > room:
            notify(f"No room for {names[0] if len(items) == 1 else f'{len(items)} files'} from {who}",
                   f"{human(total)} doesn't fit in {os.path.basename(self.dest)}", urgency="normal")
            return 507, None

        if text:
            text = str(text)[:TEXT_MAX]
            p, _ = notify(f"Text from {who}", text, actions=[("copy", "Copy")])
            follow(p, {"copy": lambda: subprocess.run(["wl-copy", "--", text])})
            return 204, None
        taken, out = set(), {}
        for (fid, f), size in zip(files.items(), sizes):
            path = unique(safe_path(self.dest, str(f.get("fileName") or fid)), taken)
            taken.add(path)
            out[str(fid)] = {"token": secrets.token_hex(16), "path": path, "size": size,
                             "sha256": str(f.get("sha256") or "").lower(), "done": False}
        s = Session(who, ip, out)
        with self.lock:
            if self.current():
                return 409, None
            self.session = s
        # Shown until the files are in, then replaced by Received (end)
        _, s.nid = notify(f"Receiving from {who}",
                          ", ".join(names[:4]) + (f" and {len(names) - 4} more" if len(names) > 4 else ""), timeout=0)
        return 200, {"sessionId": s.id, "files": {fid: f["token"] for fid, f in out.items()}}

    def upload(self, ip, q, length, chunks):
        """One file of the session. chunks(limit) yields the body and raises TooBig past limit bytes."""
        with self.lock:
            s = self.current()
        if not s or s.id != q.get("sessionId"):
            return 409 if s else 403
        f = s.files.get(q.get("fileId", ""))
        token = q.get("token", "").encode()
        if not f or not secrets.compare_digest(f["token"].encode(), token) or ip != s.ip or f["done"]:
            return 403
        if length is not None and length > f["size"]:
            return 413
        os.makedirs(os.path.dirname(f["path"]), exist_ok=True)
        part = f["path"] + ".part"
        h = hashlib.sha256()
        try:
            with open(part, "wb") as out:
                for chunk in chunks(f["size"]):
                    out.write(chunk)
                    h.update(chunk)
                    s.touched = time.monotonic()
        except TooBig:
            print(f"upload of {f['path']} longer than its {f['size']} bytes", flush=True)
            self.remove(part)
            return 413
        except (OSError, ValueError) as e:
            print(f"upload of {f['path']} failed: {e}", flush=True)
            self.remove(part)
            return 500
        if f["sha256"] and h.hexdigest() != f["sha256"]:
            print(f"checksum mismatch: {f['path']}", flush=True)
            self.remove(part)
            return 422
        os.replace(part, f["path"])
        f["done"] = True
        if s.finished():
            self.end(s)
        return 200

    def cancel(self, ip, q):
        self.codes.cancel(ip)
        with self.lock:
            s = self.session
        if s and s.id == q.get("sessionId") and s.ip == ip:
            self.end(s, interrupted=True)
        return 200

    def end(self, s, interrupted=False, quiet=False):
        with self.lock:
            if self.session is not s:
                return
            self.session = None
        done = [f["path"] for f in s.files.values() if f["done"]]
        for f in s.files.values():
            if not f["done"]:
                self.remove(f["path"] + ".part")
        if quiet:
            close_notification(s.nid)
            return
        if interrupted:
            notify(f"Transfer from {s.sender} stopped",
                   f"{len(done)} of {len(s.files)} files received" if done else "Nothing was saved", urgency="normal",
                   replace=s.nid)
            return
        if len(done) == 1:
            title, target = f"Received {os.path.basename(done[0])}", done[0]
        else:
            title, target = f"Received {len(done)} files", None
        p, _ = notify(title, f"From {s.sender} · {os.path.basename(self.dest)}",
                      actions=[("default", "Open"), ("show", "Show in Files")], replace=s.nid)
        show = (lambda: subprocess.Popen(["nautilus", "--select", done[0]])) if target else \
            (lambda: subprocess.Popen(["xdg-open", self.dest]))
        opener = (lambda: subprocess.Popen(["xdg-open", target])) if target else show
        follow(p, {"default": opener, "show": show})

    @staticmethod
    def remove(path):
        try:
            os.remove(path)
        except OSError:
            pass
