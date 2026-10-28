# Nightdrive on a PC

Nightdrive runs on an x86_64 PC with a minimal **Fedora 44**. The installer recognises the machine and prints it first,
e.g. `Machine: PC (x86_64, graphics: nvidia, keyboard: fi)`.

1. Download Fedora 44's **Everything netinstall** image for x86_64 from [fedoraproject.org/misc](https://fedoraproject.org/misc/)
   (Fedora 44, because the Hyprland COPR builds for that release) and write it to a USB stick (Fedora Media Writer, or
   `dd`).
2. Boot it and, in the installer:
   - **Keyboard** and **Language**: the layout you pick is the one Nightdrive uses, also on its login screen; the
     language's formats come along.
   - **Software Selection**: *Fedora Custom Operating System*, and on the right **Common NetworkManager Submodules**.
     Without them a computer with only Wi-Fi has no network before Nightdrive installs it (a cable works either way).
   - **User Creation**: your user, with *Make this user administrator* ticked.
3. Reboot, log in on the text console and install as in [Install](../README.md#install).

Fedora 44 KDE works too, KDE staying as a fallback.

## What Nightdrive sets up on a PC

- **The display.** Hyprland picks the scale from the display's size and resolution. Change it, and the refresh rate, in
  Launcher › Settings › Display (a TV's preferred mode is often 60 Hz, though it does 120).
- **The keyboard.** The layout Fedora's installer set, also on the login screen.
- **⌘ is the Windows key.** ⌘C / ⌘V / ⌘X copy, paste and cut in every app, and the rest of the shortcuts work as they are.
- **Firmware** for every Wi-Fi chip and the processor's microcode (`@hardware-support`).
- **Dictation** uses the default microphone. The system menu's temperatures are the CPU's (Intel `coretemp`, AMD
  `k10temp`), AMD graphics' and the SSD's.
- Without a battery or a keyboard backlight, their parts are left out of the menus.

The display and keyboard settings go to `config/hypr/local.lua` (not in the repo): edit it, or delete it and run
`./install.sh` again to write it anew.

## NVIDIA

Hyprland needs NVIDIA's own driver. On a PC with an NVIDIA card the installer enables RPM Fusion, installs `akmod-nvidia`
and builds the module for the newest kernel before the reboot. `hyprland.lua` sets the driver's environment
(`LIBVA_DRIVER_NAME`, `__GLX_VENDOR_LIBRARY_NAME`, `NVD_BACKEND`) when the driver is loaded. `--no-nvidia` leaves the
driver alone, for one installed by hand.

**Secure Boot:** the module is signed with a key of this machine's own (`kmodgenca`). Before the reboot, run this and choose a
one-time password:

```sh
sudo mokutil --import /etc/pki/akmods/certs/public_key.der
```

At the reboot the blue MOK
screen asks for it (Enroll MOK › Continue › Yes). Without that the driver doesn't load and the screen stays on Fedora's
basic driver. The installer reminds you at the end.

If the build hadn't finished by the reboot, akmods builds it at boot: `sudo journalctl -u akmods`, and
`modinfo nvidia` shows the version once it's there.
