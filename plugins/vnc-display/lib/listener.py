"""One address a device can come in on (lib/serve.py): the listening socket, and wayvnc behind it while the display is
there.

The connections are taken here and relayed to wayvnc on a unix socket of its own, not handed to wayvnc on the listening
socket: a client that is there as wayvnc starts makes it die ("ext-image-copy-capture: Failed!", then "Fatal error while
capturing"), as wayvnc begins capturing the pointer before its first capture of the screen is set up. A client that comes
~0.15 s later is fine, and the device knocks before the display, and so wayvnc, even exists. So a connection waits
here until wayvnc has had READY seconds.
"""
import functools
import os
import re
import socket
import subprocess
import threading
import time

READY = 0.5      # seconds wayvnc gets after its socket appears before a client is let through (measured: 0.15 is enough)
START_WAIT = 5   # seconds to wait for wayvnc's socket
CHUNK = 1 << 18
DES_SINCE = (0, 10)   # the first wayvnc with the old VNC password (allow_broken_crypto); 0.9 stops at an unknown key


def log(msg):
    print(msg, flush=True)


@functools.cache
def has_des():
    """macOS's Screen Sharing speaks RFB 3.3 to a server that isn't Apple's, and there only the old VNC password (DES):
    wayvnc 0.9 (neatvnc 0.9) knows neither, and the Mac says the software is incompatible (#1812)."""
    try:
        v = subprocess.run(["wayvnc", "--version"], capture_output=True, text=True, timeout=5).stdout
    except (OSError, subprocess.TimeoutExpired):
        return False
    m = re.search(r"wayvnc: v?(\d+)\.(\d+)", v)   # "wayvnc: 0.9.1", or "wayvnc: v0.10.2-bb83745 (HEAD)" from git
    return bool(m) and (int(m[1]), int(m[2])) >= DES_SINCE


def local(address):
    """The address is this computer's now: `tailscale ip` still gives it after `tailscale down`, and listening on it
    would only fail."""
    try:
        with socket.socket(socket.AF_INET6 if ":" in address else socket.AF_INET) as s:
            s.bind((address, 0))
        return True
    except OSError:
        return False


def relay(src, dst):
    """One direction of a connection; the end of either closes both, which ends the other direction too."""
    try:
        while data := src.recv(CHUNK):
            dst.sendall(data)
    except OSError:
        pass
    for s in (src, dst):
        try:
            s.shutdown(socket.SHUT_RDWR)
        except OSError:
            pass


class Listener:
    """relax: Apple's own login (Diffie-Hellman, used by e.g. the Screens app) and, with wayvnc 0.10 on, the old VNC
    password (DES, macOS's Screen Sharing: only the password's first 8 characters count) then leave the picture
    unencrypted, which is fine inside Tailscale's encryption but not on the home network."""

    def __init__(self, name, kind, conf, relax, run_dir, key, fps):
        self.name, self.kind, self.conf, self.relax = name, kind, conf, relax
        self.run_dir, self.key, self.fps = run_dir, key, fps
        self.sock, self.proc, self.address, self.since = None, None, "", 0.0
        self.lock = threading.Lock()
        self.open = 0   # connections being relayed now, by their threads

    def path(self, ext):
        return os.path.join(self.run_dir, f"{self.name}-{self.kind}.{ext}")

    def listen(self, address):
        try:
            self.sock = socket.create_server((address, int(self.conf["port"])),
                                             family=socket.AF_INET6 if ":" in address else socket.AF_INET)
        except OSError as e:
            log(f"can't listen on {address}:{self.conf['port']} ({self.kind}): {e}")
            return
        self.address = address
        log(f"listening on {address}:{self.conf['port']} ({self.kind})")

    def close(self):
        self.stop()
        if self.sock:
            self.sock.close()
            log(f"stopped listening on {self.address}:{self.conf['port']} ({self.kind})")
        self.sock, self.address = None, ""

    def follow(self, address):
        """Listens on address, or nowhere if it is "": moved when the address changed."""
        if address and not local(address):
            address = ""
        if self.sock and self.address != address:
            self.close()
        if address and not self.sock:
            self.listen(address)

    def running(self):
        return self.proc is not None and self.proc.poll() is None

    def start(self, output, kb):
        """wayvnc on the display, on its unix socket: True once it is there and has had READY seconds."""
        if self.proc and not self.running():
            log(f"wayvnc ({self.kind}) exited with {self.proc.returncode}")
            self.stop()
        if not self.proc:
            # wayvnc's own config, with the password: in the runtime folder, readable only by the user (0600 from the start)
            fd = os.open(self.path("conf"), os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
            with os.fdopen(fd, "w") as f:
                f.write(f"enable_auth=true\nusername={self.conf['username']}\npassword={self.conf['password']}\n"
                        f"rsa_private_key_file={self.key}\nrelax_encryption={'true' if self.relax else 'false'}\n")
                if self.relax and has_des():
                    f.write("allow_broken_crypto=true\n")
                f.writelines(f"{k}={v}\n" for k, v in kb.items() if v)
            try:
                os.remove(self.path("vnc"))
            except FileNotFoundError:
                pass
            # Not -r (the pointer drawn into the picture): with it, wayvnc dies ("Fatal error while capturing") as soon as
            # the client moves the pointer onto this screen. Without it the client draws the pointer itself. -R keeps the
            # size the device was added with: a client asking for another would fight virtual-display.lua.
            self.proc = subprocess.Popen(["wayvnc", "-C", self.path("conf"), "-o", output, "-R", "-f", str(self.fps),
                                          "-S", self.path("sock"), "-u", self.path("vnc")])
            end = time.monotonic() + START_WAIT
            while not os.path.exists(self.path("vnc")) and self.running() and time.monotonic() < end:
                time.sleep(0.05)
            self.since = time.monotonic()
        if not self.running() or not os.path.exists(self.path("vnc")):
            return False
        time.sleep(max(0.0, self.since + READY - time.monotonic()))
        return True

    def stop(self):
        if self.proc:
            self.proc.terminate()
            try:
                self.proc.wait(3)
            except subprocess.TimeoutExpired:
                self.proc.kill()
                self.proc.wait()
        self.proc = None
        for ext in ("conf", "sock", "vnc"):
            try:
                os.remove(self.path(ext))
            except FileNotFoundError:
                pass

    def accept(self):
        try:
            return self.sock.accept()[0]
        except OSError:
            return None

    def relay(self, client):
        """The client to wayvnc, both ways, in threads of their own; `open` counts it until it ends."""
        try:
            vnc = socket.socket(socket.AF_UNIX)
            vnc.connect(self.path("vnc"))
        except OSError as e:
            log(f"couldn't reach wayvnc ({self.kind}): {e}")
            client.close()
            return
        with self.lock:
            self.open += 1

        def run():
            back = threading.Thread(target=relay, args=(vnc, client), daemon=True)
            back.start()
            relay(client, vnc)
            back.join()
            client.close()
            vnc.close()
            with self.lock:
                self.open -= 1
        threading.Thread(target=run, daemon=True).start()
