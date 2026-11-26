#!/usr/bin/env python3
"""isoarch.py ISO: which architecture an installer ISO boots on, for lib/arch.sh's iso_check.

Prints aarch64 or x86_64, or nothing when it can't tell (exit 0 either way). A UEFI VM boots an ISO from the default
loader in /EFI/BOOT of its ISO 9660 filesystem (BOOTAA64.EFI, BOOTX64.EFI): an ISO with only another architecture's
gets "No bootable option or device was found" from the firmware, and nothing else (#1848). Each loader's PE header says
whose it is, not its name: Fedora's aarch64 Live ISOs have a BOOTX64.EFI that is an aarch64 one, and ISO 9660's own
names mangle a second BOOTAA64.EFI into BOOTAA640.EFI. The ISO's name ("…-x86_64.iso") is the fallback, as some keep the
loader only in their El Torito image.

Only reads the volume descriptor and two directories, by hand rather than with isoinfo/7z/xorriso, which a Fedora
install may not have. The ISO is a download: every offset is checked against what was read.
"""
import re
import sys

SECTOR = 2048
LOADER = re.compile(r"^BOOT[A-Z0-9]*\.EFI$")
MACHINES = {0xAA64: "aarch64", 0x8664: "x86_64", 0x014C: "x86_64"}     # PE's IMAGE_FILE_MACHINE_*: arm64, amd64, i386
NAMES = [(re.compile(r"[-_.](aarch64|arm64)[-_.]", re.I), "aarch64"),
         (re.compile(r"[-_.](x86_64|amd64|x64|i[3-6]86)[-_.]", re.I), "x86_64")]
MAX_DIR = 1 << 20   # a directory bigger than this isn't one an installer has


def records(f, lba, size):
    """The directory's entries: (name, lba, size, is_dir), its . and .. left out."""
    f.seek(lba * SECTOR)
    data = f.read(min(size, MAX_DIR))
    i = 0
    while i < len(data):
        n = data[i]
        if n == 0:                      # records don't cross a sector: the rest of this one is padding
            i = (i // SECTOR + 1) * SECTOR
            continue
        if n < 34 or i + n > len(data):
            return
        rec = data[i:i + n]
        name_len = rec[32]
        if 33 + name_len <= n:
            name = rec[33:33 + name_len]
            if name not in (b"\0", b"\1"):
                yield (name.decode("ascii", "replace").split(";")[0].rstrip(".").upper(),
                       int.from_bytes(rec[2:6], "little"), int.from_bytes(rec[10:14], "little"), bool(rec[25] & 2))
        i += n


def from_loader(path):
    """The architectures of the loaders in /EFI/BOOT, or None when there is no such folder."""
    with open(path, "rb") as f:
        f.seek(16 * SECTOR)
        pvd = f.read(SECTOR)
        if len(pvd) < 190 or pvd[0] != 1 or pvd[1:6] != b"CD001":
            return None
        root = pvd[156:190]
        here = (int.from_bytes(root[2:6], "little"), int.from_bytes(root[10:14], "little"))
        for want in ("EFI", "BOOT"):
            found = [(lba, size) for name, lba, size, is_dir in records(f, *here) if is_dir and name == want]
            if not found:
                return None
            here = found[0]
        loaders = [lba for name, lba, _, is_dir in records(f, *here) if not is_dir and LOADER.match(name)]
        return {a for a in (machine(f, lba) for lba in loaders[:8]) if a}


def machine(f, lba):
    """A PE file's architecture, from its COFF header's Machine field."""
    f.seek(lba * SECTOR)
    head = f.read(SECTOR)
    if head[:2] != b"MZ" or len(head) < 64:
        return None
    pe = int.from_bytes(head[60:64], "little")
    if pe + 6 > len(head) or head[pe:pe + 4] != b"PE\0\0":
        return None
    return MACHINES.get(int.from_bytes(head[pe + 4:pe + 6], "little"))


def main():
    path = sys.argv[1]
    try:
        archs = from_loader(path)
    except OSError:
        archs = None
    if archs is not None and len(archs) == 1:
        print(archs.pop())
        return
    if archs:                           # loaders for both: it boots on either
        return
    for pattern, arch in NAMES:
        if pattern.search(path.rsplit("/", 1)[-1]):
            print(arch)
            return


if __name__ == "__main__":
    main()
