#!/usr/bin/env python3
"""The repo's CI checks, the same locally and in .github/workflows/ci.yml.

  check.py                    syntax (bash -n, ast.parse) and shellcheck
  check.py --secrets          gitleaks over the whole history as well
  check.py --update-baseline  write the shellcheck findings there are now as the baseline

Shellcheck runs at severity warning against a baseline (shellcheck-baseline.txt): the findings that were there when
CI began are counted per file and code, and only more of them fails. Most were deliberate (word splitting of package
lists, glob matches in [[ ]], a literal ~ in a message), and a baseline lets new code meet the full check without
rewriting working scripts. A finding fixed lowers the count: --update-baseline then keeps it from coming back.
"""
import argparse
import ast
import collections
import json
import os
import shutil
import subprocess
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
BASELINE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "shellcheck-baseline.txt")
SHELLS = (b"bash", b"/sh", b" sh")


def tracked_scripts():
    """Shell and Python scripts git tracks, by extension or shebang. Symlinks point at files listed themselves."""
    out = subprocess.run(["git", "ls-files", "-z"], cwd=ROOT, capture_output=True, check=True).stdout
    sh, py = [], []
    for f in out.decode().split("\0"):
        path = os.path.join(ROOT, f)
        if not f or os.path.islink(path) or not os.path.isfile(path):
            continue
        if f.endswith((".sh", ".bash")):
            sh.append(f)
        elif f.endswith(".py"):
            py.append(f)
        else:
            with open(path, "rb") as fh:
                first = fh.readline(200)
            if first.startswith(b"#!"):
                if b"python" in first:
                    py.append(f)
                elif any(s in first for s in SHELLS):
                    sh.append(f)
    return sh, py


def bash_syntax(files):
    bad = 0
    for f in files:
        r = subprocess.run(["bash", "-n", f], cwd=ROOT, capture_output=True, text=True)
        if r.returncode:
            print(f"bash -n: {r.stderr.strip()}")
            bad += 1
    return bad


def python_syntax(files):
    bad = 0
    for f in files:
        try:
            with open(os.path.join(ROOT, f), "rb") as fh:
                ast.parse(fh.read(), f)
        except SyntaxError as e:
            print(f"ast.parse: {f}:{e.lineno}: {e.msg}")
            bad += 1
    return bad


def shellcheck(files):
    """Findings as a list of dicts (file, line, code, message); .shellcheckrc at the root sets shell and exclusions."""
    r = subprocess.run(["shellcheck", "--severity=warning", "-f", "json1", *files], cwd=ROOT,
                       capture_output=True, text=True)
    if r.returncode not in (0, 1):
        sys.exit(f"shellcheck failed: {r.stderr.strip()}")
    return json.loads(r.stdout or '{"comments": []}')["comments"]


def read_baseline():
    counts = collections.Counter()
    if os.path.exists(BASELINE):
        with open(BASELINE) as fh:
            for line in fh:
                if line.strip() and not line.startswith("#"):
                    n, f, code = line.split()
                    counts[(f, code)] = int(n)
    return counts


def write_baseline(found):
    with open(BASELINE, "w") as fh:
        fh.write("# Shellcheck findings CI accepts: count, file, code (.github/ci/check.py --update-baseline).\n")
        for (f, code), n in sorted(found.items()):
            fh.write(f"{n} {f} {code}\n")


def secrets():
    """gitleaks over every commit; .gitleaksignore at the root lists the findings judged harmless."""
    if not shutil.which("gitleaks"):
        sys.exit("gitleaks is not installed (sudo dnf install gitleaks)")
    r = subprocess.run(["gitleaks", "git", "--redact", "--no-banner", "--exit-code", "1", "."], cwd=ROOT)
    return 1 if r.returncode else 0


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--secrets", action="store_true", help="also scan the history for secrets with gitleaks")
    ap.add_argument("--update-baseline", action="store_true", help="accept the shellcheck findings there are now")
    args = ap.parse_args()
    if not shutil.which("shellcheck"):
        sys.exit("shellcheck is not installed (sudo dnf install ShellCheck)")

    sh, py = tracked_scripts()
    bad = bash_syntax(sh) + python_syntax(py)

    comments = shellcheck(sh)
    found = collections.Counter((c["file"], f"SC{c['code']}") for c in comments)
    if args.update_baseline:
        write_baseline(found)
        print(f"baseline: {sum(found.values())} findings in {len({f for f, _ in found})} files")
        return 0
    base = read_baseline()
    for key, n in sorted(found.items()):
        if n > base[key]:
            f, code = key
            print(f"shellcheck: {f}: {code} {n} times, baseline {base[key]}:")
            for c in comments:
                if (c["file"], f"SC{c['code']}") == key:
                    print(f"  {f}:{c['line']}: {c['message']}")
            bad += 1
    fixed = sum(base[k] - found[k] for k in base if found[k] < base[k])
    if fixed:
        print(f"shellcheck: {fixed} baseline findings are gone: run --update-baseline to keep them out")

    if args.secrets:
        bad += secrets()
    print(f"{len(sh)} shell and {len(py)} Python scripts: " + ("ok" if not bad else f"{bad} problems"))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
