"""The repo's unit tests for check.py: every tracked *_test.py, each run on its own as `python3 -I FILE`.

The tests are plain unittest scripts beside the code they test (config/mcp, plugins/*/lib, config/hypr/scripts),
written to be run by hand, so each runs as its own process rather than through one unittest discovery: a test that
patches a module or sys.path can't leak into another, and the report names the file that failed.

Each runs with a home of its own in a throwaway folder and without the desktop's variables (Wayland, Hyprland, the
session bus), the same on a developer's desktop as in CI's container: a test that passes only on a live desktop
fails here too, instead of passing locally and failing in CI. One that needs a desktop, a network or a live service
goes in SKIP with the reason, and is reported as skipped, never left out silently.
"""
import concurrent.futures
import os
import re
import subprocess
import sys
import tempfile
import time

# Tests CI doesn't run, by path, with the reason (a desktop, a network, a live service, or a known failure and its
# Dashboard task). Each is printed as skipped on every run.
SKIP = {}

TIMEOUT = 120  # seconds per file; the slowest (mail/lib/ids_test.py) takes ~20
# The desktop's variables, left out so a test can't reach the user's live session or tell it is on one.
DESKTOP_ENV = ("WAYLAND_DISPLAY", "DISPLAY", "HYPRLAND_INSTANCE_SIGNATURE", "DBUS_SESSION_BUS_ADDRESS",
               "XDG_RUNTIME_DIR", "XDG_CONFIG_HOME", "XDG_DATA_HOME", "XDG_STATE_HOME", "XDG_CACHE_HOME",
               "QS_CONFIG_PATH", "SWAYSOCK", "QT_QPA_PLATFORM", "QT_QPA_PLATFORMTHEME", "GDK_BACKEND")


def discover(root):
    """The *_test.py files git tracks, symlinks left out (they point at files listed themselves)."""
    out = subprocess.run(["git", "ls-files", "-z", "*_test.py"], cwd=root, capture_output=True, check=True).stdout
    return sorted(f for f in out.decode().split("\0")
                  if f and not os.path.islink(os.path.join(root, f)))


def run_one(root, f):
    """(file, ok, seconds, summary, tests skipped, output) for one test file. -v makes unittest name each skip's reason."""
    with tempfile.TemporaryDirectory(prefix="ci-test-") as home:
        env = {k: v for k, v in os.environ.items() if k not in DESKTOP_ENV and not k.startswith("PYTHON")}
        # UTC and C.UTF-8 unless set: CI's container has no zone or locale of its own, and a desktop's must not differ
        env.update(HOME=home, XDG_RUNTIME_DIR=home, TZ=env.get("TZ", "UTC"), LANG="C.UTF-8")
        start = time.monotonic()
        try:
            r = subprocess.run([sys.executable, "-I", f, "-v"], cwd=root, env=env, capture_output=True, text=True,
                               timeout=TIMEOUT, stdin=subprocess.DEVNULL)
            out, ok = r.stdout + r.stderr, r.returncode == 0
        except subprocess.TimeoutExpired as e:
            out = (e.stdout or b"").decode(errors="replace") + (e.stderr or b"").decode(errors="replace")
            out, ok = out + f"\ntimed out after {TIMEOUT} s", False
    seconds = time.monotonic() - start
    ran = re.findall(r"^Ran (\d+) tests?", out, re.M)
    skipped = re.findall(r"skipped=(\d+)", out)
    reasons = sorted(set(re.findall(r"\bskipped ['\"](.*)['\"]$", out, re.M)))
    summary = f"{ran[-1] if ran else '?'} tests" + (f", {skipped[-1]} skipped: {'; '.join(reasons)}" if skipped else "")
    return f, ok, seconds, summary, int(skipped[-1]) if skipped else 0, out


def run(root, jobs=None):
    """Run every test file, report each, and return the number that failed."""
    files = discover(root)
    for f in SKIP:
        if f not in files:
            print(f"test: SKIP lists {f}, which is no longer tracked: remove it there")
    todo = [f for f in files if f not in SKIP]
    start = time.monotonic()
    with concurrent.futures.ThreadPoolExecutor(jobs or min(8, os.cpu_count() or 2)) as pool:
        results = list(pool.map(lambda f: run_one(root, f), todo))
    bad = 0
    for f, ok, seconds, summary, _, out in results:
        print(f"test: {'ok  ' if ok else 'FAIL'} {f} ({summary}, {seconds:.1f} s)")
        if not ok:
            bad += 1
            # -v's line for each test that passed says nothing here; the failures and their tracebacks do
            lines = [line for line in out.rstrip().splitlines() if not line.endswith(" ... ok")]
            print("\n".join("  " + line for line in lines[-60:]))
    for f in sorted(SKIP):
        if f in files:
            print(f"test: skip {f}: {SKIP[f]}")
    print(f"test: {len(todo) - bad} of {len(todo)} files passed, {sum(r[4] for r in results)} tests skipped by "
          f"their own check, {len(set(SKIP) & set(files))} files left out by SKIP ({time.monotonic() - start:.0f} s)")
    return bad + sum(1 for f in SKIP if f not in files)
