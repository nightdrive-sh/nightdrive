#!/usr/bin/env python3
"""Claude's dnf transaction kept to what its card showed (#1879): `python3 config/mcp/software_test.py`. The preview's
table is read whole or not at all, the run draws only on the card's repositories, imports no signing key and leaves
what Nightdrive needs, and a plugin's card names the repositories its installer adds. dnf and pkexec are stand-ins in
PATH that print a table and leave a mark."""

import json
import os
import stat
import subprocess
import sys
import tempfile
import unittest
from importlib.machinery import SourceFileLoader
from importlib.util import module_from_spec, spec_from_loader
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
APPLY = HERE.parent / "hypr/scripts/software-apply"

TABLE = """Updating and loading repositories:
Repositories loaded.
Package                 Arch    Version          Repository      Size
Installing:
 gimp                   aarch64 2:3.0.4-1.fc44   updates     60.0 MiB
Installing dependencies:
 babl                   aarch64 0:0.1.110-1.fc44 fedora       2.0 MiB
Upgrading:
 mesa-libGL             aarch64 0:26.0.1-1.fc44  updates      1.0 MiB
   replacing mesa-libGL aarch64 0:26.0.0-1.fc44  updates      1.0 MiB
Changing reason:
 libfoo                 aarch64 0:1.0-1.fc44     @System      1.0 KiB

Transaction Summary:
 Installing:         2 packages

After this operation, 62 MiB extra will be used (install 62 MiB, remove 0 B).
Operation aborted by the user.
"""
WRAPPED = TABLE.replace(" babl                   aarch64 0:0.1.110-1.fc44 fedora       2.0 MiB\n",
                        " a-very-long-package-name-that-wrapped\n     aarch64 0:1-1 fedora 1 KiB\n")
UNKNOWN = TABLE.replace("Upgrading:\n", "Obsoleting:\n")
OUTSIDE = TABLE.replace("Installing:\n", "")
SHOWN = ["gimp · updates", "babl · fedora", "mesa-libGL · updates · upgrading"]


class Transaction(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = Path(self.tmp.name)
        self.bin = self.dir / "bin"
        self.bin.mkdir()
        self.marks = self.dir / "marks"
        self.table = self.dir / "table"
        self.table.write_text(TABLE)
        self.env = {**os.environ, "PATH": f"{self.bin}:/usr/bin:/bin", "HOME": str(self.dir),
                    "NIGHTDRIVE_MCP": "1", "NIGHTDRIVE_MCP_OPTIONS": "{}"}
        # The preview's dry run prints the table; anything else (group info) nothing
        self.stand_in("dnf", f'[[ " $* " == *" --assumeno "* ]] && cat {self.table}; exit 1')
        self.stand_in("pkexec", "exit 0")

    def tearDown(self):
        self.tmp.cleanup()

    def stand_in(self, name, body):
        f = self.bin / name
        f.write_text(f'#!/bin/bash\nprintf "%s\\n" "{name} $*" >> {self.marks}\n{body}\n')
        f.chmod(f.stat().st_mode | stat.S_IEXEC)

    def ran(self):
        return self.marks.read_text() if self.marks.exists() else ""

    def apply(self, *argv, stdin=None, env=None):
        return subprocess.run([str(APPLY), *argv], input=json.dumps(stdin) if stdin is not None else "",
                              capture_output=True, text=True, env=env or self.env)

    def test_the_whole_table_is_read(self):
        p = self.apply("preview", "install", "dnf", "gimp", "--json")
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertEqual(json.loads(p.stdout)["packages"], SHOWN)

    def test_a_row_or_part_it_can_not_read_stops_it(self):
        for table in (WRAPPED, UNKNOWN, OUTSIDE):
            self.table.write_text(table)
            p = self.apply("preview", "install", "dnf", "gimp", "--json")
            self.assertEqual(p.returncode, 1, table)
            self.assertIn("can't read", p.stderr)
            p = self.apply("install", "dnf", "gimp", "--check", "--json", stdin={"packages": SHOWN})
            self.assertEqual(p.returncode, 1)
        self.assertNotIn("pkexec", self.ran())

    def test_the_run_keeps_to_the_card(self):
        p = self.apply("install", "dnf", "gimp", "--check", "--json", stdin={"packages": SHOWN})
        self.assertEqual(p.returncode, 0, p.stderr)
        run = next(l for l in self.ran().splitlines() if l.startswith("pkexec"))
        words = run.split()
        self.assertEqual(words[:4], ["pkexec", "/usr/bin/dnf", "install", "-y"])
        self.assertEqual(words[-2:], ["--", "gimp"])
        self.assertIn("--setopt=*.gpgkey=", words)
        self.assertEqual(sorted(w for w in words if w.startswith("--repo")), ["--repo=fedora", "--repo=updates"])
        protected = next(w for w in words if w.startswith("--setopt=protected_packages=")).split("=", 2)[2].split(",")
        for name in ("linux-firmware", "xorg-x11-server-Xwayland", "hyprland", "quickshell"):
            self.assertIn(name, protected)

    def test_a_removal_is_protected_but_not_kept_to_repositories(self):
        self.table.write_text(TABLE.replace("Installing:", "Removing:").replace("Installing dependencies:",
                                                                                  "Removing unused dependencies:"))
        p = self.apply("remove", "dnf", "gimp", "--check", "--json", stdin={"packages": SHOWN})
        self.assertEqual(p.returncode, 0, p.stderr)
        words = next(l for l in self.ran().splitlines() if l.startswith("pkexec")).split()
        self.assertFalse([w for w in words if w.startswith("--repo")])
        self.assertTrue([w for w in words if w.startswith("--setopt=protected_packages=")])

    def test_access_that_allows_removing_drops_only_the_protection(self):
        env = {**self.env, "NIGHTDRIVE_MCP_OPTIONS": json.dumps({"nightdrive_packages": True, "any_source": True})}
        self.assertEqual(self.apply("install", "dnf", "gimp", "--check", stdin={"packages": SHOWN}, env=env).returncode, 0)
        words = next(l for l in self.ran().splitlines() if l.startswith("pkexec")).split()
        self.assertFalse([w for w in words if "protected_packages" in w])
        self.assertIn("--setopt=*.gpgkey=", words)        # a key is never imported unasked
        self.assertIn("--repo=updates", words)

    def test_the_users_own_install_is_as_it_was(self):
        env = {k: v for k, v in self.env.items() if not k.startswith("NIGHTDRIVE_MCP")}
        self.assertEqual(self.apply("install", "dnf", "gimp", "--check", stdin={"packages": SHOWN}, env=env).returncode, 0)
        line = next(l for l in self.ran().splitlines() if l.startswith("pkexec"))
        self.assertEqual(line, "pkexec /usr/bin/dnf install -y -- gimp")

    def test_a_key_not_imported_is_said_so(self):
        self.stand_in("pkexec", 'echo "OpenPGP check for package gimp has failed: no key"; exit 1')
        p = self.apply("install", "dnf", "gimp", "--check", stdin={"packages": SHOWN})
        self.assertEqual(p.returncode, 1)
        self.assertIn("signing key isn't imported", p.stderr)

    def test_rows_changed_since_the_card_stop_it(self):
        p = self.apply("install", "dnf", "gimp", "--check", stdin={"packages": SHOWN[:2]})
        self.assertEqual(p.returncode, 1)
        self.assertNotIn("pkexec", self.ran())


def load(path, name):
    loader = SourceFileLoader(name, str(path))
    module = module_from_spec(spec_from_loader(name, loader))
    loader.exec_module(module)
    return module


class PluginRepos(unittest.TestCase):
    def test_every_installer_that_adds_a_repo_names_it(self):
        sys.dont_write_bytecode = True
        check = load(HERE.parent / "hypr/scripts/plugin-check", "plugin_check")
        for d in sorted((REPO / "plugins").iterdir()):
            conf = d / "plugin.conf"
            if not conf.is_file():
                continue
            values = dict(l.split("=", 1) for l in conf.read_text().splitlines() if "=" in l and not l.startswith("#"))
            if check.adds_repo(str(d), values.get("install", "")):
                self.assertTrue(values.get("repos", "").strip(), d.name)
        self.assertTrue(check.adds_repo(str(REPO / "plugins/keyd"), "install.sh"))
        self.assertTrue(check.adds_repo("/nonexistent", "sudo dnf copr enable -y someone/thing && sudo dnf install x"))
        self.assertFalse(check.adds_repo("/nonexistent", "sudo dnf install -y ncdu"))

    def test_a_repo_added_through_a_setup_script_counts(self):
        """An installer that calls the repo's setup-hyprland-repo.sh adds Nightdrive's COPR, so it needs repos= (#1948)"""
        sys.dont_write_bytecode = True
        check = load(HERE.parent / "hypr/scripts/plugin-check", "plugin_check")
        with tempfile.TemporaryDirectory() as tmp:
            d = Path(tmp) / "example"
            d.mkdir()
            (d / "install.sh").write_text('#!/bin/bash\nrepo=$(cd "$(dirname "$0")/../.." && pwd)\n'
                                          '"$repo/setup-hyprland-repo.sh" >/dev/null && sudo dnf install -y wayvnc\n')
            self.assertEqual(check.adds_repo(str(d), "install.sh"), "setup-hyprland-repo.sh")
            conf = "name=Example\nicon=tablet\ndescription=An example\ninstall=install.sh\ninstalled=true\n" \
                   "version=1.0.0\nauthor=@someone\n"
            (d / "plugin.conf").write_text(conf)
            check.findings.clear()
            check.check_conf(str(d), "example", set())
            self.assertTrue(any("repos=copr:@nightdrive/nightdrive" in f for f in check.findings), check.findings)
            (d / "plugin.conf").write_text(conf + "repos=copr:@nightdrive/nightdrive\n")
            check.findings.clear()
            check.check_conf(str(d), "example", set())
            self.assertFalse(any("repos" in f for f in check.findings), check.findings)
            # A setup script that adds no repository doesn't count
            (d / "install.sh").write_text('"$here/../../setup-user.sh"\n')
            self.assertFalse(check.adds_repo(str(d), "install.sh"))

    def test_software_plugins_lists_them(self):
        found = json.loads(subprocess.run([str(HERE.parent / "hypr/scripts/software"), "plugins", "--json"],
                                          capture_output=True, text=True).stdout)["plugins"]
        vscode = next((p for p in found if p["id"] == "vscode"), None)
        if vscode is None:
            self.skipTest("no vscode plugin listed")
        self.assertEqual(vscode["repos"], ["https://packages.microsoft.com/yumrepos/vscode"])

    def test_the_card_names_them(self):
        """software-apply beside a stand-in `software` whose plugin adds a repository"""
        with tempfile.TemporaryDirectory() as d:
            for name in ("software-apply", "software-claude"):
                (Path(d) / name).write_text((HERE.parent / "hypr/scripts" / name).read_text())
                (Path(d) / name).chmod(0o755)
            plugins = {"plugins": [{"id": "code", "name": "VS Code", "installed": False, "on": False,
                                    "from": "Nightdrive", "repos": ["https://example.com/rpm"]},
                                   {"id": "plain", "name": "Plain", "installed": False, "on": False,
                                    "from": "Nightdrive"}]}
            (Path(d) / "software").write_text(f"#!/bin/bash\ncat <<'EOF'\n{json.dumps(plugins)}\nEOF\n")
            (Path(d) / "software").chmod(0o755)
            env = {**os.environ, "NIGHTDRIVE_MCP": "1", "NIGHTDRIVE_MCP_OPTIONS": "{}"}
            card = lambda pid: json.loads(subprocess.run([str(Path(d) / "software-apply"), "plugin-install", pid,
                                                          "--card", "--json"], capture_output=True, text=True,
                                                         env=env).stdout)
            self.assertEqual(card("code")["Adds repository"], "https://example.com/rpm")
            self.assertNotIn("Adds repository", card("plain"))


if __name__ == "__main__":
    unittest.main()
