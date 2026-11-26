"""The disks in Files' sidebar, straight from UDisks2 on the system bus: a mounted one with its folder, one that can be
mounted without it; and mounting, unmounting and ejecting them.

Not through Gio's volume monitor (#3707): that starts gvfs's udisks2 monitor when it isn't running yet, and the monitor
looks into every mount under home as it starts, a network drive's too (rclone, plugins/netdrive). That made rclone
connect, and its ssh ask 1Password's agent, so a locked 1Password asked to be unlocked the moment Files opened. UDisks2
knows block devices only, so a network drive isn't here at all (netdrives.py lists those) and nothing here touches one.
Without UDisks2 or PyGObject (a container, CI) there are no disks, and the rest of the sidebar still works.
"""
import os

import trash

BUS = "org.freedesktop.UDisks2"
ROOT = "/org/freedesktop/UDisks2"
BLOCK = BUS + ".Block"
FS = BUS + ".Filesystem"
DRIVE = BUS + ".Drive"
LIST_TIMEOUT = 5000      # ms: UDisks2 answers its list at once
ACT_TIMEOUT = 60000      # ms: a mount may wait on a slow stick or a password prompt (polkit)
SHOWN = ("/run/media/", "/media/")   # where a mounted disk is the user's, as gvfs has it, and home (below)


def _bus():
    """The system bus, or None without one (or without PyGObject)"""
    try:
        import gi
        gi.require_version("Gio", "2.0")
        from gi.repository import Gio, GLib
        return Gio.bus_get_sync(Gio.BusType.SYSTEM, None), Gio, GLib
    except Exception:   # ImportError, ValueError (no Gio 2.0), GLib.Error (no system bus)
        return None


def _text(value):
    """A UDisks2 byte string (ay: bytes, or a list of numbers) as text, without its closing NUL"""
    if isinstance(value, (list, tuple)):
        value = bytes(value)
    return value.rstrip(b"\0").decode(errors="replace") if isinstance(value, bytes) else str(value or "")


def _size(n):
    """1500000000 → "1.5 GB", as gvfs names a disk without a label"""
    for unit in ("B", "kB", "MB", "GB"):
        if n < 1000:
            return f"{n:.0f} {unit}" if unit == "B" or n >= 100 else f"{n:.1f} {unit}"
        n /= 1000
    return f"{n:.1f} TB"


def objects():
    """GetManagedObjects as {object path: {interface: {property: value}}}, {} without UDisks2"""
    b = _bus()
    if not b:
        return {}
    bus, Gio, GLib = b
    try:
        r = bus.call_sync(BUS, ROOT, "org.freedesktop.DBus.ObjectManager", "GetManagedObjects", None,
                          GLib.VariantType.new("(a{oa{sa{sv}}})"), Gio.DBusCallFlags.NONE, LIST_TIMEOUT, None)
    except Exception:   # GLib.Error: UDisks2 isn't there
        return {}
    return r.unpack()[0]


def _shown(path, home):
    return path.startswith(SHOWN) or path.startswith(home.rstrip("/") + "/")


def rows(objs, home=None):
    """[{name, path ("" unmounted), device, glyph, unmount, object}] for the sidebar: a filesystem mounted where it is the
    user's, and one not mounted that isn't the system's own (its partitions, the recovery, the EFI one)"""
    home = home or os.path.expanduser("~")
    out = []
    for obj, ifaces in sorted(objs.items()):
        block, fs = ifaces.get(BLOCK), ifaces.get(FS)
        if not block or fs is None or block.get("IdUsage") != "filesystem" or block.get("HintIgnore"):
            continue
        drive = objs.get(block.get("Drive", ""), {}).get(DRIVE, {})
        system = bool(block.get("HintSystem"))
        points = [_text(p) for p in fs.get("MountPoints", [])]
        path = next((p for p in points if _shown(p, home)), "")
        if (points and not path) or (not points and system):
            continue
        name = block.get("HintName") or block.get("IdLabel") or f"{_size(block.get('Size', 0))} Volume"
        removable = drive.get("Removable") or drive.get("Ejectable") or drive.get("ConnectionBus") in ("usb", "sdio")
        out.append({"name": name, "path": path, "device": _text(block.get("PreferredDevice") or block.get("Device")),
                    "glyph": "usb" if removable else "hard-drive",
                    "unmount": bool(path) and (not system or path.startswith("/run/media/")), "object": obj})
    return out


def devices():
    return [{k: v for k, v in r.items() if k != "object"} for r in rows(objects())]


def _call(obj, iface, method):
    """A UDisks2 method that takes only its options (a{sv}); its answer unpacked, or Refused with UDisks2's reason"""
    bus, Gio, GLib = _bus()
    try:
        r = bus.call_sync(BUS, obj, iface, method, GLib.Variant("(a{sv})", ({},)), None, Gio.DBusCallFlags.NONE,
                          ACT_TIMEOUT, None)
    except GLib.Error as e:
        Gio.DBusError.strip_remote_error(e)   # "GDBus.Error:org.freedesktop.UDisks2.Error.DeviceBusy: " off
        raise trash.Refused(e.message)
    return r.unpack() if r is not None else ()


def mount(device):
    """Mounts the disk whose device is device (/dev/sdb1) where UDisks2 puts it: {path}"""
    r = next((r for r in rows(objects()) if r["device"] == device), None)
    if not r:
        raise trash.Refused(f"{device} isn't there any more.")
    return {"path": _call(r["object"], FS, "Mount")[0]}


def unmount(path):
    """Unmounts the disk at path, and a stick's drive is powered off so it can be pulled out: {unmounted: path}. A drive
    with another partition still mounted stays on; that one is unmounted on its own."""
    objs = objects()
    r = next((r for r in rows(objs) if r["path"] == path), None)
    if not r:
        raise trash.Refused(f"{path} isn't a disk that can be unmounted here.")
    _call(r["object"], FS, "Unmount")
    drive_obj = objs[r["object"]][BLOCK].get("Drive", "")
    drive = objs.get(drive_obj, {}).get(DRIVE, {})
    try:
        if drive.get("CanPowerOff"):
            _call(drive_obj, DRIVE, "PowerOff")
        elif drive.get("Ejectable"):
            _call(drive_obj, DRIVE, "Eject")
    except trash.Refused:
        pass
    return {"unmounted": path}
