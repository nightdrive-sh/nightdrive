#!/usr/bin/env python3
"""`nightdrive hub`: this computer's side of Nightdrive Hub (#3391), which carries apps' files between devices.

    nightdrive hub join URL [--no-timer]    remember the Hub, sync once, and sync every few minutes from then on
    nightdrive hub sync [--quiet] [--json] [--allow-deletes]
    nightdrive hub status [--json]
    nightdrive hub timer on|off             the sync every few minutes (systemd, nightdrive-hub-sync.timer)
    nightdrive hub leave                    stop syncing; every file stays on this computer

The timer runs `sync --quiet`. A Hub out of reach is normal for a laptop and isn't an error: the changes wait in the
manifest, the status says so, and the next sync sends them.
"""
import argparse
import json
import os
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import apps  # noqa: E402
import client as hubclient  # noqa: E402
import manifest as mf  # noqa: E402
import settings  # noqa: E402
import sync  # noqa: E402

TIMER = "nightdrive-hub-sync.timer"
# The timer's file in this repo. link.sh links it into ~/.config/systemd/user, and `systemctl disable` removes such a
# link along with the enablement, so "on" after "off" enables it by this path, which links it again (as bin/companion).
TIMER_SRC = os.path.join(os.path.dirname(os.path.realpath(__file__)), "..", "..", "systemd", "user", TIMER)


def now():
    return time.strftime("%Y-%m-%dT%H:%M:%S%z")


def timer(on):
    """The systemd user timer on or off. NIGHTDRIVE_HUB_NO_TIMER leaves it alone: a test with a throwaway home still
    talks to the person's real systemd, which must not start syncing their own files."""
    if os.environ.get("NIGHTDRIVE_HUB_NO_TIMER"):
        return "left alone (NIGHTDRIVE_HUB_NO_TIMER)"
    cmd = ["systemctl", "--user", "enable" if on else "disable", "--now", os.path.normpath(TIMER_SRC) if on else TIMER]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode:
        raise RuntimeError("systemctl: " + (r.stderr.strip() or "failed"))
    return "on" if on else "off"


def run_sync(allow_deletes=False):
    """Syncs every collection once and writes the status. Returns the status."""
    cfg = settings.load_config()
    if not cfg:
        raise LookupError("Not joined to a Hub: nightdrive hub join URL")
    status = settings.read_json(settings.status_file(), {}) or {}
    status.update(url=cfg["url"], last_try=now(), error=None)
    hub = hubclient.Client(cfg["url"])
    try:
        with settings.Lock():
            info = hub.info()
            if info["server"] != cfg.get("server"):
                # Another Hub at this address (the old one lost or replaced): every collection starts over, adding
                # and merging only (manifest.start), and this one is the Hub from now on
                settings.save_config(cfg["url"], info["server"])
                status["new_server"] = now()
            hub.server = info["server"]
            reports = {}
            for name, rule in apps.rules().items():
                reports[name] = sync.Sync(hub, rule, allow_deletes).run(info["server"]).as_json()
            status.update(state="ok", server=info["server"], last_ok=now(), collections=reports)
    except hubclient.Offline as e:
        status.update(state="offline", error=str(e))
    except (hubclient.HubError, hubclient.ServerChanged, OSError) as e:
        status.update(state="error", error=str(e))
    finally:
        hub.close()
    settings.write_json(settings.status_file(), status)
    return status


def pending():
    """{collection: {"changed": n, "deleted": n}}: what this computer has to send, read from the files now."""
    out = {}
    for name, rule in apps.rules().items():
        changed, gone = mf.Manifest(name).pending(mf.scan(rule.root(), rule.accept))
        out[name] = {"changed": len(changed), "deleted": len(gone)}
    return out


def summary(rep):
    if rep.get("missing"):
        return "its folder is gone, so nothing was synced (and nothing deleted on the Hub) until it is back"
    parts = []
    for key, word in (("fetched", "fetched"), ("sent", "sent"), ("deleted_here", "deleted here"),
                      ("deleted_there", "deleted on the Hub")):
        if rep[key]:
            parts.append("%d %s" % (rep[key], word))
    if rep["kept_both"]:
        parts.append("%d edited on two devices: both kept" % len(rep["kept_both"]))
    if rep["revived"]:
        parts.append("%d deleted elsewhere but edited here: kept" % len(rep["revived"]))
    if rep["skipped"]:
        parts.append("%d the Hub refused (%s)" % (len(rep["skipped"]), ", ".join(sorted(rep["skipped"]))))
    if rep["held_deletes"]:
        parts.append("%d deletions held back: nightdrive hub sync --allow-deletes sends them" % rep["held_deletes"])
    return ", ".join(parts) or "up to date"


def cmd_join(a):
    url = a.url.rstrip("/")
    hub = hubclient.Client(url)
    try:
        info = hub.info()
    except (hubclient.Offline, hubclient.HubError) as e:
        print("Can't join %s: %s" % (url, e), file=sys.stderr)
        return 1
    finally:
        hub.close()
    old = settings.load_config()
    # The id is not saved here but by the first sync, which sees it is new and starts fresh: the same path whether
    # this is the first Hub or a replacement
    settings.save_config(url, old["server"] if old and old["url"] == url else None)
    print("Joined the Hub at %s (%s)." % (url, info["server"]))
    code = cmd_sync(argparse.Namespace(quiet=False, json=False, allow_deletes=False))
    if not a.no_timer:
        print("Sync every few minutes: " + timer(True))
    return code


def cmd_sync(a):
    try:
        st = run_sync(a.allow_deletes)
    except LookupError as e:
        if a.quiet:
            return 0        # the timer of a computer that has left: nothing to do
        print(e, file=sys.stderr)
        return 1
    except settings.Busy as e:
        if not a.quiet:
            print(e)
        return 0
    if a.json:
        print(json.dumps(st, indent=1))
    elif st["state"] == "offline":
        if not a.quiet:
            print("The Hub is out of reach; the changes wait here. (%s)" % st["error"])
    elif st["state"] == "error":
        print("Sync failed: %s" % st["error"], file=sys.stderr)
    elif not a.quiet:
        for name, rep in st["collections"].items():
            print("%s: %s" % (name.capitalize(), summary(rep)))
    return 1 if st["state"] == "error" else 0


def cmd_status(a):
    cfg = settings.load_config()
    st = settings.read_json(settings.status_file(), {}) or {}
    out = {"joined": bool(cfg), "url": cfg and cfg["url"], "server": cfg and cfg.get("server"),
           "state": st.get("state"), "error": st.get("error"), "last_try": st.get("last_try"),
           "last_ok": st.get("last_ok"), "collections": st.get("collections", {}), "pending": pending()}
    if a.json:
        print(json.dumps(out, indent=1))
        return 0
    if not cfg:
        print("Not joined to a Hub (nightdrive hub join URL).")
        return 0
    print("Hub: %s" % cfg["url"])
    print("Last sync: %s%s" % (out["last_ok"] or "never",
                               "" if out["state"] in (None, "ok") else " (then %s: %s)" % (out["state"], out["error"])))
    for name, p in out["pending"].items():
        rep = out["collections"].get(name)
        line = summary(rep) if rep else "not synced yet"
        wait = p["changed"] + p["deleted"]
        print("%s: %s%s" % (name.capitalize(), line, "; %d change%s to send" % (wait, "s" * (wait != 1)) if wait
                                                       else ""))
    return 0


def cmd_timer(a):
    print("Sync every few minutes: " + timer(a.state == "on"))
    return 0


def cmd_leave(a):
    print("Sync every few minutes: " + timer(False))
    settings.forget_config()
    print("Left the Hub. Every file stays on this computer; nightdrive hub join URL joins again.")
    return 0


def main(argv=None):
    p = argparse.ArgumentParser(prog="nightdrive hub", description="Nightdrive Hub: apps' files on every device.")
    sub = p.add_subparsers(dest="command", required=True)
    j = sub.add_parser("join", help="join a Hub, sync once and every few minutes from then on")
    j.add_argument("url", help="the Hub's address, e.g. https://hub.tailnet.ts.net")
    j.add_argument("--no-timer", action="store_true", help="sync only when asked")
    j.set_defaults(fn=cmd_join)
    s = sub.add_parser("sync", help="sync now")
    s.add_argument("--quiet", action="store_true", help="say nothing unless it fails (the timer's)")
    s.add_argument("--json", action="store_true")
    s.add_argument("--allow-deletes", action="store_true", help="send deletions the guard held back")
    s.set_defaults(fn=cmd_sync)
    st = sub.add_parser("status", help="when the last sync was, and what waits to be sent")
    st.add_argument("--json", action="store_true")
    st.set_defaults(fn=cmd_status)
    t = sub.add_parser("timer", help="the sync every few minutes on or off")
    t.add_argument("state", choices=["on", "off"])
    t.set_defaults(fn=cmd_timer)
    sub.add_parser("leave", help="stop syncing; the files stay").set_defaults(fn=cmd_leave)
    a = p.parse_args(argv)
    try:
        return a.fn(a)
    except (RuntimeError, ValueError) as e:
        print(e, file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
