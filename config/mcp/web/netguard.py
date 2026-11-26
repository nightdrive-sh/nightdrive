"""What web_download may reach (#2242, log 4035): public web servers only. Ask Claude reads web pages, and a page can
tell it to fetch an address on the user's own network (a router's admin page, a printer, a service on localhost) whose
answer would then sit in a folder of its: so http and https only, and every address a name resolves to must be a
public one, on every redirect too.

The check and the connection use the same addresses: the connection goes to the IP that was checked (the name still
goes in the Host header and TLS's SNI, and the certificate is checked against it), so a name that resolves to a public
address for the check and to 127.0.0.1 a moment later (DNS rebinding) gets nowhere.

    open_url(url, deadline) -> (http.client.HTTPResponse, final url)   follows up to REDIRECTS redirects
    BlockedError                                                       why an address may not be fetched, for Claude
"""

import http.client
import ipaddress
import socket
import ssl
import time
from urllib.parse import urljoin, urlsplit

SCHEMES = {"http": 80, "https": 443}
REDIRECTS = 5          # hops followed: a chain longer than this is more likely a loop than a file
CONNECT_TIMEOUT = 10   # seconds for one connection to open
URL_MAX = 2048         # characters: what an address longer than this carries is more than a file's name
USER_AGENT = "Mozilla/5.0 (X11; Linux) Nightdrive-download/1"   # generic: some servers refuse an empty one
# IPv6 prefixes that carry an IPv4 address inside (NAT64): what counts is the address within
NAT64 = (ipaddress.ip_network("64:ff9b::/96"), ipaddress.ip_network("64:ff9b:1::/48"))


class BlockedError(Exception):
    """The address may not be fetched; the message says why, in words for Claude and the user."""


def public(ip):
    """Whether one address is a public unicast one: not loopback, the LAN, link-local, CGNAT (a tailnet), multicast or
    reserved, and not such an address wrapped in IPv6 (mapped, 6to4, Teredo, NAT64)."""
    ip = ipaddress.ip_address(ip)
    if ip.version == 6:
        inner = ip.ipv4_mapped or ip.sixtofour or (ip.teredo[1] if ip.teredo else None)
        if inner is None and any(ip in n for n in NAT64):
            inner = ipaddress.IPv4Address(int(ip) & 0xFFFFFFFF)
        if inner is not None:
            return public(inner)
    return ip.is_global and not ip.is_multicast


def parse(url):
    """(scheme, host, port, path with query) of an address web_download may try, else BlockedError."""
    if not isinstance(url, str) or len(url) > URL_MAX:
        raise BlockedError(f"An address of at most {URL_MAX} characters is needed.")
    if any(c <= " " or c == "\x7f" or c == "\\" for c in url):   # what browsers drop or turn: which host is it?
        raise BlockedError("The address has spaces, control characters or backslashes in it.")
    parts = urlsplit(url)
    scheme = parts.scheme.lower()
    if scheme not in SCHEMES:
        raise BlockedError(f"Only http and https addresses are downloaded, not {scheme or 'this'}.")
    if parts.username is not None or parts.password is not None:
        raise BlockedError("An address with a user name or password in it isn't downloaded.")
    try:
        host, port = parts.hostname, parts.port or SCHEMES[scheme]
    except ValueError:
        raise BlockedError("The address's port isn't a number from 1 to 65535.") from None
    if not host:
        raise BlockedError("The address has no host.")
    path = parts.path or "/"
    return scheme, host, port, path + (f"?{parts.query}" if parts.query else "")


def addresses(host, port):
    """The addresses a host resolves to, all of them public, else BlockedError: one private address among public ones
    blocks the lot, as the connection could go to any of them."""
    try:
        infos = socket.getaddrinfo(host, port, type=socket.SOCK_STREAM)
    except (socket.gaierror, UnicodeError) as e:
        raise BlockedError(f"{host} couldn't be found ({e}).") from None
    found = list(dict.fromkeys(info[4][0] for info in infos))
    private = [a for a in found if not public(a)]
    if not found or private:
        raise BlockedError(f"{host} is on this computer or your own network ({private[0] if private else 'no address'}): "
                           "only public web servers are downloaded from.")
    return found


def connection(scheme, host, port, ips, timeout):
    """An HTTP(S) connection to host that opens its socket to one of the checked ips, never to a fresh lookup."""
    cls = http.client.HTTPSConnection if scheme == "https" else http.client.HTTPConnection
    kwargs = {"context": ssl.create_default_context()} if scheme == "https" else {}
    conn = cls(host, port, timeout=timeout, **kwargs)

    def to_checked(_address, timeout=CONNECT_TIMEOUT, source_address=None):
        error = None
        for ip in ips:
            try:
                sock = socket.create_connection((ip, port), min(timeout or CONNECT_TIMEOUT, CONNECT_TIMEOUT),
                                                source_address)
                sock.settimeout(timeout)
                return sock
            except OSError as e:
                error = e
        raise error or OSError("no address")

    conn._create_connection = to_checked   # http.client's own hook: HTTPS wraps this socket with host as the SNI
    return conn


def open_url(url, deadline):
    """GETs url, following redirects, each hop checked as the first. Returns (response, final url): the response's
    status is 200 and its body unread. deadline: time.monotonic() by which it must have answered."""
    for _ in range(REDIRECTS + 1):
        scheme, host, port, target = parse(url)
        ips = addresses(host, port)
        left = deadline - time.monotonic()
        if left <= 0:
            raise TimeoutError("The server took too long.")
        conn = connection(scheme, host, port, ips, left)
        conn.request("GET", target, headers={"User-Agent": USER_AGENT, "Accept-Encoding": "identity", "Accept": "*/*"})
        response = conn.getresponse()
        if response.status in (301, 302, 303, 307, 308):
            location = response.getheader("Location")
            conn.close()
            if not location:
                raise BlockedError(f"{host} redirected without saying where.")
            url = urljoin(url, location.strip())
            continue
        if response.status != 200:
            conn.close()
            raise BlockedError(f"{host} answered {response.status} {response.reason}: there was nothing to download.")
        return response, url
    raise BlockedError(f"More than {REDIRECTS} redirects: the download was given up.")
