# Garage

Virtual machines in a window of their own: make one from a ready-made Fedora image or from an ISO, start it, take a snapshot before you try something, and go back to it if that went wrong. Each VM runs in qemu with KVM at nearly the machine's own speed, with a GPU for a desktop of its own. Garage runs on an Asahi Mac (aarch64 VMs) and on a PC (x86_64 VMs). It doesn't come with every install: pick it in launcher › System › Install › Recommended.

## Using it

- Hyper G (Caps Lock + G) or the launcher opens Garage. Press `?` in it to see its keys.
- The top bar's garage icon lights up while a VM runs. A click on it lists your VMs: click one to start it, or to bring a running one's display forward, and Shut down under it stops it. A right click opens Garage.
- ⌘N makes a new VM. A ready-made image (Fedora 44 Minimal on a Mac, Fedora 44 Cloud Base on a PC) needs no installer: Garage downloads it once (the sidebar shows how far), and its first boot makes your user, with sudo, and lets you in over ssh. Or pick an ISO from Downloads (or ~/vm) and install as on any computer.
- `s` starts the selected VM, its display opens in a window of its own (`d` brings it forward), `x` shuts it down and ⇧X pulls the plug.
- `t` takes a snapshot while the VM is stopped, `Enter` on one goes back to it, `e` renames it, `c` duplicates it under a new name (the copy shares its space on the disk, so it takes none of its own) and Delete (or ⌘⌫) deletes it. Beside each is when it was taken and the space it alone keeps on the disk, what deleting it would free.
- ⌘, changes the memory, CPUs, disk (it only grows) and ISO of a stopped VM; ⌘⌫ deletes the VM.
- A VM made from an image answers `ssh -p 2222 localhost` with your own key.
- Your VMs live in ~/.local/share/nightdrive/garage, one folder each, readable by you alone: removing Garage leaves them there.
- A VM reaches the internet through qemu's own network, and your computer's local services too: 10.0.2.2 in it is the host's 127.0.0.1. Keep that in mind before running something you don't trust in one.

## In a terminal

| Command | What it does |
| --- | --- |
| `garage` | Opens Garage, or brings it forward |
| `garage list` | The VMs, one line each |
| `garage start`, `stop`, `kill`, `display [NAME]` | A VM by its name, or the only one there is |
| `garage help` | Everything else: create, snapshot, restore, delete… |
| `garage install`, `uninstall` | Garage among your apps, or out of them (the VMs and qemu stay) |
| `garage restart`, `quit`, `log` | After a change to Garage, and its QML errors |

Needs: qemu with KVM and UEFI firmware (its installer puts them in)
Keys: Hyper G
