# Trying Nightdrive in a virtual machine

The easiest way to try Nightdrive without touching your own system: install it in a Fedora 44 virtual machine on the
computer you already have, Mac or PC.

1. Download Fedora 44's **Everything netinstall** image from [fedoraproject.org/misc](https://fedoraproject.org/misc/):
   **aarch64** for an Apple Silicon Mac, **x86_64** for a PC.
2. Make a VM with at least 4 GB of memory (8 GB is better) and **3D acceleration** on: Hyprland needs a GPU, and without
   one the desktop doesn't start.
3. In Fedora's installer pick *Fedora Custom Operating System* in Software Selection, and create your user with *Make
   this user administrator* ticked.
4. Reboot, log in and install as in [Install](../README.md#install). The installer recognises the VM (`--vm` forces it)
   and sets the display scale to 2: pick another in the Launcher › Settings › Display.

## Which app

| Computer | App | |
|---|---|---|
| Mac | [Parallels Desktop](https://www.parallels.com) | tested (below) |
| Mac | [UTM](https://mac.getutm.app) (free), with the GPU-accelerated display | not tested |
| Linux PC | GNOME Boxes or virt-manager, with 3D acceleration | not tested |
| Windows PC | VMware Workstation Pro (free for personal use), with *Accelerate 3D graphics* | not tested |

VirtualBox isn't worth trying: its 3D support isn't enough for a Wayland desktop. Tried one of the untested ones? Tell
how it went in [Discussions](https://github.com/nightdrive-sh/nightdrive/discussions).

### Parallels

- File › New › *Install from an image file*, tick *Customize settings before installation*, and under Graphics pick
  **Best for Retina display**. 3D acceleration is on by default for Linux on ARM; Parallels Tools aren't needed.
- To use ⌘ inside the VM, set the VM's Hardware › Mouse & Keyboard › *Send macOS system shortcuts* to *Always*.
- After restoring a snapshot, run `sudo systemctl restart chronyd`: the VM's clock goes back with the snapshot, and dnf
  rejects packages whose signatures look made in the future.

## In Garage

On a computer that already runs Nightdrive, [Garage](../plugins/garage/README.md), Nightdrive's own app for virtual
machines, makes the VM for you: ⌘N and a
ready-made Fedora 44 image, with no installer to click through. Start it, `ssh NAME` into it and install as above.
Snapshots let you go back and try again.
