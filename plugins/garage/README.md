# Garage

Virtual machines from a ready-made Fedora image or any ISO, fast enough to forget they're virtual. Take a snapshot before you try something, and go back if it went wrong.

## Using it

| Keys | |
| --- | --- |
| Hyper G | Open Garage |
| `?` | Garage's keys |
| ⌘N | New VM |
| `s` | Start |
| `d` | Show its display, or bring it to this workspace |
| `p` | Pause, or resume |
| `x` | Shut down |
| ⇧X | Pull the plug |
| `t` | Take a snapshot (VM stopped) |
| `Enter` | Go back to the snapshot |
| `e` `c` | Rename or duplicate the snapshot |
| `Delete` or ⌘⌫ | Delete the snapshot |
| ⌘, | Memory, CPUs, disk, ISO and ssh user of a stopped VM |
| F2 | Rename a stopped VM |

- A ready-made image (Fedora 44 Minimal on a Mac, Cloud Base on a PC) needs no installer: its first boot makes your user, with sudo and your ssh key. Or pick an ISO from Downloads (or ~/vm).
- The top bar's garage icon lights up while a VM runs, and blinks while one boots or shuts down; a click lists your VMs to start or show.
- A VM is *Booting up* until its guest agent or sshd answers (at most two minutes), and *Shutting down* until qemu has gone. A shutdown that hasn't happened in a minute offers Force off.
- A paused VM frees its CPUs but keeps its memory. Resume sets its clock (with qemu-guest-agent in it); snapshots and settings still need it shut down.
- Nightdrive in a VM follows its window's size, as in UTM and Parallels, from its login screen on, at scale 2 until you pick another in its Settings › Display. Nightdrive older than 0.6 in it keeps the size it started with, stretched: update it.
- A snapshot's duplicate shares its space on the disk. Beside each snapshot is the space it alone keeps.
- `ssh NAME` reaches a running VM: each has a port of its own, kept in ~/.ssh/config.d/garage (Garage adds `Include config.d/garage` to ~/.ssh/config).
- Your VMs live in ~/.local/share/nightdrive/garage, and stay there if you remove Garage.
- A VM reaches your computer's local services too: 10.0.2.2 in it is the host's 127.0.0.1. Keep that in mind before running something you don't trust in one.

## In a terminal

| Command | What it does |
| --- | --- |
| `garage` | Opens Garage, or brings it forward |
| `garage list` | The VMs, one line each |
| `garage start`, `stop`, `kill`, `pause`, `resume`, `display`, `hide [NAME]` | A VM by its name, or the only one there is |
| `garage ssh [NAME]` | `ssh NAME`: a shell in it, or a command after its name |
| `garage rename-vm NAME NEWNAME` | A new name for a stopped VM, its ssh name too |
| `garage set NAME user USER`, `port N` | Its ssh user, or another port (if something else has its own) |
| `garage help` | Everything else: create, snapshot, restore, delete… |
| `garage install`, `uninstall` | Garage among your apps, or out of them (the VMs and qemu stay) |
| `garage restart`, `quit`, `log` | After a change to Garage, and its QML errors |

Needs: qemu with KVM and UEFI firmware (its installer puts them in)
Keys: Hyper G
