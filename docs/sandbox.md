# Nightdrive in a headless container (`nightdrive sandbox`)

`nightdrive sandbox` runs the desktop in a rootless Podman container with no screen. It is meant for checking a change and
taking a screenshot of it on a machine without Hyprland (a build server, say), or without taking over the keyboard of the
desktop you're sitting at. Needs Linux with rootless Podman and a GPU render node (`/dev/dri/renderD*`, readable by
you): without one Hyprland crashes at start. Tested on x86_64 (Rocky Linux 9, Intel GPU) and aarch64 (Fedora Asahi Remix 44 on a
14" MacBook Pro, M2 Max); not on macOS, where Podman runs in a VM without a GPU.

    nightdrive sandbox up           # builds the image the first time (~10 min, ~4.5 GB: KWin brings much of KDE), then starts it
    nightdrive sandbox check        # exit 1 and the findings: Hyprland's config, Quickshell, plugin check
    nightdrive sandbox shot NAME    # prints the path of NAME.png (in ~/.cache/nightdrive/sandbox/shots)
    nightdrive sandbox ipc launcher openLevel settings
    nightdrive sandbox exec hyprctl clients
    nightdrive sandbox vnc          # wayvnc on the tailnet address, for watching and clicking; `vnc stop` ends it
    nightdrive sandbox down

`check`, `shot`, `ipc` and `exec` start the sandbox first if it isn't up. `check` runs `Hyprland --verify-config`,
`hyprctl configerrors` and reads Quickshell's log since its last reload: a failed reload (`ERROR`) or a QML runtime error
(`WARN … @File.qml[line:col]: …`), and runs `nightdrive plugin check` on the plugins. Paths in its output are the repo's.

The repo is mounted read-only, so an edit reloads in the sandbox right away, as on the desktop (and the same Quickshell
quirks apply: it doesn't watch `shell.qml` once that file has been replaced by a new one, and components listed in
`qmldir` keep their old version until a restart). The container gets its own `config/hypr/local.lua` and `xdph.conf`
mounted over the repo's, and an empty `local.d` over yours, so your own `local.lua` and `local.d` don't apply there.

The container matches a MacBook Pro 14" as far as Hyprland goes, not the hardware: battery, Bluetooth, Wi-Fi and sound stay
empty. None of the optional parts (`plugins.txt`, `plugins/`) is installed, so the desktop is the one you get with
`install.sh --none`. To see a part's rows, bar module and keys, fake its installed test: e.g. `nightdrive sandbox exec sh -c
'printf "#!/bin/sh\n" > ~/.local/bin/deck && chmod +x ~/.local/bin/deck && nightdrive plugins installed'`. A test that asks
systemd works too, as there's no user manager to start anything: `nightdrive sandbox exec sh -c 'systemctl --user enable
nightdrive-localsend.service && nightdrive plugins installed'` (LocalSend). A plugin folder put in the container's
`~/.local/share/nightdrive/plugins/` is picked up like one of the repo's, which is handy for trying one out.

## Display and VNC

The display sizes are constants at the top of `config/sandbox/sandbox`. Screenshots are taken at 3024x1964, scale 2 (the
MacBook Pro 14"). `vnc` drops it to 1512x982 at scale 1, the same UI size with a quarter of the pixels, which a viewer over
the tailnet keeps up with; `vnc stop` sets it back.

VNC is published only on the host's tailnet address (`tailscale ip -4`, read when the sandbox starts) on port 5901, with no
password: the tailnet is the boundary. The host's firewall must let 5901/tcp in from the tailnet; `vnc` prints the
firewalld command. The size is fixed: a viewer's "SetDesktopSize failed" is harmless (TigerVNC: turn off "Resize remote
session").

## How it runs

Hyprland 0.56 / aquamarine 0.14 can't run on the headless backend alone ("no allocator available"), and needs a host
compositor with xdg_wm_base v6 and wl_compositor v6: sway 1.11 and Weston 15 are too old. KWin 6.7's virtual backend
(`kwin_wayland --virtual`) works, so Hyprland runs nested in it (Wayland backend, output `WAYLAND-1`), started with
`start-hyprland` as the login screen does. `config/sandbox/inside` does the work inside the container.

- `kwin_wayland` has `cap_sys_nice` as a file capability, which a rootless container can't exec: the image removes it
  (`setcap -r`). `--cap-add SYS_NICE` would work for KWin but puts the cap in the ambient set, and then bwrap refuses to run,
  which breaks glycin (gdk-pixbuf's JPEG loader, i.e. swaybg's wallpaper).
- `kwin_wayland --no-lockscreen`: KWin locks the screen after 5 idle minutes and hides the Hyprland window. Hyprland then gets
  no frame callbacks and stops drawing: VNC freezes on the last frame and grim hangs.
- `podman run --init`: `sleep infinity` as PID 1 doesn't reap, and the top bar's scripts pile up as zombies.
- `QT_QPA_PLATFORM="wayland;xcb"` in the commands' environment, as hyprland.lua sets it: `qs log` and `qs ipc` only find
  instances with the same display connection.
- `cursor.no_hardware_cursors` in the container's `local.lua`: KWin would draw the cursor outside Hyprland's frames, so moving
  it wouldn't update the VNC image. wayvnc runs with `-r` (the cursor drawn into the image): Remmina showed none without it.
- wayvnc is Fedora's 0.9.1 rebuilt with one upstream change (first stage of the Containerfile): Hyprland fails a cursor
  capture frame when the cursor changes shape, e.g. on a click, and 0.9.1 then exits, dropping the viewer. 0.10 only logs it,
  but needs neatvnc/aml 1.x. The rebuild can go once Fedora ships 0.10.
- A file mounted inside the read-only repo needs a file to mount over, and Podman would create a missing one in the repo
  itself, owned by a subordinate uid. `up` makes an empty `local.lua` / `xdph.conf` instead when the repo has none, and
  `down` removes them again (only if still empty). They are git-ignored.
- The image is labelled with a hash of the Containerfile and the package lists; `up` rebuilds it when that changes.
  `nightdrive sandbox build` rebuilds it by hand.
