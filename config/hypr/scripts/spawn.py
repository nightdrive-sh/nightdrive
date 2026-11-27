"""spawn(): start a child and forget it, for the long-running scripts here (net-watch, crash-report, headphones-ctl).

A bare subprocess.Popen that nobody waits for leaves a `<defunct>` child in `ps` once it exits, until Python happens to
reap it at the next Popen; in a watcher that runs all session that can be hours (#3657). Here a daemon thread waits
for each child, so it is reaped as soon as it exits, and the caller never blocks.
"""
import subprocess
import threading


def spawn(argv, **kwargs):
    """subprocess.Popen(argv, **kwargs) whose child is reaped in the background. Returns the Popen."""
    p = subprocess.Popen(argv, **kwargs)
    threading.Thread(target=p.wait, daemon=True, name=f"reap-{p.pid}").start()
    return p
