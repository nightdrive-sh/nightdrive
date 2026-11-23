"""sync_test's scenarios against the real Hub (github: nightdrive-hub), started on 127.0.0.1 with a throwaway data
folder: the in-memory Hub of the other tests is only as right as its reading of the protocol.

Needs the Hub's checkout: ~/Projects/nightdrive-hub, or NIGHTDRIVE_HUB_SRC. Skips itself without one (CI).

    python3 config/hub/lib/e2e_test.py
"""
import os
import re
import shutil
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import sync_test  # noqa: E402

SRC = os.environ.get("NIGHTDRIVE_HUB_SRC") or os.path.expanduser("~/Projects/nightdrive-hub")
HAVE = os.path.isfile(os.path.join(SRC, "hub", "main.py"))


def start():
    """(url, stop) of a real Hub on a free port, its data in a folder of its own that stop() removes."""
    data = tempfile.mkdtemp(prefix="hub-e2e-")
    # From its checkout, so `-m hub` finds it there (not -I, which would leave the checkout out of the path)
    env = {k: v for k, v in os.environ.items() if k != "PYTHONPATH"}
    proc = subprocess.Popen([sys.executable, "-m", "hub", "serve", "--data", os.path.join(data, "hub"),
                             "--port", "0"], cwd=SRC, env=env, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, text=True)
    line = proc.stdout.readline()
    m = re.search(r"http://127\.0\.0\.1:(\d+)", line)
    if not m:
        proc.kill()
        raise RuntimeError("The Hub didn't start: %r" % line)

    def stop():
        proc.terminate()
        proc.wait(10)
        proc.stdout.close()
        shutil.rmtree(data, ignore_errors=True)
    return "http://127.0.0.1:%s" % m.group(1), stop


@unittest.skipUnless(HAVE, "needs the Hub's checkout (%s or NIGHTDRIVE_HUB_SRC)" % SRC)
class RealHubTest(sync_test.Scenarios, unittest.TestCase):
    def start_hub(self):
        return start()


if __name__ == "__main__":
    unittest.main()
