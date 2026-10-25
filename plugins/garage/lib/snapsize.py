#!/usr/bin/env python3
"""snapsize.py DISK.qcow2: what each internal snapshot holds on its own, as JSON { tag: bytes }.

qemu-img reports a snapshot's saved RAM (vm-state-size, 0 for ours) but not the disk space it takes, so this reads the
qcow2's own tables: each snapshot's L1 and L2 tables name the data clusters it sees, as the active disk's do. A cluster
seen by one snapshot alone is space only that snapshot keeps, what deleting it would give back. One shared with another
snapshot or the disk as it is now counts for neither, as deleting one of them frees nothing.

Read while the VM is stopped (garage-ctl list caches it by the disk's mtime): a running qemu changes the tables under it.
Format: docs/interop/qcow2.txt in qemu's source.
"""
import json
import struct
import sys

OFFSET_MASK = 0x00FFFFFFFFFFFE00        # bits 9-55: a table's or a standard cluster's host offset
COMPRESSED = 1 << 62
EXTENDED_L2 = 1 << 4                    # incompatible feature: 16-byte L2 entries with subcluster bitmaps


def l2_clusters(f, l1_offset, l1_size, cluster_bits, entry_size):
    """The data clusters one L1 table reaches: { key: bytes }, a standard cluster's by its host offset (its whole
    size), a compressed one's by its byte offset (its sectors)."""
    cluster = 1 << cluster_bits
    out = {}
    if not l1_size:
        return out
    f.seek(l1_offset)
    l1 = struct.unpack(f">{l1_size}Q", f.read(8 * l1_size))
    # A compressed entry: the offset in its low x bits, then (sectors - 1)
    x = 62 - (cluster_bits - 8)
    for e in l1:
        l2_offset = e & OFFSET_MASK
        if not l2_offset:
            continue
        f.seek(l2_offset)
        raw = f.read(cluster)
        entries = struct.unpack(f">{cluster // 8}Q", raw)[::entry_size // 8]
        for d in entries:
            if d & COMPRESSED:
                off = d & ((1 << x) - 1)
                out[("c", off)] = (((d >> x) & ((1 << (cluster_bits - 8)) - 1)) + 1) * 512
            else:
                off = d & OFFSET_MASK
                if off:
                    out[off] = cluster
    return out


def sizes(path):
    with open(path, "rb") as f:
        h = f.read(104)
        magic, version = struct.unpack(">4sI", h[:8])
        if magic != b"QFI\xfb":
            raise SystemExit(f"{path}: not a qcow2 disk")
        cluster_bits, = struct.unpack(">I", h[20:24])
        l1_size, l1_offset = struct.unpack(">IQ", h[36:48])
        nb_snapshots, snapshots_offset = struct.unpack(">IQ", h[60:72])
        features = struct.unpack(">Q", h[72:80])[0] if version >= 3 else 0
        entry_size = 16 if features & EXTENDED_L2 else 8

        # The snapshot table: each entry's L1 table and its tag (qemu's "name"), padded to 8 bytes
        snaps = []
        f.seek(snapshots_offset)
        for _ in range(nb_snapshots):
            s_l1_offset, s_l1_size, id_len, name_len = struct.unpack(">QIHH", f.read(16))
            f.read(20)                  # date, VM clock, VM state size
            extra, = struct.unpack(">I", f.read(4))
            f.read(extra + id_len)
            tag = f.read(name_len).decode("utf-8", "replace")
            pad = (40 + extra + id_len + name_len) % 8
            if pad:
                f.read(8 - pad)
            snaps.append((tag, s_l1_offset, s_l1_size))

        layers = [l2_clusters(f, l1_offset, l1_size, cluster_bits, entry_size)]
        layers += [l2_clusters(f, o, n, cluster_bits, entry_size) for _, o, n in snaps]

    # How many layers see each cluster; a snapshot's own are those it alone sees
    seen = {}
    for layer in layers:
        for k in layer:
            seen[k] = seen.get(k, 0) + 1
    return {tag: sum(b for k, b in layer.items() if seen[k] == 1)
            for (tag, _, _), layer in zip(snaps, layers[1:])}


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("snapsize.py DISK.qcow2")
    print(json.dumps(sizes(sys.argv[1])))
