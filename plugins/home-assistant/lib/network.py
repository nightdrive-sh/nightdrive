"""Where the token may go (#1748): which network this is, whether it is a home network the user named, and whether an
http address is really on the tailnet. lib/client.py asks it before every address it would send the token to.

A plain http address (homeassistant.local, a LAN IP) sends the token as plain text to whatever answers that name, so it
is used only on a home network. A network is known by two things that must both match: NetworkManager's connection
(a Wi-Fi profile's uuid: an evil twin with the same name would need its WPA password) and the default gateway's MAC
address (a wired network's profile is the same "Wired connection 1" for every cable). A new router means asking again.

An http address on the tailnet is safe anywhere: Tailscale encrypts its traffic. It counts only when its name resolves
to a Tailscale address and the route there goes through tailscale0, and the request is then sent to that address, so a
café's DNS can't turn `ha` into a machine of its own.

The answers are kept in ANSWERS, one network a line: "home|not<TAB>uuid<TAB>mac<TAB>name".
"""
import ipaddress
import json
import os
import socket
import subprocess
import time
import urllib.parse

HOME = os.environ["HOME"]
ANSWERS = f"{HOME}/.config/nightdrive/home-assistant-networks"
TAILNET = [ipaddress.ip_network("100.64.0.0/10"), ipaddress.ip_network("fd7a:115c:a1e0::/48")]
TAILSCALE_DEV = "tailscale0"
ARP_WAIT = 0.3   # s for the gateway's MAC to show after a nudge, when the neighbour table doesn't have it yet


def run(*cmd):
    """A command's output, "" when it fails or isn't there (a machine without NetworkManager)"""
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=3).stdout
    except (OSError, subprocess.SubprocessError):
        return ""


def ip_json(*args):
    try:
        out = json.loads(run("ip", "-j", *args) or "[]")
    except ValueError:
        return []
    return out if isinstance(out, list) else []


class Network:
    """The network the traffic goes out on: its connection's uuid and name, and its gateway's MAC"""

    def __init__(self, uuid, mac, name=""):
        self.uuid, self.mac, self.name = uuid, mac.lower(), name

    @property
    def key(self):
        return f"{self.uuid}/{self.mac}"

    def __repr__(self):
        return f"Network({self.uuid!r}, {self.mac!r}, {self.name!r})"


def default_route():
    """The main table's default route with the lowest metric (as config/hypr/scripts/net-primary picks it):
    (dev, gateway), or None. Tailscale's routes are in a table of their own."""
    routes = [r for r in ip_json("route", "show", "default", "table", "main") if r.get("dev") and r.get("gateway")]
    if not routes:
        return None
    r = min(routes, key=lambda r: r.get("metric", 0))
    return r["dev"], r["gateway"]


def gateway_mac(dev, gw):
    def lookup():
        for n in ip_json("neigh", "show", gw, "dev", dev):
            if n.get("lladdr") and "FAILED" not in n.get("state", []) and "INCOMPLETE" not in n.get("state", []):
                return n["lladdr"]
        return ""
    mac = lookup()
    if not mac:
        # Not in the table (it ages out): one datagram makes the kernel ask for it
        try:
            fam = socket.AF_INET6 if ":" in gw else socket.AF_INET
            with socket.socket(fam, socket.SOCK_DGRAM) as s:
                s.sendto(b"", (gw, 9))   # discard
        except OSError:
            return ""
        time.sleep(ARP_WAIT)
        mac = lookup()
    return mac


def current():
    """The network now, or None (none, or not a Wi-Fi or a wired one NetworkManager knows)"""
    route = default_route()
    if not route:
        return None
    dev, gw = route
    kind, uuid, name = (run("nmcli", "-g", "GENERAL.TYPE,GENERAL.CON-UUID,GENERAL.CONNECTION", "device", "show", dev)
                        .split("\n") + ["", "", ""])[:3]
    if kind not in ("wifi", "ethernet") or not uuid:
        return None
    mac = gateway_mac(dev, gw)
    return Network(uuid, mac, name) if mac else None


def answers():
    """{key: (answer, Network)}: what the user said of each network, "home" or "not\""""
    out = {}
    try:
        with open(ANSWERS) as f:
            lines = f.read().splitlines()
    except FileNotFoundError:
        return out
    for line in lines:
        parts = line.split("\t")
        if len(parts) >= 3 and parts[0] in ("home", "not"):
            n = Network(parts[1], parts[2], parts[3] if len(parts) > 3 else "")
            out[n.key] = (parts[0], n)
    return out


def answer(net):
    """"home", "not" or "" (never asked) for a Network; "" for None"""
    return answers().get(net.key, ("", None))[0] if net else ""


def is_home(net):
    return answer(net) == "home"


def remember(net, ans):
    """Saves the user's answer for this network ("home" or "not"); None forgets it"""
    kept = {k: v for k, v in answers().items() if k != net.key}
    if ans:
        kept[net.key] = (ans, net)
    os.makedirs(os.path.dirname(ANSWERS), exist_ok=True)
    tmp = ANSWERS + ".new"
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as f:
        f.write("# Home Assistant's networks (plugins/home-assistant/lib/network.py): home|not, uuid, gateway MAC, name\n")
        for a, n in kept.values():
            f.write(f"{a}\t{n.uuid}\t{n.mac}\t{n.name.replace(chr(9), ' ')}\n")
    os.replace(tmp, ANSWERS)


def host_of(url):
    p = urllib.parse.urlsplit(url)
    return p.scheme, p.hostname or "", p.port


def tailnet_ip(host, port=None):
    """The Tailscale address host resolves to, if the route there goes through tailscale0; otherwise None"""
    if host.lower().rstrip(".").endswith(".local"):
        return None   # mDNS, never the tailnet; and a name no one answers for takes nss-mdns 5 s to give up on
    try:
        infos = socket.getaddrinfo(host, port or 80, proto=socket.IPPROTO_TCP)
    except (OSError, UnicodeError):
        return None
    for info in infos:
        addr = info[4][0]
        try:
            ip = ipaddress.ip_address(addr.split("%")[0])
        except ValueError:
            continue
        if not any(ip in net for net in TAILNET):
            continue
        route = ip_json("route", "get", str(ip))
        if route and route[0].get("dev") == TAILSCALE_DEV:
            return str(ip)
    return None


def pinned(url, ip):
    """url with its host replaced by ip, and the Host header it had: the request goes where tailnet_ip() checked"""
    p = urllib.parse.urlsplit(url)
    host = f"[{ip}]" if ":" in ip else ip
    netloc = f"{host}:{p.port}" if p.port else host
    return urllib.parse.urlunsplit((p.scheme, netloc, p.path, p.query, p.fragment)), p.netloc


def route(url, net):
    """How the token may go to url on network net: (url to send to, Host header or None), or None when it may not.
    https always (its certificate is checked); http on the tailnet, pinned to the address checked; other http only on
    a home network."""
    scheme, host, port = host_of(url)
    if scheme == "https":
        return url, None
    if scheme != "http" or not host:
        return None
    ip = tailnet_ip(host, port)
    if ip:
        return pinned(url, ip)
    return (url, None) if is_home(net) else None


def plain(url):
    """An http address that isn't on the tailnet now: one only a home network may have"""
    scheme, host, port = host_of(url)
    return scheme == "http" and not tailnet_ip(host, port)
