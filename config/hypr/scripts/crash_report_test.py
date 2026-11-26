#!/usr/bin/env python3
"""crash-report's watcher and containers (#3311): `python3 config/hypr/scripts/crash_report_test.py`. A crash in
Nightdrive's sandbox (its check's Hyprland --verify-config segfaults) gets no notification, one in another container says
so, and the desktop's own reads as before. journalctl, podman and notify-send are stubbed: nothing shows."""

import json
import os
import shutil
import subprocess
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(HERE, "crash-report")
SANDBOX_ID = "ab" * 32    # running, labelled nightdrive.sandbox
TOOLBOX_ID = "cd" * 32    # running, no such label
GONE_ID = "ef" * 32       # removed before the watcher asked

STUBS = {
    # the coredump entries in CR_CRASHES (JSON lines), then ends as the journal never does, a moment later: the
    # notifications are the watcher's daemon threads, which die with it
    "journalctl": '#!/bin/bash\ncat "$CR_CRASHES"\nsleep 1.5\n',
    "podman": """#!/bin/bash
case "$*" in
  *%s*) printf 'nightdrive-sandbox-t1\\tt1\\n' ;;
  *%s*) printf 'fedora-toolbox-44\\t<no value>\\n' ;;
  *) echo "Error: no such container" >&2; exit 125 ;;
esac""" % (SANDBOX_ID, TOOLBOX_ID),
    # keeps the title and text (the last two arguments), one per line; no action chosen
    "notify-send": '#!/bin/bash\nprintf "%s | %s\\n" "${@: -2:1}" "${@: -1}" >>"$CR_SHOWN"\n',
}


def entry(pid, comm, cgroup="/user.slice/user-1000.slice/session-2.scope", leader=None, cmdline=None, top=None):
    message = f"Process {pid} ({comm}) dumped core." + (f"\n\n#0  0x0000aaab93df9790 {top} (/usr/bin/{comm})" if top else "")
    c = {"MESSAGE": message, "COREDUMP_PID": str(pid), "COREDUMP_COMM": comm, "COREDUMP_CMDLINE": cmdline or comm,
         "COREDUMP_UID": str(os.getuid()), "COREDUMP_EXE": f"/usr/bin/{comm}", "COREDUMP_SIGNAL_NAME": "SIGSEGV",
         "COREDUMP_CGROUP": cgroup}
    if leader:
        c["COREDUMP_CONTAINER_CMDLINE"] = leader
    return c


def podman(cid):
    return f"/user.slice/user-1000.slice/user@1000.service/user.slice/libpod-{cid}.scope/container"


class Watch(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.mkdtemp()
        bin_dir = os.path.join(self.dir, "bin")
        os.mkdir(bin_dir)
        for name, body in STUBS.items():
            path = os.path.join(bin_dir, name)
            with open(path, "w") as f:
                f.write(body)
            os.chmod(path, 0o755)
        self.shown = os.path.join(self.dir, "shown")
        self.env = {"PATH": bin_dir + ":/usr/bin:/bin", "HOME": self.dir, "CR_SHOWN": self.shown,
                    "CR_CRASHES": os.path.join(self.dir, "crashes")}

    def tearDown(self):
        shutil.rmtree(self.dir)

    def watch(self, *crashes):
        with open(self.env["CR_CRASHES"], "w") as f:
            f.write("".join(json.dumps(c) + "\n" for c in crashes))
        subprocess.run([SCRIPT, "watch"], env=self.env, timeout=20, check=True)
        return self.lines()

    def lines(self):
        try:
            with open(self.shown) as f:
                return sorted(f.read().splitlines())
        except FileNotFoundError:
            return []

    def test_the_desktops_own_crash(self):
        self.assertEqual(self.watch(entry(10, "Hyprland")),
                         ["Hyprland crashed | /usr/bin/Hyprland (SIGSEGV)"])

    def test_sandbox_crashes_are_left_out(self):
        verify = "/bin/bash /home/nd/nightdrive/config/sandbox/inside check"
        shown = self.watch(entry(11, "Hyprland", podman(SANDBOX_ID), verify),
                           # removed already: its leader ran the sandbox's script
                           entry(12, "qs", podman(GONE_ID), verify))
        self.assertEqual(shown, [])

    def test_another_container_says_so(self):
        shown = self.watch(entry(13, "gedit", podman(TOOLBOX_ID), "/usr/bin/bash -l"),
                           entry(14, "vim", podman(GONE_ID), "/usr/bin/bash -l"),
                           entry(15, "less", leader="/sbin/init"))
        self.assertEqual(shown, [
            "gedit crashed in a container | /usr/bin/gedit (SIGSEGV), in container fedora-toolbox-44: not the desktop",
            "less crashed in a container | /usr/bin/less (SIGSEGV), in a container: not the desktop",
            "vim crashed in a container | /usr/bin/vim (SIGSEGV), in container efefefefefef: not the desktop",
        ])

    def test_a_containers_crash_doesnt_hold_back_the_desktops(self):
        shown = self.watch(entry(16, "Hyprland", podman(TOOLBOX_ID), "/usr/bin/bash -l"), entry(17, "Hyprland"))
        self.assertEqual(len(shown), 2)
        self.assertIn("Hyprland crashed | /usr/bin/Hyprland (SIGSEGV)", shown)

    def test_verify_configs_crash_on_the_desktop_is_harmless(self):
        # Hyprland 0.56–0.57: --verify-config segfaults after its result; the running desktop at that frame still shows
        top = "_ZN17CEventLoopManager11removeTimerEN9Hyprutils6Memory14CSharedPointerI15CEventLoopTimerEE"
        shown = self.watch(entry(18, "Hyprland", cmdline="Hyprland --verify-config -c /home/u/.config/hypr/hyprland.lua",
                                 top=top), entry(19, "Hyprland", top=top))
        self.assertEqual(shown, ["Hyprland crashed | /usr/bin/Hyprland (SIGSEGV)"])

    def test_uxplay_is_no_longer_muted_from_the_start(self):
        # GStreamer 1.28.9 fixed waylandsink's crash at every screen change (#1675): UxPlay's crash now shows. A "-NAME"
        # line left in the mute file (it unmuted a default) means nothing; a muted name still is
        muted = os.path.join(self.dir, ".local/state/nightdrive/crash-reports-muted")
        os.makedirs(os.path.dirname(muted))
        with open(muted, "w") as f:
            f.write("-gedit\nvim\n")
        shown = self.watch(entry(20, "uxplay"), entry(21, "gedit"), entry(22, "vim"))
        self.assertEqual(shown, ["gedit crashed | /usr/bin/gedit (SIGSEGV)", "uxplay crashed | /usr/bin/uxplay (SIGSEGV)"])


if __name__ == "__main__":
    unittest.main()
