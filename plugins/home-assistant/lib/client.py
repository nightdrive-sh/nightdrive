"""Talking to Home Assistant: the config, the token, and the address a request goes to (bin/home-assistant).

An address gets the token only where lib/network.py allows it (#1748): https and the tailnet anywhere, a plain http
address on a home network only. Whether an address answers is asked without the token (Home Assistant answers 401), so
looking for one sends it nowhere; the token goes only with the request itself, to the address chosen. The choice is
remembered with the network it was made on, so a new network chooses again.

On a network the user hasn't answered for, a plain address that answers (asked without the token) gets them a
notification, "Is this your home network?" (ask_home(), in the background): the answer is kept, and a home network
then uses the local address.
"""
import fcntl
import json
import os
import shlex
import subprocess
import sys
import time
import urllib.error
import urllib.request

import network

HOME = os.environ["HOME"]
CONFIG = f"{HOME}/.config/nightdrive/home-assistant"
CACHE = f"{HOME}/.cache/nightdrive/home-assistant-url"
RUNTIME = os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}"
# HA_TOKEN_CMD's answer, until logout. Never in /tmp: a file another user made there first would get the token.
TOKEN_CACHE = f"{RUNTIME}/nightdrive-ha-token"
ASKED = f"{RUNTIME}/nightdrive-ha-asked"   # the networks asked about this session (ask_home)
PROBE_TIMEOUT = 1.5      # s per address while looking for one that answers
TIMEOUT = 8              # s for a request to the chosen address
RECHECK = 300            # s: a fallback address is used this long before the preferred ones are tried again
BIN = os.path.join(os.path.dirname(os.path.dirname(os.path.realpath(__file__))), "bin", "home-assistant")


def die(msg, code=1):
    print(msg, file=sys.stderr)
    sys.exit(code)


def load_config():
    cfg = {}
    try:
        with open(CONFIG) as f:
            lines = f.read().splitlines()
    except FileNotFoundError:
        return cfg
    for line in lines:
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        v = v.strip()
        cfg[k.strip()] = " ".join(shlex.split(v)) if v else ""
    return cfg


def token(cfg):
    if cfg.get("HA_TOKEN"):
        return cfg["HA_TOKEN"]
    if not cfg.get("HA_TOKEN_CMD"):
        return ""
    # Asking 1Password every few seconds would be slow (and may prompt): keep the answer in the runtime dir
    try:
        return open(TOKEN_CACHE).read().strip()
    except FileNotFoundError:
        pass
    t = subprocess.run(["bash", "-c", cfg["HA_TOKEN_CMD"]], capture_output=True, text=True).stdout.strip()
    if t:
        try:
            fd = os.open(TOKEN_CACHE, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
            os.write(fd, t.encode())
            os.close(fd)
        except OSError:   # no runtime dir (outside a login session): asked again next time
            pass
    return t


class NoRedirect(urllib.request.HTTPRedirectHandler):
    """urllib takes the Authorization header along to a redirect's address, an http one too: none is followed"""

    def redirect_request(self, *args):
        return None


OPENER = urllib.request.build_opener(NoRedirect)


def request(base, tok, method, path, body=None, timeout=TIMEOUT, host=None):
    """base's path. No token (tok None) for asking whether it answers; host: the Host header of a pinned address"""
    data = json.dumps(body).encode() if body is not None else None
    headers = {"Content-Type": "application/json"}
    if tok:
        headers["Authorization"] = "Bearer " + tok
    if host:
        headers["Host"] = host
    req = urllib.request.Request(base.rstrip("/") + path, data=data, method=method, headers=headers)
    with OPENER.open(req, timeout=timeout) as r:
        raw = r.read().decode()
    return json.loads(raw) if raw.strip().startswith(("{", "[")) else raw


def answers(base, host=None):
    """Whether Home Assistant answers there, asked without the token: its API says 401 to that"""
    try:
        request(base, None, "GET", "/api/", timeout=PROBE_TIMEOUT, host=host)
        return True
    except urllib.error.HTTPError as e:
        e.close()
        return e.code == 401
    except Exception:
        return False


class Client:
    """The first address in HA_URLS that may have the token here and answers. A fallback (Tailscale while away) is
    re-checked after RECHECK seconds, so the local address comes back when you're home."""

    def __init__(self):
        cfg = load_config()
        self.urls = cfg.get("HA_URLS", "").split()
        self.tok = token(cfg)
        if not self.urls or not self.tok:
            die("Home Assistant isn't set up: nightdrive plugins install home-assistant", 3)
        self.net = network.current()
        self.base = self.host = None

    def cached(self):
        """The address chosen before, if it was chosen on this network and is still the one to use"""
        try:
            with open(CACHE) as f:
                url, _, key = f.read().strip().partition("\t")
            age = time.time() - os.path.getmtime(CACHE)
        except FileNotFoundError:
            return None
        if url not in self.urls or key != (self.net.key if self.net else ""):
            return None
        if url != self.urls[0] and age >= RECHECK:
            return None
        return network.route(url, self.net)

    def pick(self):
        r = self.cached()
        if r:
            return r
        skipped = []
        for u in self.urls:
            r = network.route(u, self.net)
            if r is None:
                skipped.append(u)
            elif answers(*r):
                os.makedirs(os.path.dirname(CACHE), exist_ok=True)
                with open(CACHE, "w") as f:
                    f.write(f"{u}\t{self.net.key if self.net else ''}")
                self.ask_home(skipped)
                return r
        self.ask_home(skipped)
        tried = [u for u in self.urls if u not in skipped]
        if not tried:
            die(f"Home Assistant: {', '.join(skipped)} is used only on your home network (plain http sends the "
                "token as plain text). Add Tailscale or an https address: nightdrive plugins install home-assistant", 4)
        die("Home Assistant doesn't answer at " + ", ".join(tried)
            + (f" ({', '.join(skipped)} only on your home network)" if skipped else ""), 4)

    def ask_home(self, skipped):
        """Asks in the background whether this is a home network, when there is a plain address (skipped, or after the
        one chosen) and the user hasn't answered for this network (once a session: ask-home)"""
        if not self.net or network.answer(self.net):
            return
        if not skipped and not any(u.startswith("http://") for u in self.urls):
            return
        try:
            subprocess.Popen([sys.executable, "-I", BIN, "ask-home"], stdin=subprocess.DEVNULL,
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
        except OSError:
            pass

    def call(self, method, path, body=None):
        if not self.base:
            self.base, self.host = self.pick()
        try:
            return request(self.base, self.tok, method, path, body, host=self.host)
        except urllib.error.HTTPError as e:
            # The config API wants an admin's token: its 401 says the token's user isn't one, not that it's wrong
            if e.code == 401 and not path.startswith("/api/config/"):
                die("Home Assistant refused the token (401): make a new one in HA › Profile › Security")
            raise
        except (urllib.error.URLError, TimeoutError, OSError):
            # The remembered address stopped answering (left home, Wi-Fi changed): look again once
            forget_choice()
            self.net = network.current()
            self.base, self.host = self.pick()
            return request(self.base, self.tok, method, path, body, host=self.host)


def forget_choice():
    try:
        os.remove(CACHE)
    except FileNotFoundError:
        pass


def ask_home():
    """The notification: is this network, where a plain address answers, a home network? One at a time; each network
    once a session when it was shown, and again after RECHECK when nothing answered (just joined, mDNS not ready)."""
    net = network.current()
    if not net or network.answer(net):
        return
    os.makedirs(RUNTIME, exist_ok=True)
    with open(ASKED + ".lock", "w") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError:
            return   # another one is asking
        asked = asked_now()
        if asked.get(net.key, ("", 0))[0] == "shown" or time.time() - asked.get(net.key, ("", 0))[1] < RECHECK:
            return
        plain = [u for u in load_config().get("HA_URLS", "").split() if network.plain(u)]
        found = next((u for u in plain if answers(u)), None)
        mark_asked(net, "shown" if found else "probed")
        if not found:
            return
        got = subprocess.run(
            ["notify-send", "-a", "Home Assistant", "-i", "lucide:house", "-w", "-A", "home=This is home",
             "-A", "not=Not here", f"Home Assistant on “{net.name}”?",
             f"It answers at {found} on this network. Is this your home network? Its token goes to that address "
             "as plain text, so only on your home networks; elsewhere Tailscale or https."],
            capture_output=True, text=True).stdout.strip()
        if got in ("home", "not"):
            network.remember(net, got)
            forget_choice()
            subprocess.run(["qs", "ipc", "call", "bar", "refresh"], capture_output=True)


def asked_now():
    out = {}
    try:
        with open(ASKED) as f:
            lines = f.read().splitlines()
        for line in lines:
            key, what, at = (line.split() + ["", "", "0"])[:3]
            out[key] = (what, float(at))
    except (FileNotFoundError, ValueError):
        pass
    return out


def mark_asked(net, what):
    asked = asked_now()
    asked[net.key] = (what, time.time())
    with open(ASKED, "w") as f:
        f.write("".join(f"{k} {w} {t:.0f}\n" for k, (w, t) in asked.items()))
