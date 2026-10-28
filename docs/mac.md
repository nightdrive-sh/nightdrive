# Nightdrive on a Mac

Nightdrive runs on an Apple Silicon Mac (M1 or M2 series) with **[Fedora Asahi Remix](https://asahilinux.org/fedora/) 44**,
next to macOS. It's used every day on a MacBook Pro 14″ with an M2 Max; other models may need a few values adjusted
([Make it yours](../README.md#make-it-yours)).

1. In macOS's Terminal, run Asahi's installer and pick **Fedora Asahi Remix 44 Minimal**. It resizes macOS's partition
   and leaves macOS as it was.

```sh
curl https://fedora-asahi-remix.org/install | sh
```

2. Boot into Fedora, finish its first-boot setup (your user) and log in on the text console.
3. Install as in [Install](../README.md#install). The installer first asks for the keyboard layout, as Asahi
   Minimal leaves it `us` and the login screen's password is typed with it (`--keyboard "fi mac"` answers in advance).

Fedora Asahi Remix with KDE Plasma works too, KDE staying as a fallback.

## What Nightdrive sets up on a Mac

- **The notch.** The display uses its full top edge (the `appledrm.show_notch=1` kernel argument), and the top bar sits in
  the notch area.
- **The top-row keys** control volume, brightness, the keyboard backlight and dictation (hold Fn).
- **Sleep.** Asahi only has s2idle, where the Mac draws about 3 W asleep. Wi-Fi and Bluetooth are turned off while it
  sleeps and back on at wake-up (`NIGHTDRIVE_RADIOS=0` in `/etc/nightdrive-sleep.conf` keeps them on).
- **What a Mac doesn't use** goes: the Minimal image's server services (network logins and shares, system logs, crash
  reports) and other Wi-Fi chips' firmware (`packages-remove-asahi.txt`; `--choose` unticks it).
- **macOS's partitions** (its disk, the boot picker's and the recovery's) are hidden from Files' sidebar. Nothing on the
  disk changes, and macOS's disk can still be opened by hand (with an APFS driver such as apfs-fuse).

## What doesn't work yet

These are Asahi Linux's limits, not Nightdrive's; [Asahi's feature support](https://asahilinux.org/docs/platform/feature-support/overview/)
has the current state for each model.

- **Touch ID**: not supported. Type your password.
- **External displays over USB-C / Thunderbolt**: not yet (work in progress). The HDMI port works on the models that have
  one (Mac mini, Mac Studio, MacBook Pro 14″ and 16″); its sound is a preview.
- **Thunderbolt and USB4**: the ports work as USB 3.
- **Hardware video encoding**: none, so Screen Mirroring encodes on the CPU (up to 1080p, with a short delay).
- **Deep sleep**: only s2idle (above).
- **16 KiB memory pages** break a few Electron apps; 1Password works.

## Good to know

- The display defaults are the MacBook's (scale 2), and rounded screen corners tuned for its display are off
  (`NIGHTDRIVE = { corners = true }` in `config/hypr/local.lua` turns them on).
- To go back to macOS, hold the power button at start-up and pick it in the boot picker.
