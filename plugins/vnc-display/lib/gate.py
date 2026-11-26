"""Who may knock (lib/listener.py), checked before the display is made: a connection makes a headless output, reloads
Hyprland and starts wayvnc, all before the VNC login, so a peer that only gets through the TCP handshake mustn't get
that far (#1926).

- The peer's address: Tailscale's own ranges on the Tailscale listeners, the home network's subnet on the home one.
  Linux takes packets for the Tailscale address on any interface (the weak host model), and Fedora Workstation's
  firewall leaves 1025-65535/tcp open, so a machine on the same Wi-Fi with a static route could otherwise reach the
  listener that offers the lighter login meant for Tailscale only. Its replies would go out through Tailscale, so the
  handshake from a spoofed 100.x address never completes.
- A rate: at most RATE connections in WINDOW seconds per peer, so one peer can't keep the display flickering on and
  off, nor lock the others out.
"""
import ipaddress
import time
from collections import deque

# Tailscale's CGNAT range and its IPv6 ULA prefix: every tailnet address is in one of them
TAILSCALE = (ipaddress.ip_network("100.64.0.0/10"), ipaddress.ip_network("fd7a:115c:a1e0::/48"))
RATE = 10      # connections a peer may open in WINDOW seconds (a device's reconnects stay well under it)
WINDOW = 60


def subnet(interface):
    """The network of an address with its prefix ("192.168.1.20/24", as nmcli gives it), as a tuple for allowed(), or
    () when it can't be read: then nobody is let in."""
    try:
        return (ipaddress.ip_interface(interface).network,)
    except ValueError:
        return ()


def allowed(host, networks):
    """The peer's address (as accept() gives it: an IPv6 one may carry a %scope) is in one of the networks."""
    try:
        ip = ipaddress.ip_address(host.split("%")[0])
    except ValueError:
        return False
    if ip.version == 6 and ip.ipv4_mapped:
        ip = ip.ipv4_mapped
    return any(ip.version == n.version and ip in n for n in networks)


class Rate:
    """RATE connections per WINDOW seconds per peer address. Only peers that passed allowed() are counted, so a peer
    out of range can't use up anyone's share, and the table stays as small as the tailnet."""

    def __init__(self, rate=RATE, window=WINDOW, clock=time.monotonic):
        self.rate, self.window, self.clock = rate, window, clock
        self.seen = {}   # host: deque of the times of its connections within the window

    def allow(self, host):
        now = self.clock()
        for h in [h for h, times in self.seen.items() if times[-1] <= now - self.window]:
            del self.seen[h]   # nothing from it within the window: forgotten
        times = self.seen.setdefault(host, deque())
        while times and times[0] <= now - self.window:
            times.popleft()
        if len(times) >= self.rate:
            return False
        times.append(now)
        return True
