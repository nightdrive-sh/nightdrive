"""A first look at a new wayvnc, before the device gets to it (lib/listener.py).

wayvnc 0.10 (to 0.10.2 and its master at least) starts with a blank picture at the output's logical size (2360x1640 at
scale 2 is 1180x820) and captures the screen only once a client is in. So the device's first answer (ServerInit) gives
the logical size, and the real picture resizes it right after: RealVNC on an iPad keeps the zoom it chose for the first
size and shows a quarter of the display, an iPhone gets black borders (#1820). wayvnc 0.9 made the blank picture at the
output's pixel size.

So this logs in as the device does, as a client of its own on wayvnc's unix socket, waits for the real picture's size
and leaves: wayvnc keeps that picture once capture stops, and the device's ServerInit has the right size. The login is
RSA-AES (security type 5: RSA keys, then AES-128-EAX), the one every listener offers, also the home network's.
"""
import os
import socket
import struct
import time
from hashlib import sha1

from cryptography.hazmat.primitives import cmac
from cryptography.hazmat.primitives.asymmetric import padding, rsa
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes

RSA_AES = 5
TIMEOUT = 3   # seconds for the whole look: the device waits meanwhile, and without it things are only as before
_key = None   # this client's RSA key, made once: a 2048-bit key takes a moment


def _client_key():
    global _key
    if _key is None:
        _key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    return _key


class _Eax:
    """AES-EAX as neatvnc's RSA-AES stream uses it: a 16-byte little-endian message counter as the nonce, and the
    message's 2-byte length as the associated data."""

    def __init__(self, key):
        self.key, self.count = key, 0

    def _omac(self, t, data):
        c = cmac.CMAC(algorithms.AES(self.key))
        c.update(bytes(15) + bytes([t]) + data)
        return c.finalize()

    def _nonce(self):
        n = self.count.to_bytes(16, "little")
        self.count += 1
        return self._omac(0, n)

    def seal(self, header, data):
        n = self._nonce()
        ct = Cipher(algorithms.AES(self.key), modes.CTR(n)).encryptor().update(data)
        tag = bytes(a ^ b ^ c for a, b, c in zip(n, self._omac(1, header), self._omac(2, ct)))
        return ct, tag

    def open(self, header, ct, tag):
        n = self._nonce()
        want = bytes(a ^ b ^ c for a, b, c in zip(n, self._omac(1, header), self._omac(2, ct)))
        if want != tag:
            raise ValueError("RSA-AES: message authentication failed")
        return Cipher(algorithms.AES(self.key), modes.CTR(n)).decryptor().update(ct)


class _Conn:
    def __init__(self, sock):
        self.sock, self.buf, self.enc, self.dec = sock, b"", None, None

    def raw(self, n):
        while len(self.buf) < n:
            data = self.sock.recv(65536)
            if not data:
                raise EOFError("wayvnc closed the connection")
            self.buf += data
        out, self.buf = self.buf[:n], self.buf[n:]
        return out

    def read(self, n):
        """n bytes, decrypted once the session is encrypted: messages are cut at whatever size the server wrote."""
        if not self.dec:
            return self.raw(n)
        out = getattr(self, "plain", b"")
        while len(out) < n:
            header = self.raw(2)
            length = struct.unpack(">H", header)[0]
            out += self.dec.open(header, self.raw(length), self.raw(16))
        self.plain = out[n:]
        return out[:n]

    def send(self, data):
        if self.enc:
            header = struct.pack(">H", len(data))
            ct, tag = self.enc.seal(header, data)
            data = header + ct + tag
        self.sock.sendall(data)


def _pub_bytes(key):
    """(bits, modulus, exponent) as RSA-AES sends a public key: both numbers in the modulus's length."""
    nums = key.public_numbers()
    size = (key.key_size + 7) // 8
    return struct.pack(">I", size * 8), nums.n.to_bytes(size, "big"), nums.e.to_bytes(size, "big")


def _login(c, username, password):
    c.raw(12)
    c.send(b"RFB 003.008\n")
    types = c.raw(c.raw(1)[0])
    if RSA_AES not in types:
        raise ValueError(f"no RSA-AES among the security types {list(types)}")
    c.send(bytes([RSA_AES]))

    bits = struct.unpack(">I", c.raw(4))[0]
    size = (bits + 7) // 8
    modulus, exponent = c.raw(size), c.raw(size)
    server = rsa.RSAPublicNumbers(int.from_bytes(exponent, "big"), int.from_bytes(modulus, "big")).public_key()
    server_pub = (struct.pack(">I", bits), modulus, exponent)
    mine = _client_key()
    client_pub = _pub_bytes(mine.public_key())
    c.send(b"".join(client_pub))

    length = struct.unpack(">H", c.raw(2))[0]
    server_random = mine.decrypt(c.raw(length), padding.PKCS1v15())
    client_random = os.urandom(len(server_random))
    challenge = server.encrypt(client_random, padding.PKCS1v15())
    c.send(struct.pack(">H", len(challenge)) + challenge)

    c.enc = _Eax(sha1(server_random + client_random).digest()[:16])
    c.dec = _Eax(sha1(client_random + server_random).digest()[:16])
    if c.read(20) != sha1(b"".join(server_pub + client_pub)).digest():
        raise ValueError("RSA-AES: the server's hash doesn't match")
    c.send(sha1(b"".join(client_pub + server_pub)).digest())
    c.read(1)   # the credentials' subtype: user name and password
    user, pw = username.encode(), password.encode()
    c.send(bytes([len(user)]) + user + bytes([len(pw)]) + pw)
    if struct.unpack(">I", c.read(4))[0] != 0:
        raise ValueError("wayvnc refused the login")


def _wait_for_size(c, size, want, bpp, end):
    """Asks for one pixel's update until wayvnc's size is want: neatvnc resizes with the next update after the first
    captured picture. Returns the size it got to."""
    if size == want:
        return size
    c.send(struct.pack(">BxHii", 2, 2, -308, -223) + struct.pack(">BBHHHH", 3, 0, 0, 0, 1, 1))
    while time.monotonic() < end:
        kind = c.read(1)[0]
        if kind == 0:   # FramebufferUpdate
            c.read(1)
            for _ in range(struct.unpack(">H", c.read(2))[0]):
                _, _, w, h, enc = struct.unpack(">HHHHi", c.read(12))
                if enc == -308:
                    c.read(16 * c.read(4)[0])
                elif enc != -223:
                    c.read(w * h * bpp)   # raw, the one encoding left, in ServerInit's pixel format
                if enc in (-308, -223):
                    size = w, h
                    if size == want:
                        return size
            c.send(struct.pack(">BBHHHH", 3, 1, 0, 0, 1, 1))
        elif kind == 2:   # Bell
            pass
        elif kind == 3:   # ServerCutText: the clipboard
            c.read(3)
            c.read(struct.unpack(">I", c.read(4))[0])
        else:
            raise ValueError(f"unexpected server message {kind}")
    return size


def warm_up(path, username, password, want):
    """Logs in on wayvnc's unix socket and leaves once wayvnc's size is want (the output's (width, height) in pixels), or
    after TIMEOUT. Returns what it saw, for the log: (first size, last size), or the reason it gave up."""
    end = time.monotonic() + TIMEOUT
    try:
        with socket.socket(socket.AF_UNIX) as s:
            s.settimeout(TIMEOUT)
            s.connect(path)
            c = _Conn(s)
            _login(c, username, password)
            c.send(b"\1")   # shared: never pushes anyone out
            size = struct.unpack(">HH", c.read(4))
            bpp = c.read(16)[0] // 8
            c.read(struct.unpack(">I", c.read(4))[0])
            return size, _wait_for_size(c, size, tuple(want), bpp, end)
    except (OSError, EOFError, ValueError) as e:
        return str(e) or type(e).__name__
