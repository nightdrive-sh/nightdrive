"""Network Drives' own ssh key (netdrive key NAME|all): ssh drives that log in without 1Password's agent or any prompt.

Why (#3714): every drive mounts at login, each over its own ssh connection. With 1Password's agent each one asked
1Password to unlock at the same moment (twice for two drives, the second before the first was done), and the first try
often came before 1Password had even started. So the drives can have a key of their own:
- KEY (~/.ssh/netdrive) is made here with a random passphrase that no one types or sees. It is kept in the login
  keyring (Secret Service, through secret-tool), which the login opens, so the key file alone, on a disk or in a
  backup, is of no use.
- An ssh-agent of Network Drives' own (mountcmd.agent_socket) holds it, unlocked once per login (load) with the
  passphrase lib/askpass reads from the keyring, once the keyring is open (wait_keyring). It runs as a user unit of
  its own (AGENT_UNIT), so restarting one drive doesn't take it from the others.
- The drive's ssh gets -i KEY, IdentitiesOnly and IdentityAgent (mountcmd.ssh_command), so ~/.ssh/config stays as it
  is, and the Host's 1Password key still logs in everywhere else.
What it gives up: while the user is logged in, a program running as them can use that agent or read the keyring, as it
could a key with no passphrase, where 1Password asks for each app. So the key belongs on an account that reaches only
the drive: a Storage Box sub-account (only its own folder), read-only for a read-only drive.
"""
import fcntl
import os
import pty
import secrets
import shutil
import subprocess
import time
from pathlib import Path

import drives
import mountcmd

KEY = "~/.ssh/netdrive"                 # the key netdrive key makes; a drive's "key" names the one it uses
COMMENT = "nightdrive-netdrive"         # the public key's comment: its line in authorized_keys says what it is
AGENT_UNIT = "nightdrive-netdrive-agent"
# The keyring item holding a key's passphrase: these attributes and the key's absolute path
KEYRING = ["application", "nightdrive-netdrive", "key"]
ASKPASS = str(Path(__file__).resolve().parent / "askpass")
AGENT_WAIT = 5                          # s: the longest wait for a new agent to answer
SYSTEMD = True                          # the agent as a user unit; the tests run it as a plain process instead
UNLOCK_TIMEOUT = 15                     # s: ssh-add with the keyring's answer
# Exit 0 while the login keyring is locked or not yet there (its header says why both)
KEYRING_CHECK = str(Path(__file__).resolve().parent / "keyring-locked")
KEYRING_POLL = 2                        # s between looks while the keyring is locked
_detached = []                          # an agent started without systemd, kept so Python doesn't warn it still runs


def path(key=KEY):
    return os.path.expanduser(key)


def make(key=KEY):
    """The key, made if there is none (its passphrase into the keyring first, so a key never exists without it).
    Returns its path."""
    p = path(key)
    if os.path.exists(p):
        if not os.path.exists(p + ".pub"):
            raise drives.Refused(f"{p} has no {p}.pub beside it: move {p} away and run netdrive key again.")
        return p
    for tool in ("ssh-keygen", "secret-tool"):
        if not shutil.which(tool):
            raise drives.Refused(f"{tool} is missing (dnf install openssh-clients libsecret).")
    os.makedirs(os.path.dirname(p), mode=0o700, exist_ok=True)
    passphrase = secrets.token_urlsafe(32)
    store(p, passphrase)
    try:
        keygen(p, passphrase)
    except drives.Refused:
        subprocess.run(["secret-tool", "clear", *KEYRING, p], capture_output=True)
        raise
    return p


def store(p, passphrase):
    """The passphrase into the login keyring, given on stdin (never on a command line, which ps shows)"""
    r = subprocess.run(["secret-tool", "store", "--label", f"Network Drives: passphrase of {p}", *KEYRING, p],
                       input=passphrase, capture_output=True, text=True)
    if r.returncode != 0:
        raise drives.Refused(f"The login keyring didn't take the key's passphrase: {r.stderr.strip() or 'locked?'}")


def keygen(p, passphrase):
    """ssh-keygen under a pseudo-terminal, answering its two passphrase prompts: it reads a passphrase only from a
    terminal or its -N argument, and an argument is on show in ps to every user"""
    pid, fd = pty.fork()
    if pid == 0:
        try:
            os.execvp("ssh-keygen", ["ssh-keygen", "-q", "-t", "ed25519", "-C", COMMENT, "-f", p])
        finally:
            os._exit(127)
    out = b""
    try:
        while True:
            try:
                chunk = os.read(fd, 1024)
            except OSError:            # EIO: the child closed the terminal
                break
            if not chunk:
                break
            out += chunk
            # A prompt is answered once it is whole: ssh-keygen sets the terminal (and flushes its input) before
            # printing it, so an answer sent sooner could be thrown away
            if out.rstrip().endswith(b":") and b"assphrase" in out.rsplit(b"\n", 1)[-1]:
                os.write(fd, passphrase.encode() + b"\n")
                out = b""
    finally:
        os.close(fd)
    _, status = os.waitpid(pid, 0)
    if os.waitstatus_to_exitcode(status) != 0 or not os.path.exists(p + ".pub"):
        raise drives.Refused(f"ssh-keygen couldn't make {p}.")


def env(key=KEY):
    e = dict(os.environ, SSH_AUTH_SOCK=mountcmd.agent_socket(), SSH_ASKPASS=ASKPASS, SSH_ASKPASS_REQUIRE="force",
             NETDRIVE_KEY=path(key), NETDRIVE_KEYRING_CHECK=KEYRING_CHECK)
    e.pop("DISPLAY", None)
    return e


def agent_alive():
    """ssh-add -l: 0 with keys, 1 without, 2 when no agent answers"""
    r = subprocess.run(["ssh-add", "-l"], env=env(), capture_output=True, text=True, stdin=subprocess.DEVNULL)
    return r.returncode in (0, 1)


def start_agent():
    """The drives' agent, a user unit of its own; without systemd (the tests) a detached process"""
    sock = mountcmd.agent_socket()
    os.makedirs(os.path.dirname(sock), mode=0o700, exist_ok=True)
    try:
        os.unlink(sock)                # a dead agent's socket: ssh-agent won't start over it
    except FileNotFoundError:
        pass
    cmd = ["ssh-agent", "-D", "-a", sock]
    quiet = {"stdin": subprocess.DEVNULL, "stdout": subprocess.DEVNULL, "stderr": subprocess.DEVNULL}
    r = None
    if SYSTEMD and shutil.which("systemd-run"):
        subprocess.run(["systemctl", "--user", "stop", AGENT_UNIT], capture_output=True)   # one whose socket died
        r = subprocess.run(["systemd-run", "--user", "--quiet", "--collect", f"--unit={AGENT_UNIT}",
                            "--description=Nightdrive network drives' ssh agent", *cmd], capture_output=True)
    if r is None or r.returncode != 0:
        _detached.append(subprocess.Popen(cmd, start_new_session=True, **quiet))
    end = time.monotonic() + AGENT_WAIT
    while not agent_alive():
        if time.monotonic() > end:
            raise drives.Refused("Network Drives' ssh agent didn't start.")
        time.sleep(0.1)


def fingerprint(p):
    r = subprocess.run(["ssh-keygen", "-l", "-f", p + ".pub"], capture_output=True, text=True)
    return r.stdout.split()[1] if r.returncode == 0 and len(r.stdout.split()) > 1 else ""


def keyring_locked():
    """True while the login keyring is locked or not there yet, and when the check can't tell in time (waiting is
    safe, a prompt isn't)"""
    try:
        r = subprocess.run([KEYRING_CHECK], capture_output=True, stdin=subprocess.DEVNULL, timeout=UNLOCK_TIMEOUT)
    except subprocess.TimeoutExpired:
        return True
    return r.returncode == 0


def wait_keyring(notify=lambda text: None, sleep=time.sleep):
    """Returns once the login keyring is open (#3728). The drives start with the session, which at an autologin start
    runs under the login screen, before the password that opens the keyring (the lock's PAM): asking the keyring then
    opened gnome-keyring's own password prompt, and the drive failed when no one answered it. So a drive waits, saying
    so on its status line, however long it takes, as it waits for its host."""
    told = False
    while keyring_locked():
        if not told:
            notify("Waiting for the login keyring: your password at the login screen opens it")
            told = True
        sleep(KEYRING_POLL)


def load(key=KEY, notify=lambda text: None):
    """The key in the drives' agent, unlocked, starting the agent if it isn't running. Under a lock: every drive
    starts at login at once, and only one may start the agent. First waits for the login keyring (wait_keyring)."""
    p = path(key)
    if not os.path.exists(p + ".pub"):
        raise drives.Refused(f"The drive's key {p} is missing: netdrive key NAME makes one.")
    wait_keyring(notify)
    notify("Unlocking its key")
    os.makedirs(mountcmd.runtime_dir(), mode=0o700, exist_ok=True)
    with open(os.path.join(mountcmd.runtime_dir(), "agent.lock"), "w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        if not agent_alive():
            start_agent()
        listed = subprocess.run(["ssh-add", "-l"], env=env(key), capture_output=True, text=True,
                                stdin=subprocess.DEVNULL).stdout
        if fingerprint(p) and fingerprint(p) in listed:
            return
        try:
            r = subprocess.run(["ssh-add", "-q", p], env=env(key), capture_output=True, text=True,
                               stdin=subprocess.DEVNULL, start_new_session=True, timeout=UNLOCK_TIMEOUT)
        except subprocess.TimeoutExpired:
            r = None
        if r is None or r.returncode != 0:
            raise drives.Refused(f"The key {p} couldn't be unlocked: its passphrase isn't in the login keyring, or "
                                 f"the keyring is locked. To make a new key: move {p} and {p}.pub away, then "
                                 f"netdrive key NAME.")


def copy_id(host, key=KEY):
    """The public key into the host's authorized_keys, logging in as the Host does (1Password asks this once). -s:
    over sftp, the only way a Storage Box takes it; -f: ssh-copy-id's own check would ask for the key's passphrase."""
    r = subprocess.run(["ssh-copy-id", "-f", "-s", "-i", path(key) + ".pub", host])
    if r.returncode != 0:
        raise drives.Refused(f"ssh-copy-id couldn't add the key to {host}.")
