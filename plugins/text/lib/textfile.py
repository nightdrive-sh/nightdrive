#!/usr/bin/env python3
"""Reads and writes a file for Text's window (plugins/text), as JSON on stdout.

  textfile.py read PATH                 {path, name, dir, text, md5, crlf, writable}; exit 2 with the reason on
                                        stderr when it isn't a text file the window can edit (binary, not UTF-8, too big)
  textfile.py write PATH [--expect MD5] [--md5 MD5] [--crlf]
                                        stdin written to PATH; --expect: only while the file is still the text whose
                                        read gave that md5 (else exit 3, written over by nothing); --md5: only if stdin
                                        is that text, whole (a cut stdin is refused); --crlf: its lines end in CR LF again
  textfile.py new PATH                  an empty file made (not over one that is there: exit 3), then read

The window shows the text with LF line ends: a file read with CR LF says so (crlf) and is written back with them, so a
Windows file stays one. md5 is of the text as the window has it (LF), so the window can compare its own text with it.

A save keeps what the file is: through a symlink (the dotfiles' config is links into the repo) the file it points at is
written, and the new file takes the old one's mode (a script stays executable). It is written beside and renamed over,
so a crash never leaves half a file.
"""
import hashlib
import json
import os
import sys
import tempfile

MAX_BYTES = 8 * 1024 * 1024        # past this a QML TextEdit crawls: such a file is a log for less, not for editing


class NotText(Exception):
    pass


def md5(text):
    return hashlib.md5(text.encode("utf-8")).hexdigest()


def decode(data):
    """The text with LF line ends, and whether it had CR LF."""
    if len(data) > MAX_BYTES:
        raise NotText(f"too big to edit here ({len(data) // (1024 * 1024)} MB)")
    if b"\0" in data:
        raise NotText("not a text file")
    try:
        text = data.decode("utf-8")
    except UnicodeDecodeError:
        raise NotText("not UTF-8 text")
    if text.startswith("﻿"):
        raise NotText("UTF-8 with a byte order mark, which saving here would lose")
    crlf = "\r\n" in text
    return (text.replace("\r\n", "\n") if crlf else text), crlf


def info(path, text, crlf):
    real = os.path.realpath(path)
    return {"path": path, "name": os.path.basename(path), "dir": os.path.dirname(path), "text": text,
            "md5": md5(text), "crlf": crlf,
            "writable": os.access(real, os.W_OK) and os.access(os.path.dirname(real), os.W_OK)}


def read(path):
    with open(path, "rb") as f:
        text, crlf = decode(f.read())
    return info(path, text, crlf)


def write(path, text, expect=None, crlf=False):
    """text (LF) into the file path points at; with expect, only while it still has that md5's text. Returns read()'s
    answer for what was written, or None when the file changed meanwhile."""
    real = os.path.realpath(path)
    if expect is not None:
        try:
            with open(real, "rb") as f:
                now, _ = decode(f.read())
        except FileNotFoundError:
            now = None
        except NotText:
            return None
        if now is None or md5(now) != expect:
            return None
    data = (text.replace("\n", "\r\n") if crlf else text).encode("utf-8")
    folder = os.path.dirname(real)
    fd, tmp = tempfile.mkstemp(prefix="." + os.path.basename(real) + ".", suffix=".tmp", dir=folder)
    try:
        with os.fdopen(fd, "wb") as f:
            f.write(data)
            f.flush()
            os.fsync(f.fileno())
        try:
            os.chmod(tmp, os.stat(real).st_mode & 0o7777)
        except FileNotFoundError:
            os.chmod(tmp, 0o666 & ~umask())
        os.replace(tmp, real)
    except BaseException:
        try:
            os.remove(tmp)
        except FileNotFoundError:
            pass
        raise
    return info(path, text, crlf)


def umask():
    mask = os.umask(0)
    os.umask(mask)
    return mask


def new(path):
    """An empty file, never over one that is there."""
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o666)
    os.close(fd)
    return read(path)


def fail(message, code=1):
    print(message, file=sys.stderr)
    sys.exit(code)


def main(args):
    if len(args) < 2 or args[0] not in ("read", "write", "new"):
        fail(__doc__.strip(), 2)
    cmd, path, opts = args[0], os.path.abspath(os.path.expanduser(args[1])), args[2:]
    name = os.path.basename(path)
    try:
        if cmd == "read":
            out = read(path)
        elif cmd == "new":
            try:
                out = new(path)
            except FileExistsError:
                fail(f"{name} is there already", 3)
        else:
            expect = opts[opts.index("--expect") + 1] if "--expect" in opts else None
            want = opts[opts.index("--md5") + 1] if "--md5" in opts else None
            text = sys.stdin.buffer.read().decode("utf-8")
            if want is not None and md5(text) != want:
                fail(f"{name} wasn't saved: the text didn't arrive whole")
            out = write(path, text, expect, "--crlf" in opts)
            if out is None:
                fail(f"{name} was changed elsewhere meanwhile", 3)
    except NotText as e:
        fail(f"Can't open {name}: {e}", 2)
    except FileNotFoundError:
        fail(f"{name} isn't there")
    except IsADirectoryError:
        fail(f"{name} is a folder")
    except PermissionError:
        fail(f"No permission to {'write' if cmd == 'write' else 'read'} {name}")
    except OSError as e:
        fail(f"{name}: {e.strerror}")
    print(json.dumps(out))


if __name__ == "__main__":
    main(sys.argv[1:])
