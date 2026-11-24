#!/usr/bin/env python3
"""`nightdrive backup`: this machine's disk, backed up with restic to a repository of your own (docs/backup.md).

    nightdrive backup setup REPOSITORY [--path P]… [--password-cmd CMD] [--existing] [--no-timer]
    nightdrive backup run [--due] [--quiet] [--json]
    nightdrive backup status [--json]
    nightdrive backup snapshots [--json]
    nightdrive backup check [--read-data 5%]
    nightdrive backup restore [SNAPSHOT] TARGET [--include PATH]…
    nightdrive backup timer on|off
    nightdrive backup restic ARGS…          restic itself, on this repository (mount, find, diff…)

The timer starts `run --due --quiet` every hour, and a backup runs when the last good one is DUE_HOURS old: a laptop
asleep at night or away from the network is backed up at its next chance, not skipped for a day. A repository out of
reach isn't an error until no backup has gone through in STALE_DAYS.
"""
import argparse
import fcntl
import getpass
import json
import os
import secrets
import socket
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import conf  # noqa: E402
import restic  # noqa: E402

DUE_HOURS = 20          # a backup a day, a little early so it doesn't drift later each day
STALE_DAYS = 3          # out of reach for this long: the run fails, and the unit's failure notice says so
PRUNE_DAYS = 7          # forget --prune weekly: it rewrites packs, too slow for every run
CHECK_DAYS = 30         # check --read-data-subset monthly
CHECK_SUBSET = "5%"
TAG = "nightdrive"      # Nightdrive's snapshots, the only ones its prune touches

TIMER = "nightdrive-backup.timer"
# The timer's file in this repo, enabled by its path so "on" after "off" links it again (as cli.py of the Hub)
TIMER_SRC = os.path.join(os.path.dirname(os.path.realpath(__file__)), "..", "..", "systemd", "user", TIMER)
KEYRING_LOCKED = os.path.join(os.path.dirname(os.path.realpath(__file__)), "..", "..", "quickshell", "kit",
                              "keyring.py")


class Busy(RuntimeError):
    pass


class Lock:
    """One run at a time on this machine: the timer's and one started by hand would otherwise both back up."""

    def __enter__(self):
        conf.STATE_DIR.mkdir(parents=True, exist_ok=True)
        self.f = open(conf.STATE_DIR / "lock", "w")
        try:
            fcntl.flock(self.f, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            self.f.close()
            raise Busy("A backup is already running.") from None
        return self

    def __exit__(self, *exc):
        self.f.close()


def timer(on):
    """The systemd user timer on or off. NIGHTDRIVE_BACKUP_NO_TIMER leaves it alone, for tests with a throwaway home."""
    if os.environ.get("NIGHTDRIVE_BACKUP_NO_TIMER"):
        return "left alone (NIGHTDRIVE_BACKUP_NO_TIMER)"
    cmd = ["systemctl", "--user", "enable" if on else "disable", "--now", os.path.normpath(TIMER_SRC) if on else TIMER]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode:
        raise RuntimeError("systemctl: " + (r.stderr.strip() or "failed"))
    return "on" if on else "off"


def keyring_locked(cfg):
    """True when the password comes from the keyring and it is locked (after a reboot, before the login): asking then
    would pop a prompt at night, so the run waits for the next hour."""
    if not cfg["password-cmd"].startswith("secret-tool ") or not os.path.exists(KEYRING_LOCKED):
        return False
    return subprocess.run([sys.executable, KEYRING_LOCKED], capture_output=True).returncode == 0


def due(st, hours=DUE_HOURS):
    age = conf.age_hours(st.get("last_ok"))
    return age is None or age >= hours


def stale(st):
    """No backup in STALE_DAYS (counted from the setup before the first one)."""
    age = conf.age_hours(st.get("last_ok") or st.get("setup"))
    return age is not None and age >= STALE_DAYS * 24


def run_backup(only_if_due=False):
    """One backup, then the weekly prune and the monthly check when they are due. Returns the status."""
    cfg = conf.load()
    if not cfg:
        raise LookupError("Backup isn't set up: nightdrive backup setup REPOSITORY")
    st = conf.read_status()
    if only_if_due and not due(st):
        return dict(st, skipped="not due")
    st.update(repository=cfg["repository"], last_try=conf.now(), error=None)
    st.pop("skipped", None)
    try:
        with Lock():
            if keyring_locked(cfg):
                st.update(state="waiting", error="the keyring is locked")
            else:
                restic.reachable(cfg)
                summary = restic.backup(cfg, conf.ensure_excludes(), TAG)
                st.update(state="ok", last_ok=conf.now(), summary=summary)
                if due(dict(last_ok=st.get("last_prune")), PRUNE_DAYS * 24):
                    restic.forget(cfg, TAG)
                    st["last_prune"] = conf.now()
                if due(dict(last_ok=st.get("last_check")), CHECK_DAYS * 24):
                    restic.check(cfg, CHECK_SUBSET)
                    st["last_check"] = conf.now()
    except restic.Offline as e:
        st.update(state="offline", error=str(e))
    except RuntimeError as e:        # restic missing or failing; Busy is raised to the caller
        if isinstance(e, Busy):
            raise
        st.update(state="error", error=str(e))
    conf.write_status(st)
    return st


def size(n):
    for unit in ("B", "KB", "MB", "GB"):
        if n < 1000:
            return "%.0f %s" % (n, unit) if unit == "B" else "%.1f %s" % (n, unit)
        n /= 1000
    return "%.1f TB" % n


def line(st):
    """The status in a sentence, for the terminal and Claude's backup_status."""
    if not st.get("repository"):
        return "Not set up (nightdrive backup setup REPOSITORY)."
    last = st.get("last_ok") or "never"
    s = st.get("summary") or {}
    text = "Last backup: %s" % last
    if s and st.get("last_ok"):
        text += " (%d files, %s new, %.0f s)" % (s.get("total_files_processed", 0), size(s.get("data_added", 0)),
                                                 s.get("total_duration", 0))
        if s.get("unreadable"):
            text += "; %d files couldn't be read" % s["unreadable"]
    if st.get("state") not in (None, "ok"):
        text += ". Then %s: %s" % (st["state"], st.get("error"))
    if stale(st):
        text += ". No backup in %d days or more." % STALE_DAYS
    return text


def cmd_run(a):
    try:
        st = run_backup(a.due)
    except LookupError as e:
        if a.quiet:
            return 0                    # the timer of a machine where backup was never set up or was removed
        print(e, file=sys.stderr)
        return 1
    except Busy as e:
        if not a.quiet:
            print(e)
        return 0
    if a.json:
        print(json.dumps(st, indent=1))
    elif not a.quiet or st.get("state") == "error" or (st.get("state") != "ok" and stale(st)):
        if not st.get("skipped"):
            print(line(st), file=sys.stderr if st.get("state") != "ok" else sys.stdout)
    if st.get("skipped"):
        return 0
    return 1 if st.get("state") == "error" or (st.get("state") != "ok" and stale(st)) else 0


def cmd_status(a):
    cfg = conf.load()
    st = conf.read_status()
    out = {"configured": bool(cfg), "repository": cfg and cfg["repository"], "paths": cfg and cfg["path"],
           "state": st.get("state"), "error": st.get("error"), "last_try": st.get("last_try"),
           "last_ok": st.get("last_ok"), "last_prune": st.get("last_prune"), "last_check": st.get("last_check"),
           "summary": st.get("summary"), "stale": bool(cfg) and stale(st)}
    out["line"] = line(dict(st, repository=out["repository"]))
    if a.json:
        print(json.dumps(out, indent=1))
    else:
        if cfg:
            print("Repository: %s\nPaths: %s" % (cfg["repository"], " ".join(cfg["path"])))
        print(out["line"])
    return 0


def new_password():
    return secrets.token_urlsafe(32)


def keyring_store(repository, password):
    r = subprocess.run(["secret-tool", "store", "--label", "Nightdrive backup (%s)" % repository,
                        "service", conf.KEYRING_SERVICE, "repository", repository],
                       input=password, text=True, capture_output=True)
    if r.returncode:
        raise RuntimeError("secret-tool store: " + (r.stderr.strip() or "failed"))


def keyring_clear(repository):
    subprocess.run(["secret-tool", "clear", "service", conf.KEYRING_SERVICE, "repository", repository],
                   capture_output=True)


def keyring_has(repository):
    r = subprocess.run(["secret-tool", "lookup", "service", conf.KEYRING_SERVICE, "repository", repository],
                       capture_output=True, text=True)
    return r.returncode == 0 and bool(r.stdout)


def cmd_setup(a):
    restic.binary()
    old = conf.load()
    if old and old["repository"] != a.repository and not a.force:
        print("Backup is set up for %s already: --force sets it up for %s instead." % (old["repository"], a.repository),
              file=sys.stderr)
        return 1
    text = conf.render(a.repository, a.path, a.password_cmd)
    cfg = conf.parse(text)
    cfg.update(repository=a.repository, **{"password-cmd": a.password_cmd or conf.keyring_cmd(a.repository)})
    try:
        restic.reachable(cfg)
    except restic.Offline as e:
        print("Can't reach the repository: %s" % e, file=sys.stderr)
        return 1
    # A password made or typed here goes into the keyring first, as restic reads it through password-cmd; a setup
    # that fails takes it out again, and one that was there before is left as it was
    generated, stored = None, False
    if not a.password_cmd and not keyring_has(a.repository):
        password = getpass.getpass("The repository's password: ") if a.existing else new_password()
        keyring_store(a.repository, password)
        generated, stored = (None if a.existing else password), True
    if restic.exists(cfg):
        print("Using the repository at %s." % a.repository)
    elif a.existing:
        if stored:
            keyring_clear(a.repository)
        print("Can't open the repository with that password (or there is none there).", file=sys.stderr)
        return 1
    else:
        try:
            restic.init(cfg)
        except RuntimeError as e:
            if stored:
                keyring_clear(a.repository)
            print("%s\nA repository already there? setup --existing asks for its password." % e, file=sys.stderr)
            return 1
        print("Made a new repository at %s." % a.repository)
    conf.save(text)
    excludes = conf.ensure_excludes()
    st = conf.read_status()
    if not old or old["repository"] != a.repository:
        st = {"setup": conf.now(), "repository": a.repository}
        conf.write_status(st)
    if generated:
        print("\nIts password, also in this computer's keyring. Save it in your password manager now: without it\n"
              "nothing in the backup can be read, on this computer or another.\n\n    %s\n" % generated)
    print("Settings: %s; what is left out: %s" % (conf.CONF, excludes))
    if not a.no_timer:
        print("Backup every day (checked hourly): " + timer(True))
    print("nightdrive backup run starts the first one now; the first takes long, the next only the changes.")
    return 0


def cmd_snapshots(a):
    cfg = need_cfg()
    snaps = restic.snapshots(cfg)
    if a.json:
        print(json.dumps(snaps, indent=1))
        return 0
    for s in snaps:
        print("%s  %s  %s  %s" % (s.get("short_id", s["id"][:8]), s["time"][:19].replace("T", " "), s.get("hostname"),
                                  " ".join(s.get("paths", []))))
    if not snaps:
        print("No snapshots yet.")
    return 0


def cmd_check(a):
    cfg = need_cfg()
    restic.reachable(cfg)
    restic.check(cfg, a.read_data)
    st = conf.read_status()
    st["last_check"] = conf.now()
    conf.write_status(st)
    print("The repository is sound (%s of the data read back)." % a.read_data)
    return 0


def cmd_restore(a):
    cfg = need_cfg()
    target = os.path.abspath(os.path.expanduser(a.target))
    if os.path.exists(target) and (not os.path.isdir(target) or os.listdir(target)):
        print("%s isn't an empty folder: restore into a new one, then move what you need." % target, file=sys.stderr)
        return 1
    args = ["restore", a.snapshot, "--target", target]
    for p in a.include or []:
        args += ["--include", os.path.abspath(os.path.expanduser(p))]
    restic.reachable(cfg)
    restic.run(cfg, args, capture=False)
    print("Restored into %s (the files under their full path, e.g. %s%s)." % (target, target, os.path.expanduser("~")))
    return 0


def cmd_restic(a):
    cfg = need_cfg()
    os.execve(restic.binary(), ["restic"] + a.args, restic.env(cfg))


def cmd_timer(a):
    print("Backup every day (checked hourly): " + timer(a.state == "on"))
    return 0


def need_cfg():
    cfg = conf.load()
    if not cfg:
        raise LookupError("Backup isn't set up: nightdrive backup setup REPOSITORY")
    return cfg


def main(argv=None):
    p = argparse.ArgumentParser(prog="nightdrive backup", description="This machine backed up with restic.")
    sub = p.add_subparsers(dest="command", required=True)
    s = sub.add_parser("setup", help="the repository, its password in the keyring, and the daily timer")
    s.add_argument("repository", help="e.g. sftp:storage-backup:/%s, or a folder on another disk" % socket.gethostname())
    s.add_argument("--path", action="append", help="what to back up (again for more); the home folder if none")
    s.add_argument("--password-cmd", help="a command that prints the password, instead of the keyring (op read …)")
    s.add_argument("--existing", action="store_true", help="a repository made before: ask for its password")
    s.add_argument("--no-timer", action="store_true", help="back up only when asked")
    s.add_argument("--force", action="store_true", help="replace a setup for another repository")
    s.set_defaults(fn=cmd_setup)
    r = sub.add_parser("run", help="back up now")
    r.add_argument("--due", action="store_true", help="only if the last backup is a day old (the timer's)")
    r.add_argument("--quiet", action="store_true", help="say nothing unless it fails")
    r.add_argument("--json", action="store_true")
    r.set_defaults(fn=cmd_run)
    st = sub.add_parser("status", help="the last backup, and the last try's state")
    st.add_argument("--json", action="store_true")
    st.set_defaults(fn=cmd_status)
    sn = sub.add_parser("snapshots", help="the backups kept")
    sn.add_argument("--json", action="store_true")
    sn.set_defaults(fn=cmd_snapshots)
    c = sub.add_parser("check", help="verify the repository, reading back part of its data")
    c.add_argument("--read-data", default=CHECK_SUBSET, help="how much to read back (default %s)" % CHECK_SUBSET)
    c.set_defaults(fn=cmd_check)
    rs = sub.add_parser("restore", help="a snapshot's files into an empty folder")
    rs.add_argument("snapshot", nargs="?", default="latest")
    rs.add_argument("target")
    rs.add_argument("--include", action="append", help="only this path (again for more)")
    rs.set_defaults(fn=cmd_restore)
    t = sub.add_parser("timer", help="the daily backup on or off")
    t.add_argument("state", choices=["on", "off"])
    t.set_defaults(fn=cmd_timer)
    x = sub.add_parser("restic", help="restic itself on this repository")
    x.add_argument("args", nargs=argparse.REMAINDER)
    x.set_defaults(fn=cmd_restic)
    a = p.parse_args(argv)
    try:
        return a.fn(a)
    except (LookupError, RuntimeError, ValueError) as e:
        print(e, file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
