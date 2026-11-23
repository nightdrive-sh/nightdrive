#!/usr/bin/env python3
"""Files on the desktop's clipboard, offered as several types at once (#3304): `clipboard.py copy|cut PATH…`.

y / ⌘C and x / ⌘X in Files put the paths here. wl-copy offers one type a time, and one type can't serve everyone who
pastes: a file browser wants the files, a terminal or a text field wants the paths as text, so the one who pastes picks
the type it understands, as with Finder and Nautilus:
- x-special/gnome-copied-files: Nautilus's own, which says copy or cut; Files reads it first too (Clip.qml)
- text/uri-list: the files as file:// URLs, for other file browsers, browsers and chats
- text/plain (and the X names XWayland asks by): the paths as text, one a line (text_of below says why)

It speaks the Wayland wire protocol itself, as a data-control client (ext-data-control-v1, else wlr-data-control-v1,
the protocol wl-copy and clipboard managers use), with Python's standard library only: no new package for one helper.
Like wl-copy it stays in the background, answering whoever pastes, until something else takes the clipboard. Without
data-control (a compositor that has neither) it falls back to wl-copy with text/uri-list, as before."""

import itertools
import os
import socket
import struct
import sys
from urllib.parse import quote

TEXT_TYPES = ["text/plain;charset=utf-8", "text/plain", "UTF8_STRING", "STRING", "TEXT"]
MANAGERS = ["ext_data_control_manager_v1", "zwlr_data_control_manager_v1"]   # the same requests and events, in order


def uri(path):
    return "file://" + quote(path)


def text_of(paths):
    """The paths as text: one a line, as they are, with no newline after the last.

    One a line rather than quoted and side by side (as a drop on a terminal gives them) because that reads the same
    everywhere it is pasted: in a text field or a mail no quotes or backslashes are left over, and Claude Code takes a
    pasted line as one path, spaces and all, so a name with spaces needs nothing done to it, and several files are a
    list it reads one by one. Nothing after the last line, so a paste at a shell's prompt doesn't run it: the user
    sees the paths and adds what they need (a shell would need quotes around a name with spaces, which is theirs to
    add for the command they write)."""
    return "\n".join(paths)


def payloads(paths, cut=False):
    """Each type on offer and what it holds, in the order offered (the files first, as Nautilus does)."""
    uris = [uri(p) for p in paths]
    out = {
        "x-special/gnome-copied-files": ("cut" if cut else "copy") + "\n" + "\n".join(uris),
        "text/uri-list": "\r\n".join(uris) + "\r\n",
    }
    for t in TEXT_TYPES:
        out[t] = text_of(paths)
    return {k: v.encode() for k, v in out.items()}


# ---- The Wayland wire: a message is the object's id, then (size << 16 | opcode), then its arguments; a string is
# its length with the NUL, the bytes and padding to 4; a file descriptor travels beside, as SCM_RIGHTS

def _string(s):
    b = s.encode() + b"\0"
    return struct.pack("=I", len(b)) + b + b"\0" * (-len(b) % 4)


def _read_string(body, at):
    (n,) = struct.unpack_from("=I", body, at)
    s = body[at + 4:at + 4 + n - 1].decode(errors="replace")
    return s, at + 4 + n + (-n % 4)


class Wayland:
    def __init__(self):
        name = os.environ.get("WAYLAND_DISPLAY") or "wayland-0"
        if not name.startswith("/"):
            name = os.path.join(os.environ.get("XDG_RUNTIME_DIR", ""), name)
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.connect(name)
        self.buf = b""
        self.fds = []
        self.next_id = 2               # 1 is wl_display

    def new_id(self):
        i = self.next_id
        self.next_id += 1
        return i

    def send(self, obj, opcode, args=b""):
        self.sock.sendall(struct.pack("=II", obj, (8 + len(args)) << 16 | opcode) + args)

    def events(self):
        """Yields (object, opcode, body) as they come; a fd sent with one waits in self.fds."""
        while True:
            while len(self.buf) >= 8:
                obj, word = struct.unpack_from("=II", self.buf)
                size = word >> 16
                if len(self.buf) < size:
                    break
                body, self.buf = self.buf[8:size], self.buf[size:]
                yield obj, word & 0xFFFF, body
            data, anc, _, _ = self.sock.recvmsg(65536, socket.CMSG_SPACE(16 * 4))
            for level, kind, raw in anc:
                if level == socket.SOL_SOCKET and kind == socket.SCM_RIGHTS:
                    self.fds += list(struct.unpack("=%di" % (len(raw) // 4), raw[:len(raw) - len(raw) % 4]))
            if not data:
                raise ConnectionError("the compositor closed the connection")
            self.buf += data

    def roundtrip(self, on_event=None):
        """Waits until the compositor has handled all sent so far; a protocol error is raised."""
        cb = self.new_id()
        self.send(1, 0, struct.pack("=I", cb))                 # wl_display.sync
        for obj, op, body in self.events():
            if obj == 1 and op == 0:                           # wl_display.error
                _, code = struct.unpack_from("=II", body)
                raise RuntimeError("Wayland error %d: %s" % (code, _read_string(body, 8)[0]))
            if obj == cb and op == 0:                          # wl_callback.done
                return
            if on_event:
                on_event(obj, op, body)


def offer(data):
    """Takes the clipboard with these types. Returns what serve() needs, or None without data-control."""
    wl = Wayland()
    registry = wl.new_id()
    wl.send(1, 1, struct.pack("=I", registry))                 # wl_display.get_registry
    globals_ = {}

    def on_global(obj, op, body):
        if obj == registry and op == 0:                        # wl_registry.global
            (name,) = struct.unpack_from("=I", body)
            iface, at = _read_string(body, 4)
            globals_.setdefault(iface, (name, struct.unpack_from("=I", body, at)[0]))
    wl.roundtrip(on_global)
    manager_iface = next((m for m in MANAGERS if m in globals_), None)
    if not manager_iface or "wl_seat" not in globals_:
        return None

    def bind(iface, version):
        i = wl.new_id()
        wl.send(registry, 0, struct.pack("=I", globals_[iface][0]) + _string(iface) + struct.pack("=II", version, i))
        return i
    manager, seat = bind(manager_iface, 1), bind("wl_seat", 1)
    source, device = wl.new_id(), wl.new_id()
    wl.send(manager, 0, struct.pack("=I", source))             # create_data_source
    for mime in data:
        wl.send(source, 0, _string(mime))                      # source.offer
    wl.send(manager, 1, struct.pack("=II", device, seat))      # get_data_device
    wl.send(device, 0, struct.pack("=I", source))              # device.set_selection
    early = []                  # a paste may come before the roundtrip ends (a clipboard manager's): serve() answers it
    wl.roundtrip(lambda *e: early.append(e))
    return wl, source, device, early


def serve(wl, source, device, early, data):
    """Answers each paste until the clipboard is taken by someone else."""
    for obj, op, body in itertools.chain(early, wl.events()):
        if obj == source and op == 0:                          # source.send(mime, fd)
            mime, _ = _read_string(body, 0)
            fd = wl.fds.pop(0)
            try:
                os.write(fd, data.get(mime, b""))
            except OSError:
                pass                                           # the reader went away
            finally:
                os.close(fd)
        elif (obj == source and op == 1) or (obj == device and op == 2):   # cancelled, or the device finished
            return
        elif obj == 1 and op == 0:
            return


def daemonize():
    """Into the background, as wl-copy goes: the caller returns, and the clipboard holds no folder busy."""
    if os.fork():
        os._exit(0)
    os.setsid()
    os.chdir("/")
    null = os.open(os.devnull, os.O_RDWR)
    for fd in (0, 1, 2):
        os.dup2(null, fd)


def main(argv=None):
    argv = list(sys.argv[1:] if argv is None else argv)
    # Options only before "--": after it a name may start with a dash
    opts, paths = (argv[:argv.index("--")], argv[argv.index("--") + 1:]) if "--" in argv else (argv, [])
    foreground = "--foreground" in opts
    opts = [a for a in opts if a != "--foreground"]
    paths = opts[1:] + paths
    if not opts or opts[0] not in ("copy", "cut") or not paths:
        print("usage: clipboard.py copy|cut [--foreground] [--] PATH…", file=sys.stderr)
        return 2
    paths = [os.path.abspath(p) for p in paths]
    data = payloads(paths, opts[0] == "cut")
    try:
        taken = offer(data)
    except (OSError, RuntimeError, ConnectionError) as e:
        print("clipboard.py: %s" % e, file=sys.stderr)
        taken = None
    if not taken:
        os.execvp("wl-copy", ["wl-copy", "--type", "text/uri-list", "--", data["text/uri-list"].decode()])
    if not foreground:
        daemonize()
    try:
        serve(*taken, data)
    except (OSError, ConnectionError):
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
