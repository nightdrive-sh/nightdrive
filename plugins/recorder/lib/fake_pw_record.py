#!/usr/bin/env python3
"""A stand-in for pw-record in capture_test.py: writes silence to the WAV file it is given at the real rate, with a
header that says 0 bytes until SIGINT, as pw-record's does until it is stopped, and then the true size. With
FAKE_PW_FAIL set it exits at once, as pw-record does when it can't connect."""

import os
import signal
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import wav   # noqa: E402

if os.environ.get("FAKE_PW_FAIL"):
    print("error: can't connect: Host is down", file=sys.stderr)
    sys.exit(1)

args = sys.argv[1:]
rate = int(args[args.index("--rate") + 1])
channels = int(args[args.index("--channels") + 1])
path = args[-1]
stopped = False


def stop(*_):
    global stopped
    stopped = True


signal.signal(signal.SIGINT, stop)
with open(path, "wb") as f:
    f.write(wav.header(rate, channels, 16, 0))
    f.flush()
    written, began = 0, time.time()
    while not stopped:
        due = int((time.time() - began) * rate) * channels * 2
        f.write(b"\0" * (due - written))
        f.flush()
        written = due
        time.sleep(0.02)
    f.seek(0)
    f.write(wav.header(rate, channels, 16, written))
