# Nightdrive

**A keyboard-driven Hyprland desktop for Fedora, on an Apple Silicon Mac (Fedora Asahi Remix) or a PC.**
Mac-style ⌘ shortcuts, one launcher for everything, a top bar of thoughtful little menus, and a synthwave look.

![Nightdrive: Firefox, the Deck window playing FM-84, Mail and the Launcher on top](docs/screenshots/desktop.jpg)

**Hi, I'm [Jari Lehtinen](https://github.com/jarilehtinen).** I've used a Mac for over 20 years. Every year or so I've tried a Linux distro or two, but none of them quite
stuck. Omarchy came closest, but I wanted something built entirely around my own preferences and the apps I actually use.
In my day job as a web developer, user interfaces and ease of use are at the core of what I do, and that's what I wanted from
my desktop too: ⌘ shortcuts, a launcher like Spotlight, a menu bar that just works, only faster and lighter.
So I installed Fedora Asahi on my MacBook Pro and built Nightdrive, evening by evening and with a lot
of help from Claude Code.

> **Work in progress.** Nightdrive is my daily setup, published so others can use it or borrow from it. It's used every day on
> a MacBook Pro 14″ (M2 Max), and tested on a PC and in a virtual machine.
> Feedback, issues and ideas are very welcome.

## Why Nightdrive?

[Hyprland](https://hypr.land) is a great tiling compositor, but on its own it's a toolkit: no bar, launcher, theme or apps.
Nightdrive puts all of that together into one opinionated desktop.

- **⌘ is the main key.** ⌘ is the Super key: Command on a Mac, the Windows key on a PC.
  ⌘C / ⌘V / ⌘X work in every app, including the terminal. ⌘S saves, ⌘W closes, ⌘Q quits, ⌘Space opens the launcher.
- **Caps Lock is Hyper, the app key.** Hyper + a letter opens an app or brings it to the front: Hyper+B the browser,
  Hyper+F Files, Hyper+M music. No app uses Hyper itself, so the keys are yours: pick the app for any letter or digit
  in the launcher (Settings › Apps › App shortcuts).
- **Fits the machine it's on.** The installer recognises an Apple Silicon Mac, a PC or a virtual machine and sets it up to
  match: the keyboard layout you picked when installing Fedora, the graphics driver (NVIDIA too), the display scale. On a
  MacBook the top bar sits in the notch area, the top-row keys control volume, brightness, the keyboard backlight and
  dictation, and sleep is tuned for Asahi.
- **Everything is a keystroke away.** One launcher handles apps, passwords, clipboard history, emoji, screenshots, settings,
  installing packages and power. You rarely need a terminal for everyday things.
- **Simple and readable.** Plain config files, a few small scripts, and comments that explain *why*.

## Highlights

### A launcher for everything

**⌘Space**, or the N█ logo at the top left of the bar (Settings › Top bar › Logo hides it), opens the launcher. It holds apps, 1Password items (copy a password, username or one-time code), clipboard history,
an emoji picker, screenshots, a colour picker, every keybinding, settings, `dnf` install / remove, one-click updates, and
power actions. Search from the top level finds all of these. While music plays, a player row sits above the list. Type a
question and press ⌘⌥Enter to send it straight to Claude Code. Search "Rename current space" to give the workspace you're on
a name in the bar instead of its number, for as long as it has windows.

It is a calculator too: type `3*8`, `(12+4)/3`, `15% of 80`, `5 km in miles` or `100 eur in usd` and the answer is the
first row; Enter copies it. [qalc](https://qalculate.github.io) does the maths, units and currencies (exchange rates
refreshed once a day). Settings › Launcher › *Decimal comma in results* answers `3,5` instead of `3.5`; you can type either.

![The launcher](docs/screenshots/launcher.jpg)

### Menus you want to click

Click an icon and a small menu opens under it: sound and output devices, Wi-Fi (and Ethernet while a cable is in use,
with your wired profiles to switch between), Bluetooth, battery and brightness, Tailscale, headphone EQ, system load
and temperatures, the calendar, notifications, music, and **Claude**: your Claude Code sessions (a dot on the icon
when one finished while you were elsewhere; a click goes to its window) and your usage limits. A right click on its
icon changes what it shows: the 5-hour or the weekly usage, with or without the percentage, or the number of sessions.
When a session waits for you, its notification says which one and what it wants, and a permission request can be
answered right there (Allow, Deny). ⌘⇧Space lets you walk through the menus with the arrow keys. On a narrow screen (a
portrait display, a VM's window) the icons that don't fit beside the workspaces go into a **…** menu, the ones farthest
from the clock first, so your order (⌘+drag) decides what stays; the clock and ≡ always do.

![The music, home and headphones menus in the top bar](docs/screenshots/menus.jpg)

### Apps without a terminal, and only the parts you want

System › Install › Software in the launcher searches Fedora's packages and Flathub's apps at once, one row per app (Fedora's
when both have it, Tab in the details takes Flathub's), with command-line tools below and the details before installing.
Browse has Popular (top 100) and categories: Flathub's most installed apps that your machine can run (ARM or x86), and in
Terminals Fedora's terminals first (Ghostty, kitty, Alacritty, foot, Ptyxis). System ›
Remove has Software (both) and Webapps, and its search looks in both.

Nightdrive's own apps (Mail, Contacts, Deck) and Tailscale come with every install; Garage, Nightdrive's app for virtual machines,
waits in System › Install › Recommended. Everything else is an optional part: the
installer adds the ones on by default (or the ones you tick with `./install.sh --choose`), and the rest are under System ›
Install: apps Nightdrive sets up (1Password, Home Assistant…), ready-made web apps with a keybinding, and plugins for
desktop features. A part that isn't installed doesn't show anywhere: no launcher level, bar icon or keybinding.

Updates come in a notification with an **Update** button, which updates Nightdrive and the system in one go.

### A drawer for what you want at hand

⌘⇧D drops the active window into the drawer, and ⌘D slides the drawer up over your windows, dimming and blurring the rest.
⌘D again puts it away. ⌘⇧D in the drawer sends the window back to the workspace and place it came from. It suits notes,
a to-do list or a chat you want one keystroke away without giving them a workspace of their own.

![The drawer empty, and with a terminal and Files in it](docs/screenshots/drawer.jpg)

### Little things that add up

- **Shelf**: drag a file to the top edge of the screen to park it, then drag it into another app (like Dropover / Yoink).
- **Dictation**: hold F5 (or Fn on a Mac), speak, and let go. It runs fully offline with Voxtype and Parakeet ([setup](docs/dictation.md)).
- **Claude writes**: select your notes or a rough draft in any app (a chat, a form, a mail) and press ⌘⇧C. Claude writes
  it out in a tone that fits the place, in the same language, and shows it in the middle of that window (of the screen
  when the window fills most of it): Enter puts it in place of
  the selection, ⌘⇧C again writes another version, Esc cancels (the card's buttons do the same). With nothing
  selected (an empty document), the card asks what to write ("a thank-you note to the team"), and Enter inserts it at
  the cursor. Only the selection, or what you typed, and the window's name and title are sent, never from password
  managers or private browser windows. In a Claude Code session it writes your prompt, and Enter inserts it at the
  cursor. In a terminal (turn it on in Claude writes' settings) you
  select what you want done, like "find the text files that mention jari", and get the command on the command line,
  with a warning if it deletes, overwrites or needs root; it runs only when you press Enter. To give it context, select
  the message you're answering together with your draft. launcher › Settings › Claude writes (or the Claude menu's button) sets
  the model (Sonnet by default) and your own instructions, sent with every request ("a relaxed tone", "end emails with
  my name"): type one there, or turn on an example. Apps of your own can be left out there too.
- **Snippets**: text snippets in launcher › Tools › Snippets; Enter pastes one. Turn on auto-expand and typing a trigger
  anywhere replaces it with the text. A text can have several lines (an email signature): Shift+Enter adds a line break,
  shown as ↵, or `nightdrive snippets set s# - < signature.txt` reads one from a file.
- **From your phone** (experimental plugins): [LocalSend](plugins/localsend/README.md) receives files from a phone after
  you accept them in a notification, and [AirPlay Receiver](plugins/airplay-receiver/README.md) mirrors an iPhone, iPad or
  Mac into a window. [Ferry](plugins/ferry/README.md) is a
  mailbox over Tailscale: drop files on its top bar icon and they wait for the phone, which needs no app, only a web page
  on its Home Screen.
- **[Screen Mirroring](plugins/mirroring/README.md)**: mirror the screen to an Apple TV or an AirPlay TV from the display menu or the launcher (search
  "airplay"), with sound. Google Cast works from Chromium (⋮ › Cast…). Sharing the screen, for these and video calls, asks
  in a themed window: the whole screen or one window.
- **Themes**: seven colours that change the whole desktop at once, two synthwave wallpapers and your own (Settings › Theme).
  GTK windows such as the file picker and Files follow the colour too, and so does the password prompt for admin rights
  (polkit): an app already open shows it once reopened.
- **Screensavers**: a synthwave sunset and a falling-characters rain, both drawn in the terminal, and a big clock whose
  digits slide up as the minutes change.
- **Background apps**: ⌘W only hides chat apps and the music player, so they keep running. Their shortcut brings them straight back.
- **Closed by mistake?** ⌘⇧U opens the window you closed with ⌘W again, in the same place. A terminal comes back in the
  same folder, with Claude Code in the same conversation. Press again for the one before it.
- **Battery ran out?** When the battery is low (under 20 % as the laptop goes to sleep, and each minute from 5 %), the open
  windows are kept. If it runs out, the next login asks whether to open them again, each on its workspace.
- **Web apps**: turn any site into an app window from the launcher (System › Install › Webapp), and remove one in System ›
  Remove › Webapps (its logins go with it). Their notifications come with the web app's own name and icon, not Chromium's.
  A link to another site opens in your default browser (Firefox), not in Chromium; the web app's own pages stay in it.
- **Default apps**: which app opens links, mail, folders, text, code, images, video, music, PDFs and calendar files, and
  which terminal ⌘Enter opens, in the launcher (Settings › Apps › Default apps, or `nightdrive defaults`). Hyper B, F and E open
  the browser, Files and Email you chose.
- **App shortcuts**: which app Hyper + a letter or digit opens, in the launcher (Settings › Apps › App shortcuts, or
  `~/.config/hypr/scripts/app-keys`). Your choice replaces a default, Nightdrive's or a plugin's, and the key list shows
  it. The other shortcuts are in the config files ([Make it yours](#make-it-yours)).
- **Mouse**: the mouse wheel's scroll speed, from 0.5× to 3×, in the launcher (Settings › Mouse). It applies right away
  and leaves the trackpad's speed as it is.
- **Remote login**: SSH into this computer from another one, off by default like on a Mac. Turn it on in the launcher
  (Settings › Remote login). It works over Tailscale from anywhere, and on the networks you allow: the one you turn it on
  at, and each new one asks with a notification (safe at home or work, not at a café). The page's second switch changes
  the answer for the network you are on.
- **Login apps**: you choose what starts at login in the launcher (Settings › Apps › Startup, or ⌥Enter on an app). Background
  apps start hidden. Only 1Password (if installed) is on by default, because its SSH agent and the Passwords level need it.
- **Login screen**: a password-only greeter that matches the theme, for the user who installed Nightdrive (`--no-greeter`
  keeps the distribution's own, or gives a text login where there's none). Another user logs in from the text console
  (Ctrl+Alt+F3, with Fn on a Mac keyboard) or with the text login (`config/greeter/switch.sh text`). The same screen is the
  lock. If it ever dies (Hyprland's "lockscreen app died" screen), it comes back by itself, still locked; if it doesn't,
  ⌃⌥F3 starts it again.

![Screensavers: synthwave sunset and rain](docs/screenshots/screensavers.jpg)

## What's included

| | App | How it fits in |
|---|---|---|
| Window manager | [Hyprland](https://hypr.land) | Lua config, Mac-style keybindings |
| Bar, menus, launcher | [Quickshell](https://quickshell.org) | one themed shell for the top bar, its menus, launcher, OSD and shelf; an orange microphone and camera in the bar while an app uses them (MacBooks have no microphone light), the microphone filling up with the input level, their menus name the apps |
| Terminal | [kitty](https://sw.kovidgoyal.net/kitty/) | ⌘Enter, opens in `~/Projects`; Mac copy and paste; Ctrl+click opens a link, or a file or folder path in the output (Claude Code's too): a folder in Files, a file in the code editor at its line (`file.py:42`). Another terminal (Ghostty, foot, Alacritty, WezTerm) in Settings › Apps › Default apps: it opens everywhere kitty did, with its own settings and colours |
| Browser | Firefox | tabs below the address bar, no tab bar while a window has one tab, links from other apps in a new window, starts with an empty window rather than the last session's tabs (all three in launcher › Settings › Apps › Firefox), themed UI |
| Mail | [Mail](plugins/mail/README.md) (Nightdrive's own, over notmuch and mbsync) | quiet reading, notifications you can answer from, replies written by Claude for you to read first |
| Mail, alternative (optional) | Thunderbird | themed, with a minimal toolbar ([details](docs/thunderbird.md)) |
| Music | [Deck](plugins/deck/README.md) (Nightdrive's own Spotify player, needs Spotify Premium) | bar icon, music menu, player row in the launcher, media keys |
| Virtual machines (optional) | [Garage](plugins/garage/README.md) (Nightdrive's own, over qemu and KVM) | Hyper G; ready-made Fedora VMs or an ISO, snapshots to go back to |
| Passwords (optional) | [1Password](plugins/1password/README.md) + `op` CLI | Passwords level in the launcher, SSH agent |
| AI | [Claude Code](https://claude.com/claude-code) (the installer sets it up; log in once with `claude`) | ⌘⌥Enter in `~/Projects`, ask from the launcher, sessions and usage limits in the bar |
| Dictation | [Voxtype](https://github.com/peteonrails/voxtype) (Parakeet) | F5 / Fn push-to-talk, recording card on screen |
| Network | NetworkManager, BlueZ, [Tailscale](plugins/tailscale/README.md) | Wi-Fi, Bluetooth and Tailscale menus |
| Audio | PipeWire, [EasyEffects](https://github.com/wwmm/easyeffects) | output switching (AirPlay speakers too), EQ presets for headphones; the headphone jack asks whether headphones or speakers went in, keeps a volume for each and starts quiet until you answer; Sony and AirPods listening mode, AirPods battery per pod and case and their own settings; the headphones' microphone in the Sound menus or Use for › Calls in the headphones menu (headset mode; another microphone or Use for › Music switches back to music mode, and music started in headset mode offers it in a notification) |
| Screen Mirroring (optional) | [doubletake](https://github.com/omarroth/doubletake) (AirPlay, built by `plugins/mirroring/install.sh`) | Settings › Display; experimental, picture limited to 1080p (no hardware encoder on Asahi) |
| Notifications | Quickshell | app icon and time on every notification, its app's buttons in the popup and in the history (until the app closes it), history and do not disturb in the bar; a warning with the charge left when the battery drops to 10 % and 5 % (gone once the charger is in); how long they show and their sounds in launcher › Settings › Notifications; with Settings › Crash reports on, a crashed app's notification has Ask Claude, which finds out why, and Mute for 15 minutes (a crash loop while you test) or for good |
| Sounds | Nightdrive's own, made from scratch (`sounds/generate.py`: no samples) | notification sounds to choose from; the desktop's own: a tick at the new level on each volume step, a shutter for a screenshot, the charger in, low battery, a device in or out (USB, Bluetooth), a wrong password or a launcher row that does nothing, lock, log out and shut down; do not disturb silences the ones that happen by themselves (charger, battery, devices); launcher › Settings › Notifications › System sounds and Volume key tick turn them off |
| Files and images | Nautilus, Loupe | images open in Loupe, a simple viewer like Preview |
| Markdown | [Apostrophe](https://apps.gnome.org/Apostrophe/) (Flatpak) | `.md` files open in it, themed editor |
| Messaging | [Telegram Desktop](https://desktop.telegram.org) (Flatpak, install it from Install › Software) | native Wayland app, keeps running in the background like 1Password |
| Web apps | Chromium app windows | add your own, or a ready-made one with a keybinding: WhatsApp, Slack, Teams, YouTube (Install › Webapp) |
| External display | Hyprland | workspaces 1–9 on the external display, one on the laptop's screen (⌘0, a laptop icon in the bar); with the lid closed only the external display is used, and the login screen shows on the screen you're on; where the laptop's screen is (below, above, left or right of the display, for the pointer to cross where they meet) in launcher › Settings › Display |
| Lock and idle | the login screen as the lock (Quickshell), hypridle | screensaver after 10 min, lock after 30 min (screensaver and screen-off times: Settings › Screensaver) |
| Smart home (optional) | [Home Assistant](plugins/home-assistant/README.md) | Home in the launcher: rooms and their devices, Enter turns one on/off or runs a scene, ←/→ sets a light's brightness; pinned devices in the top bar's Home menu; the webapp. Local, Tailscale and Nabu Casa addresses tried in order |
| Phone (optional) | [LocalSend](https://localsend.org) receiver, [UxPlay](https://github.com/FDH2/UxPlay), Ferry (own, over `tailscale serve`) | files and text from a phone, asked first in a notification; an iPhone, iPad or Mac mirrored into a window; a mailbox both ways with a web page and Web Push. All experimental |
| [Mac Keyboard Shortcuts](plugins/keyd/README.md) (optional) | [keyd](https://github.com/rvaiya/keyd), a Nautilus extension | ⌥⌫ deletes a word, ⌘⌫ to the line start; Files like Finder: Enter renames, ⌘O opens, ⌘⌫ to the trash |
| Optional parts | everything marked optional above, Jottacloud, VS Code | chosen when installing; the rest later in launcher › System › Install (Recommended: apps Nightdrive sets up; Webapp; Plugins: desktop features like Screen Mirroring) or `nightdrive plugins` (`plugins.txt` and [`plugins/`](plugins/README.md)). A part that isn't installed doesn't show anywhere: no launcher level, bar icon or keybinding. One installed later (the launcher, `dnf`, Flatpak) shows up by itself |

## Requirements

One of these, with a minimal Fedora 44: Nightdrive adds what the desktop needs, nothing else. The installer tells which
machine it's on and sets it up to match.

- A **PC** (x86_64) with **Fedora 44** from the [Everything netinstall image](https://fedoraproject.org/misc/), with
  *Fedora Custom Operating System* picked in its Software Selection, and NVIDIA, AMD or Intel graphics. See
  [docs/pc.md](docs/pc.md) for the install and what differs from a Mac.
- An **Apple Silicon Mac** (M1 or M2 series) with **[Fedora Asahi Remix](https://asahilinux.org/fedora/) 44**, its
  **Minimal** image (one of the choices in the Asahi installer). Used daily on a MacBook Pro 14″ with an M2 Max; other
  models should work, but you may need to adjust a few values (see [Make it yours](#make-it-yours)).
- A Fedora 44 **virtual machine**, e.g. in Parallels on a Mac or with qemu on an Asahi Mac ([docs/vm.md](docs/vm.md)).

The KDE edition of either (Fedora Asahi Remix with KDE Plasma, Fedora 44 KDE) works too, as Nightdrive was first built on
it: KDE stays, as a fallback session, until `nightdrive minimal` takes it away ([Install](#install)).

Claude's features (Claude writes, Ask Claude, Mail's Reply with Claude, Deck's Curated, setting things up with Claude in
Welcome to Nightdrive) need a paid Claude plan, Pro or Max. The rest of Nightdrive works without one.

## Install

On a fresh Fedora 44 (above), logged in as your user on its text console, with a network connection (Wi-Fi:
`nmcli device wifi connect "Network name" --ask`):

```sh
curl -fsSL https://nightdrive.sh/install | bash
```

That runs [`bootstrap.sh`](bootstrap.sh): it installs git, clones Nightdrive into `~/dotfiles` and starts its installer.
`bash -s -- --dev` clones the dev channel instead of the stable one, and the installer's options in the table below go
after `--` too (`bash -s -- --choose`). The same by hand:

```sh
sudo dnf install -y git   # not in a fresh install
git clone https://github.com/nightdrive-sh/nightdrive.git ~/dotfiles
cd ~/dotfiles
./install.sh              # asks nothing: system update, packages, fonts, the notch setting, config links, Claude
                          # Code, Tailscale, Mail, Contacts, Deck, login screen and the default optional parts
```

It tells which machine it's on and then runs unattended (sudo asks for the password once at the start); the system
update takes a while. On a Mac it first asks for the keyboard layout, if it's still the Minimal image's `us`: the login
screen's password is typed with it (`--keyboard "fi mac"` answers in advance). A minimal Fedora gets what a desktop
edition would have: it boots to the login screen, the firewall has the desktop's settings as on Fedora KDE (so LocalSend
and AirPlay are reached), and SSH is off until you turn on Remote login (Launcher › Settings), unless you install over
ssh. Claude Code, Tailscale, Mail, Contacts and Deck come with every install, like the rest of the desktop: each stays quiet until
you set it up. The optional parts that are on by default (Apostrophe, YouTube) come too, and the rest can be added later from the
Launcher (System › Install) or with `nightdrive plugins install ID`.

To pick the optional parts yourself, run `./install.sh --choose`: it lists them first (a number toggles one, Enter
continues):

```
Machine: Apple Silicon Mac (Fedora Asahi Remix, keyboard: fi mac)

  Nightdrive apps
   1 [x] Contacts          Your iCloud and Google contacts in a window of their own, kept in sync
   2 [x] Deck              Spotify player (needs Premium), Launcher and top bar
   3 [ ] Garage            Virtual machines: start, snapshot and restore them
   4 [x] Mail              Mail over notmuch: quiet reading, notifications, Claude's replies

  Recommended apps
   5 [ ] 1Password         Password manager: Launcher › Passwords, op CLI, SSH agent
   6 [x] Apostrophe        Markdown editor (Flatpak), opens .md files
   …

  Web apps
  12 [ ] Slack             Slack as a web app (Hyper+S)
   …

  Plugins
  16 [ ] AirPlay Receiver  Mirror an iPhone, iPad or Mac here (UxPlay, experimental)
  17 [ ] Ferry             Files and text both ways with your phone over Tailscale, no app (experimental)
   …

  22 [ ] Install all       every optional part above

  23 [x] Remove services   28 installed packages a Mac doesn't use: realmd sssd-common sssd-kcm nfs-utils …
```

The last row is a Mac's only: the Minimal image's server services (network logins and shares, system logs, crash
reports) and other Wi-Fi chips' firmware, listed in `packages-remove-asahi.txt`.

**Trying it on the system you already use?** Nightdrive doesn't remove your apps: on a Mac only the services above go
(`--choose` unticks them). Your configs in `~/.config` are moved aside to `<name>.bak-<time>`, and on Fedora KDE
`config/greeter/switch.sh off` brings back KDE's login screen.

Home Assistant, if chosen, asks for its address and token at the very end.

Then **reboot**. The Nightdrive boot splash goes straight over to the Nightdrive login screen (greetd + Quickshell): the
desktop starts behind it as its lock, so the screen changes hands only once and doesn't flash black. The login apps start
after the password. If the login screen doesn't start (Hyprland can't, say for a missing graphics driver), a text login
comes up in its place: log in, and `start-hyprland` starts the desktop or shows why it can't. Ctrl+Alt+F3 gives one too.
Until it's fixed, `config/greeter/switch.sh text` makes that text login the login screen, starting the desktop after the
password (type `!bash` at its prompt for a text console instead). On Fedora KDE, KDE stays installed as a fallback and
`switch.sh off` brings back its login screen; on Fedora Minimal, which has none, `off` is the text login. `switch.sh on`
gives the plain login screen that starts the desktop after the password, `switch.sh autologin` the default back (the
desktop behind the login screen).

| Option | What it changes |
|---|---|
| `--no-greeter` | No Nightdrive login screen. On Fedora KDE, keeps KDE's; pick **Hyprland** there (not *Hyprland (uwsm-managed)*). On Fedora Minimal, which has none, a text login (greetd's agreety) that starts the desktop after the password |
| `--no-autologin` | The Nightdrive login screen starts the desktop after the password, instead of being its lock (black flashes at boot) |
| `--no-splash` | Keeps Fedora's boot splash and the GRUB menu (`config/splash/install.sh off` later) |
| `--choose` | Lists the optional parts (and on a Mac the removals) first, to tick or untick |
| `--keyboard "fi mac"` | The keyboard layout and variant for the login screen, the desktop and the text console, without asking (xkb names: `localectl list-x11-keymap-layouts`) |
| `--vm` | The virtual machine settings, if the VM isn't detected as one ([docs/vm.md](docs/vm.md)) |
| `--no-nvidia` | On a PC, leaves an NVIDIA card's driver alone instead of installing RPM Fusion's ([docs/pc.md](docs/pc.md)) |
| `--with 1password,slack` | These optional parts on top of the defaults (`--dry-run` lists the ids) |
| `--without youtube` | The defaults without these; combines with `--with`, and leaves out Tailscale, Mail, Contacts or Deck too |
| `--all` / `--none` / `--defaults` | Every optional part / none / the defaults (Apostrophe, YouTube); Tailscale, Mail, Contacts and Deck come with each |
| `--dry-run` | Shows the optional parts, the packages and system settings it would add and what it would remove, then stops |

At your first login, **Welcome to Nightdrive** opens and asks first whether you have Claude Code (a Pro or Max plan).
With Claude, sign in there first, then it sets up Tailscale, Mail, Contacts and Deck with you, each in a Claude session of its own
that does only that one thing. Without, it shows each one's steps right there, one at a time in plain words. Or choose
*I'll do it myself*: a list of the apps, each opening its README in Apostrophe, and Finish when you're done. Leave what
you don't need; Back in the list asks the question again, Launcher › System › *Set up Nightdrive* (or
`nightdrive welcome`) opens it again, and later logins ask with a notification until you finish it or say not to.

A few things stay manual:
- 1Password: in Settings › Developer, turn on *SSH agent* and *Integrate with 1Password CLI*. The Launcher's Passwords level
  needs the CLI integration.
- Thunderbird, if you chose it: open it once and run `./link.sh` again. It themes Thunderbird's profile, which doesn't exist
  before the first start (Firefox's the installer makes itself).
- Optionally, set up dictation ([docs/dictation.md](docs/dictation.md)).
- More optional parts: Launcher › System › Install (Recommended, Webapp, Plugins), or `nightdrive plugins`. Each opens its
  installer in a terminal (a ready-made web app is added right away); running one again is safe.

`./link.sh` on its own just (re)links the config files and is safe to run again. The repo can live anywhere; `~/dotfiles` is
only a convention.

**Installed on Fedora KDE?** Installs from before Nightdrive moved to Fedora Minimal go on as they are, KDE as a
fallback session. To make one what a fresh install on Minimal is, run `nightdrive minimal --dry-run` first: it lists what
would go (KDE and what only it needed, some 600 packages) and what stays as yours (what you installed yourself), and
changes nothing. Then, from Nightdrive's desktop or a text console (not from Plasma):

```sh
nightdrive minimal   # asks once; --keep kate,okular keeps KDE apps you still use
```

It makes the Nightdrive login screen the one in use first, if KDE's still is (`--no-greeter`: greetd's text login), takes a
read-only btrfs snapshot of the root, and then lets dnf work out what goes: what stays is marked as installed by you, the
rest as a dependency, and `dnf autoremove` removes what nothing that stays needs. The kernel, the boot loader and what
the system needs to start, log in or repair itself (systemd, dnf, sudo, NetworkManager, SSH; on a Mac, Asahi's repos and
boot chain) always stay: if dnf would remove one of them, it stops before removing anything, and once done it checks
that `/boot` still has what it had, and says so if not, before you reboot. KDE's settings in `~/.config` move to
`~/.local/share/nightdrive/kde-config-<time>`, the config files you had changed in `/etc` are listed (`.rpmsave`), and
Wi-Fi networks whose password was in KDE's wallet ask for it again.

The way back is printed at the end and kept in `~/.local/state/nightdrive/minimal-undo.txt`. `sudo dnf history rollback
--ignore-extras ID` puts KDE back with the same versions while the repos still have them (then `config/greeter/switch.sh
off` for its login screen); it may end with *Group state for "" not found*, but the packages are back all the same.
Otherwise the snapshot takes the root's place, `root` here being the root's subvolume (`findmnt -no FSROOT /`):

```sh
sudo mount -o subvolid=5 /dev/<the root's partition> /mnt
sudo mv /mnt/root /mnt/root.minimal
sudo btrfs subvolume snapshot /mnt/root.pre-minimal-<time> /mnt/root
sudo umount /mnt && sudo reboot
```

Once you're happy with Minimal, delete the snapshot, as it holds on to KDE's files: `sudo btrfs subvolume delete
/mnt/root.pre-minimal-<time>`, mounted as above.

### Updating

Nightdrive checks for new changes every six hours and shows a notification with an **Update** button when there are some.
You can also update any time from the launcher (**Update**) or a terminal:

```sh
nightdrive update   # pulls Nightdrive (and Deck), relinks, installs new packages, updates the system, reloads the desktop
```

An install that doesn't have one of Nightdrive's apps yet (Mail, Contacts, Deck) gets it with the update, once: one you remove
afterwards isn't installed again: it is back in launcher › System › Install › Recommended (or `nightdrive plugins
install mail`). Settings › Apps › Nightdrive apps turns one off or on.

It never overwrites your own edits: a repo with uncommitted changes is skipped with a note. On an install older than the
command, run it once as `~/dotfiles/bin/nightdrive update` (a plain `git pull` misses the new links and packages).

Updates come from the **Stable** channel (the `main` branch) unless you pick **Development** (`dev`), which gets every
change first, before it is tested and released into Stable: in the launcher under **Settings › Update channel**, or `nightdrive channel dev`
(`nightdrive channel stable` goes back). Switching stops with a note instead of going over your own changes.

Stable gets the changes as releases, each with notes on what's new: an update that brings one shows its notes at the end,
`nightdrive version` tells which release you have, and every release is in the [changelog](CHANGELOG.md). The launcher's
**System › About Nightdrive** (or search "version") shows the release, the channel and the computer, with links to the
website, the documentation and the GitHub issues.

The same `nightdrive` command reaches the settings from a terminal (`nightdrive` alone lists everything):

| Command | What it does |
|---|---|
| `nightdrive update` | Updates Nightdrive and the system (above) |
| `nightdrive update check` | Only looks for new changes (what the six-hourly check runs) |
| `nightdrive channel` | The update channel, stable or dev; `nightdrive channel dev` switches to it |
| `nightdrive version` | The release you have, and the channel |
| `nightdrive minimal --dry-run` | On an install on Fedora KDE: what turning it into Fedora Minimal would remove, and what stays as yours; without `--dry-run` it does it ([Install](#install)) |
| `nightdrive theme color teal` | Theme colour: violet, blue, teal, green, amber, rose or graphite; aerc (if you use it) gets it too, unless you have picked a styleset of your own |
| `nightdrive theme set background '#181722'` | The look: the background and opacity of the terminals, the launcher, Firefox and Thunderbird, and the window borders and shadows (`inactive-border off`, `shadow-size 8`…); `nightdrive theme look` lists the settings, `default` puts one back; the same with sliders in Theme Editor (launcher › Settings › Theme) |
| `nightdrive theme save "My theme"` | Saves the theme colour and the look as a theme of your own (in `~/.config/nightdrive/themes`); `nightdrive theme themes` lists them with Nightdrive's Default, `use ID` switches, `delete ID` removes one of yours, `reset` goes back to Default; also launcher › Settings › Theme › Themes and Theme Editor's Save as theme |
| `nightdrive wallpaper set <image>` | Changes the wallpaper; `nightdrive wallpaper current` prints it |
| `nightdrive display list` | Each screen's even scales; `nightdrive display scale eDP-1 2` sets one |
| `nightdrive bar-style opacity 80` | Top bar opacity; also `icons`, `icon-opacity` and `highlight` |
| `nightdrive topbar adjust` | Top bar icon and text sizes, half a pixel at a time, live |
| `nightdrive topbar date dmy` | The clock's date: `dmy` 19.10., `mdy` 10/19, `iso` 10-19 or `auto` (the system language's order); also launcher › Settings › Top bar › Date format |
| `nightdrive plugins` | Optional parts and whether each is installed and on; `nightdrive plugins install home-assistant` runs one's installer |
| `nightdrive plugins off ferry` | Hides an installed part from the desktop and stops its services, for one that misbehaves (`on` brings it back; also the switch on its page in the launcher) |
| `nightdrive plugins add <git-url>` | Adds a plugin from someone else's repo, marked external in the launcher; `nightdrive update` keeps it up to date, `nightdrive plugins remove ID` deletes it |
| `nightdrive ask "Fix the clock"` | Opens Claude Code in a new terminal with that as its first message, as ⌘⌥Enter does from the launcher; `--dir ~/dotfiles` starts it in that folder (`~/Projects` otherwise), `--name "Clock"` names the session (as `/rename`), `--effort high` sets its effort level (low to max), `--background` opens it without taking the keyboard from the window you are typing in, on the workspace of the window it was run from even if you have moved to another, with a notification that goes to it; `--workspace 3` opens it on that workspace |
| `nightdrive welcome` | Opens Welcome to Nightdrive: setting up Tailscale, Mail, Contacts, Deck… with Claude (signed in first), each on its own, by hand a step at a time, or from their READMEs (Launcher › System › *Set up Nightdrive*) |

## Keys

⌘ is the Super key (Command on a Mac, the Windows key on a PC). Hyper is Caps Lock: Hyper + a letter opens an app, and
which app is yours to choose (launcher › Settings › Apps › App shortcuts).

| Keys | Action |
|---|---|
| ⌘ Space · ⌘ Enter | Launcher · terminal |
| ⌘ ⌥ Enter | Claude Code (with text typed in the launcher: sends it as the prompt) |
| ⌘ C / V / X · ⌘ S | Copy / paste / cut, in every app · save |
| ⌘ W · ⌘ Q · ⌘ ⇧ U | Close (background apps are only hidden) · really quit · open the closed window again |
| ⌘ ⇧ F · ⌘ ⇧ T · ⌘ ⇧ J | The window: fullscreen · tile or float · split direction (⌘ ⇧ arrows move it) |
| ⌥ Tab · ⌥ ⇧ Tab | The app's next · previous window |
| ⌘ F · ⌘ T · ⌘ J | The app's own: find · new tab · downloads |
| ⌘ 1…0 · ⌘ ⇧ 1…0 | Go to workspace · move the window there |
| ⌘ D · ⌘ ⇧ D | Drawer: show / hide · put the window in it, or take it back out |
| ⌘ ⇧ V · ⌘ ⇧ E | Clipboard history · emoji |
| ⌘ ⇧ C | Claude writes the selected text out, or what you ask for at the cursor, in any app (Claude writes, under [Little things](#little-things-that-add-up)) |
| ⌘ R · ⌘ ⇧ R | Reload · without the cache (browsers) |
| ⌘ ⇧ S · ⌘ ⌥ S · ⌘ ⌥ ⇧ S | Screenshot of a region · of a window · of the screen, to the clipboard (Save in the notification keeps a copy in Downloads) |
| Hyper B / F / P / M / E | Browser / Files / 1Password / Music / Email |
| ⌘ ⇧ Space | Walk through the top bar menus with the keyboard |
| ⌘ + drag | On a top bar icon: move it to another place in the bar |
| ⌘ Esc | Notifications |
| F5 (hold; Fn on a Mac) | Dictation |
| ⌘ ⇧ K | All shortcuts (also in the launcher under *Keybindings*) |

The full list is in [`config/hypr/SHORTCUTS.md`](config/hypr/SHORTCUTS.md).

## Make it yours

- **Machine settings.** The defaults at the top of [`config/hypr/hyprland.lua`](config/hypr/hyprland.lua) are for a
  MacBook's display (scale 2) and a Finnish Mac keyboard. The installer writes the machine's own into
  `config/hypr/local.lua`: on a PC the display scale picked automatically and the keyboard layout Fedora's installer
  set, in a VM settings for it, on a Mac the layout unless it's Finnish. The login screen uses the same layout. A scale picked in the
  launcher (Settings › Display) wins over both, and so does a refresh rate picked there (Automatic is the display's
  preferred mode: a TV that does 120 Hz often prefers 60).
- **X11 apps** (REAPER, Steam, Discord) draw at the screen's full resolution, so they are sharp but small on a scaled
  screen: turn up the app's own scale or zoom in its settings.
- **Per-machine overrides** go to `config/hypr/local.lua`, which git ignores.
  Rounded screen corners (tuned for the MacBook's display) are off; `NIGHTDRIVE = { corners = true }` there turns them on.
- **Keybindings** are in [`config/hypr/bindings.lua`](config/hypr/bindings.lua), a plugin's in its own folder. Apps
  open with Hyper (Caps Lock, `MOD3`) + a letter, chosen in the launcher (Settings › Apps › App shortcuts); a Hyper key
  bound in `local.lua` (`hl.bind("MOD3 + D", …)`) is a default that a choice there replaces.
- **Optional parts** (recommended apps, ready-made web apps, plugins): a one-line part, such as a web app or an app from
  dnf or Flathub, is a line in [`plugins.txt`](plugins.txt), with its keybinding in `bindings.lua`'s `optional` list and
  SHORTCUTS.md (with an `{id}` tag). A part with files of its own (a top bar module and menu, keys, a service, commands)
  is a folder in [`plugins/`](plugins), like [`plugins/ferry`](plugins/ferry). [`plugins/README.md`](plugins/README.md)
  explains how to make one, with a small example to copy. A plugin of your own can live in its own repo, with the
  folder's files at its top: `nightdrive plugins add <git-url>` clones it.
- **Background apps**: apps that ⌘W should only hide are in
  [`config/hypr/background-apps`](config/hypr/background-apps).
- **Reopened terminals**: the programs that ⌘⇧U starts again in a closed terminal (editors and the like) are in
  [`config/hypr/reopen-commands`](config/hypr/reopen-commands).
- **Launcher apps**: only the apps in [`config/fuzzel/apps-allow.txt`](config/fuzzel/apps-allow.txt) are listed. Search finds
  the rest.
- **Private additions**: some things don't belong in a public repo, like work tools or a personal dashboard. You can keep them in
  your own private repo and link them into git-ignored *local* slots. Nightdrive loads them when they exist:

  | Slot | What you can add there |
  |---|---|
  | `config/hypr/local.d/*.lua` | autostart entries, window rules, keybindings |
  | `config/hypr/background-apps.local`, `reopen-commands.local`, `SHORTCUTS.local.md` | more background apps, more programs ⌘⇧U starts again, your own entries in the shortcut list |
  | `config/quickshell/local/` | `<Name>Menu.qml` bar menus, and `LauncherExtension.qml` for your own launcher levels |
  | `config/fuzzel/apps-allow.local.txt` | more apps shown in the launcher |
  | `config/kitty/local.conf`, `config/ghostty/local.ghostty`, `config/alacritty/local.toml`, `config/foot/local.ini` | your own kitty, Ghostty, Alacritty and foot settings (font, size, keys), over Nightdrive's |
  | `config/topbar/local.modules.jsonc`, `status.local`, `local.adjust.conf` | your own bar modules (at the left end of the icons), their status and icon sizes |

## How it fits together

- **Quickshell** draws the top bar and its menus. The modules are listed in `config/topbar/modules.jsonc`. Each one gets its
  state from `config/topbar/scripts/status <name>` (an icon name, a text and a class), and a click opens `<Name>Menu.qml`
  under it. Icons are SVGs: Lucide by name, or `pack:name` from any [Iconify](https://icon-sets.iconify.design) set (fetched
  once). Sizes are in `config/topbar/adjust.conf`.
  Quickshell reloads when one of its files is saved, and a short popup says so ("The top bar reloaded", "restarted", or
  "didn't reload" with the error), so it doesn't go unnoticed.
- The menus use ordinary command-line tools such as `wpctl`, `nmcli`, `bluetoothctl`, `upower`, `tailscale`, `cliphist` and `dnf`.
  There are no daemons of their own.
- The theme script (`config/hypr/scripts/theme`) derives every shade from one colour. It writes a small file for Quickshell,
  fuzzel, hyprlock and GTK (`config/gtk-*/gtk.css` imports it), then reloads them.
- Deck writes its playing state to a small JSON file. The bar, the music menu and the launcher read that file.

## Good to know

- **Known issues** that have a workaround but no fix in Nightdrive yet are listed in [docs/known-issues.md](docs/known-issues.md),
  each with its own issue labelled `known issue`.
- **Hyprland comes from Nightdrive's own COPR.** Fedora's own repositories have no Hyprland, so on every machine the
  installer takes the Hyprland packages from [`@nightdrive/nightdrive`](https://copr.fedorainfracloud.org/coprs/g/nightdrive/nightdrive/)
  (aarch64 and x86_64; specs in [nightdrive-packages](https://github.com/nightdrive-sh/nightdrive-packages)) and limits
  that repository to them. Ghostty comes from there too.
- **Asahi specifics.** The notch area needs the `appledrm.show_notch=1` kernel argument, which the installer sets. The 16 KiB memory
  pages break a few Electron apps, but 1Password works. macOS's partitions (its disk, the boot picker's and the recovery's)
  are hidden from Files' sidebar by a udev rule (`/etc/udev/rules.d/61-nightdrive-apple-partitions.rules`). They are only
  hidden, nothing on the disk changes, and macOS's disk can still be opened by hand (with an APFS driver such as
  apfs-fuse).
- **The Claude menu** reads your plan's limits with Claude Code's own sign-in, so Claude Code must have been run once.
- **Claude writes (⌘⇧C)** sends the selected text (or what you type in its card), and the window's class and title, to
  Anthropic through Claude Code, and only when you press the key. Claude has no tools there, not even your MCP servers
  or claude.ai connectors, and nothing is saved as a session. Its text goes in only after you've seen it, the clipboard
  gets its own content back, and the text isn't kept in the clipboard history.
- **No credentials are stored in this repo.** Tokens stay with each app (Deck, Claude Code) or in 1Password.

## Want to participate?

Nightdrive is work in progress, and help of almost any kind moves it forward:

- **Try it on your machine.** It's used daily on a MacBook Pro 14″ with M2 Max only. A report from a real PC (NVIDIA, AMD
  or Intel graphics) or any other Apple Silicon model is valuable (in Discussions), whether everything worked or something
  broke.
- **Ask or share in [Discussions](https://github.com/nightdrive-sh/nightdrive/discussions):** questions, ideas, how it runs
  on your machine, or a screenshot of your setup.
- **Open an [issue](https://github.com/nightdrive-sh/nightdrive/issues)** for a bug or a rough edge. A screenshot or the output
  of the failing command helps a lot.
- **Send a pull request.** Keep it small and in the spirit of the rest: plain files, comments that explain *why*, and nothing
  personal (that goes in the git-ignored local slots, see [Make it yours](#make-it-yours)). [`AGENTS.md`](AGENTS.md) has the
  working notes, handy for people and coding agents alike. Not running Nightdrive yourself? `nightdrive sandbox` runs the
  desktop in a headless container on Linux with Podman and a GPU, for checks and screenshots ([docs/sandbox.md](docs/sandbox.md)).
- **Wallpaper artists welcome.** There's only so much time, and wallpapers are where I'd most love a hand. The ones in Nightdrive
  were made with ChatGPT image generation for now, and I'd much rather ship art by real artists. If you make synthwave
  art, or know someone who does, and would like to see it on Nightdrive desktops, say hello in
  [Discussions](https://github.com/nightdrive-sh/nightdrive/discussions).

## Credits

Inspired by [Omarchy](https://omarchy.org). Built on [Hyprland](https://hypr.land) and [Quickshell](https://quickshell.org), on top of the [Asahi Linux](https://asahilinux.org) team's work. The colours start
from the [Tokyo Night](https://github.com/enkia/tokyo-night-vscode-theme) palette, and the icons are [Lucide](https://lucide.dev) (ISC).
The wallpapers were made with ChatGPT image generation for now (artists welcome, see [Want to participate?](#want-to-participate)).
The Tailscale logo in the bar is Tailscale's trademark.

## License

[MIT](LICENSE). The bundled Lucide icon font and icons are ISC-licensed.
