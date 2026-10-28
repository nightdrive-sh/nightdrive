# Known issues

Problems found on a real machine that Nightdrive doesn't fix for everyone yet, usually because their cause is in another
project (a driver, an app) or they have been seen on one machine only. Each one is an issue labelled
[known issue](https://github.com/nightdrive-sh/nightdrive/issues?q=is%3Aissue%20label%3A%22known%20issue%22), with what
was seen, the cause, how to check for it in the journal and the workaround. If you run into one too, add a comment (or a
👍) there: a second report is the signal to fix it in Nightdrive itself. Found a new one with a workaround? Open it with
the *Known issue* form.

- **[Wi-Fi takes about a minute to connect after opening the lid (6 GHz)](https://github.com/nightdrive-sh/nightdrive/issues/2)**:
  keep that network on 5 GHz with `nmcli connection modify "<network>" 802-11-wireless.band a`.
- **[AirPlay audio to an Apple TV or HomePod plays nothing (OS 27)](https://github.com/nightdrive-sh/nightdrive/issues/3)**:
  an Apple bug; use Screen Mirroring (Settings › Display), which carries the sound too.
- **[The Space preview in Files flashes a zoomed picture as it opens (Sushi 50)](https://github.com/nightdrive-sh/nightdrive/issues/4)**:
  harmless; the image viewer (Loupe) opens a picture without the flash.
- **[1Password's own keyboard shortcuts do nothing (Quick Access, Autofill)](https://github.com/nightdrive-sh/nightdrive/issues/5)**:
  Hyper P opens the app; its commands (`1password --quick-access`) can get keys in `~/.config/hypr/local.lua`.
- **[iPhone mirroring stops when a screen comes or goes (AirPlay Receiver)](https://github.com/nightdrive-sh/nightdrive/issues/6)**:
  start mirroring again from the phone; the receiver is back by itself.
- **[WezTerm from Flathub doesn't open a window](https://github.com/nightdrive-sh/nightdrive/issues/7)**:
  WezTerm's own nightly builds (`wezfurlong/wezterm-nightly` COPR), not tried here yet.
- **[EasyEffects stops when an autoload file is broken (headphone EQ)](https://github.com/nightdrive-sh/nightdrive/issues/8)**:
  remove the empty or broken file from `~/.local/share/easyeffects/autoload/output`, then choose an EQ again.
- **[The Mac doesn't sleep after an external display was unplugged while it slept](https://github.com/nightdrive-sh/nightdrive/issues/9)**:
  restart the Mac; unplug an external display while the Mac is awake.
- **[An external display on HDMI isn't found when the Mac starts with it plugged in](https://github.com/nightdrive-sh/nightdrive/issues/10)**:
  unplug the HDMI cable and plug it back in, or plug the display in after the Mac has started.

When the cause is fixed and the workaround is no longer needed, the issue is closed and its line here goes.
