#!/usr/bin/env python3
"""One command to a running VM, for vm-ctl (lib/qemu.sh):

    monitor.py qmp SOCKET COMMAND VM [ARGS-JSON]   qemu's own monitor (power button, quit)
    monitor.py qga SOCKET COMMAND VM [ARGS-JSON]   the guest agent inside it (shutdown, set the clock)

Prints the command's return value as JSON. Exit 1 with a line the window can show (its error line) when the socket
or the command fails; exit 3 when the guest agent doesn't answer, i.e. qemu-guest-agent isn't running in the guest:
qemu holds the socket's other end, so the connection is made and only the answer tells.
"""
import json
import random
import socket
import sys

TIMEOUT = 3     # seconds for an answer: a guest agent answers at once, or isn't there
NO_AGENT = 3


def send(f, cmd, args):
    msg = {"execute": cmd}
    if args is not None:
        msg["arguments"] = args
    f.write(json.dumps(msg) + "\n")
    f.flush()


def answer(f):
    """The next return or error, past QMP's events"""
    while True:
        line = f.readline()
        if not line:
            raise ConnectionError("closed")
        r = json.loads(line)
        if "return" in r or "error" in r:
            return r


def qmp(f, cmd, args):
    f.readline()                                # the greeting
    send(f, "qmp_capabilities", None)
    answer(f)
    send(f, cmd, args)
    return answer(f)


def qga(f, cmd, args):
    # guest-sync first: an answer left over from an earlier client must not pass for this one's
    token = random.randrange(1, 2**31)
    send(f, "guest-sync", {"id": token})
    while answer(f).get("return") != token:
        pass
    send(f, cmd, args)
    # guest-shutdown doesn't answer on success: the guest is on its way down
    if cmd == "guest-shutdown":
        return {"return": {}}
    return answer(f)


def main():
    if len(sys.argv) < 5 or sys.argv[1] not in ("qmp", "qga"):
        sys.exit(__doc__)
    kind, path, cmd, vm = sys.argv[1:5]
    args = json.loads(sys.argv[5]) if len(sys.argv) > 5 else None
    try:
        s = socket.socket(socket.AF_UNIX)
        s.settimeout(TIMEOUT)
        s.connect(path)
        r = (qmp if kind == "qmp" else qga)(s.makefile("rw"), cmd, args)
    except socket.timeout:
        if kind == "qga":
            sys.exit(NO_AGENT)
        sys.exit(f"{vm} doesn't answer: Force off pulls the plug")
    except (OSError, ValueError) as e:
        sys.exit(f"{vm} doesn't answer ({getattr(e, 'strerror', None) or e}): Force off pulls the plug")
    if "error" in r:
        sys.exit(f"{vm}: {r['error'].get('desc', r['error'])}")
    print(json.dumps(r["return"]))


main()
