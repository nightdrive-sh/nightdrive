# Dictation (Voxtype)

Hold **F5** or **Fn** on a Mac, **Insert** on a PC (or another key: below), speak, and let go: the text is typed into the active window.

It runs fully offline with [Voxtype](https://github.com/peteonrails/voxtype) and NVIDIA's Parakeet model, on the CPU (about 1.4 s for 6 s of speech on an M2 Max).

Voxtype is installed by hand:

1. Download the binaries for your machine from the [Voxtype releases](https://github.com/peteonrails/voxtype/releases)
   (version 1.1.0) into `~/.local/bin`, check their sha256 (`SHA256SUMS.txt`) and drop the version and platform from the
   names: `voxtype-onnx` (Parakeet), plus `voxtype-osd`, `voxtype-osd-quickshell` and `voxtype-audio-bridge` for the
   on-screen recording card.
   - PC: the `linux-x86_64` files, `onnx-avx2` for `voxtype-onnx` (`onnx-avx512` if `grep avx512f /proc/cpuinfo` finds it).
   - Apple Silicon Mac: the `linux-aarch64` files.
   - Leave out `voxtype-osd-gtk4`: without it the card is the Quickshell one below, which fits the desktop.
2. Download the model (into `~/.local/share/voxtype/models`). For better accuracy, also download the full one
   (`--model parakeet-tdt-0.6b-v3`, 2.4 GB): it gets English names and sentence breaks clearly better, about 0.3 s slower
   for 20 s of speech. The daemon uses it whenever it's there.

```sh
voxtype-onnx setup --download --model parakeet-tdt-0.6b-v3-int8
```

3. Install the OSD's QML. `link.sh` then replaces its `OsdSurface.qml` with the one in `config/voxtype/` (card at the top
   centre, no dimming).

```sh
voxtype setup quickshell --source <voxtype repo>/quickshell
```

4. `sudo dnf install wtype` so the text can be typed into windows (without it, it goes to the clipboard).
5. Log out and in: Hyprland starts the daemon at login.

The settings are in `config/voxtype/config.toml`, which `link.sh` links into `~/.config/voxtype/`. `hypr/scripts/dictate`
starts the daemon with the best model installed, and handles the keys and the muted-mic check. The mic is the MacBook's
own on a Mac, and the default one elsewhere.

## Your own corrections

An executable `~/.config/voxtype/post-process` (not in the repo) gets each dictation on stdin before it's typed and returns
the text to type on stdout, e.g. a script that puts product names right (Hyperland → Hyprland). Voxtype's own
`[text] replacements` match whole words only, so an inflected form slips past them. It's picked up at the next login.

## A key on a PC

A MacBook's F5 sends the mic key (`XF86AudioMicMute`), and Fn reaches the system. A PC keyboard usually has neither,
so there Insert is the key (Shift+Insert still pastes); a mic key that sends `XF86AudioMicMute` works as F5. Where Insert
is awkward (a laptop's Fn layer), give dictation another key in `config/hypr/local.lua`, held like F5:

```lua
hl.bind("Pause", hl.dsp.exec_cmd(os.getenv("HOME") .. "/.config/hypr/scripts/dictate start"), { locked = true })
hl.bind("Pause", hl.dsp.exec_cmd(os.getenv("HOME") .. "/.config/hypr/scripts/dictate stop"), { locked = true, release = true, transparent = true })
```

(`transparent` keeps the release working when you click with the mouse while holding the key.)

`hyprctl reload` isn't needed: Hyprland reloads on save. Things that got in the way on a Keychron K8:

- **A mic or assistant key** often sends a shortcut as one tap (Win+C, Cortana's), so the release comes at once and
  holding it does nothing. Turn it into a free key with keyd (`[alt]` or `[meta]` layer, e.g. `c = f18`, in a file of its
  own under `/etc/keyd/` with the keyboard's id in `[ids]`) and bind that key to `voxtype-onnx record toggle`: one press
  starts, the next one stops. The **Copilot key** of newer laptops is often such a tap too (⇧⌘F23, `SUPER + SHIFT + F23`).
- **F20** is `XF86AudioMicMute` in XKB, the hold-to-talk key above: a tap of it starts and stops at once. F13–F18 are
  free (XKB names them `XF86Tools`, `XF86Launch5` … `XF86Launch9`).
- With **keyd** running (the Mac Keyboard Shortcuts plugin), the right Ctrl arrives as the left one, so it can't be bound
  on its own.
- `sudo keyd monitor` shows what a key sends.

Timings for 6 s of speech on the CPU: Parakeet 1.4 s, Whisper small 4.3 s, medium 13.7 s, large-v3-turbo 24 s.
