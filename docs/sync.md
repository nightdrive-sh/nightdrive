# Settings on several machines (plan)

**Not built yet.** This page is the plan for `nightdrive sync`; it becomes the guide once sync works.

`nightdrive sync` makes most settings the same on every machine you use: the theme, the top bar, keys, the launcher,
your mail and calendar accounts. What belongs to the hardware stays with each machine: displays, mice, keyboards and
audio devices. It runs when you run it; nothing syncs in the background.

## How it works

- **Where a file is decides whether it syncs.** Shared settings live in `~/.config/nightdrive/settings/`; everything
  else, `~/.local/state/nightdrive/` and the rest of `~/.config/nightdrive/` among it, stays on its machine. There is
  no list of what syncs beside the folder itself.
- **The folder is a git repository**, so every machine has the whole history and merges changes itself.
- **Nightdrive Hub carries it**: your own small server, the same one that syncs the apps' data (Tasks, Notes). Each
  machine uploads only its own file, `<machine>.bundle` (a *git bundle*: the repository's history in a single file),
  and downloads the others'. As no two machines ever write the same file, the Hub needs nothing of its own for settings.
- **A sync** commits this machine's changes, downloads the others' bundles, merges them, applies what changed (the
  tables below) and uploads its own bundle.
- **A conflict is shown, never guessed**: the same setting changed to different values on two machines since they last
  synced. Sync stops before applying anything and shows both values; you pick one for each.
- **Joining**: `nightdrive sync join` (once the machine has joined the Hub) names the machine, by default its hostname,
  which no other machine may use, and takes the settings already on the Hub. This machine's earlier values stay in
  the history.

## Folders

```
~/.config/nightdrive/settings/    the git repository that syncs
  theme.json  bar.json  …         one file per area (the tables below)
  mail/  calendar/  claude/  …    an app's own files in a folder of its own
  programs/                       what to install: dnf.txt, flatpak.txt, plugins.txt
  machines/<machine>/             one machine's own values over the shared ones
~/.local/state/nightdrive/sync/   this machine's name, the last sync, the bundles downloaded
```

A file in `machines/<machine>/` wins over the shared file of the same name, only on that machine: a JSON file key by
key (only the keys it has), any other file whole. Programs read settings through one helper per language (Python, shell,
QML) that does this overlay, and a change is written to the override when this machine has one for that key, else to
the shared file.

## File format

- **JSON, written the same way every time**: keys sorted, two-space indent, one key per line, a newline at the end, so
  a change is one readable line in the history.
- **Merged key by key** (a git merge driver set in the repository's `.gitattributes`): changes to different keys on two
  machines merge by themselves, even keys next to each other, and objects merge the same way inside. A list is one
  value, except a list of things that has no order (startup apps, hidden bar modules), which merges as a set: what
  either machine added or removed. The same key changed to two values is a conflict.
- **Other text files** (the accounts' `.conf` files, Claude's write instructions) merge line by line, as git does. The
  program lists have an id a line, sorted, and merge as sets.

## What syncs

| Setting | Now | In `settings/` | Applied with |
|---|---|---|---|
| Theme | `~/.local/state/theme-color`, `nightdrive/theme-look.json`, `theme-name` | `theme.json` | `theme apply` |
| Your themes | `~/.config/nightdrive/themes/` | `themes/` | – |
| Top bar look | `~/.local/state/bar-opacity`, `bar-icons`, `bar-highlight`, `bar-icon-opacity` | `bar.json` | `bar-style apply` |
| Top bar modules | `bar-items.json` | `bar.json` | – (watched) |
| Clock | `clock-mode`, `date-style` | `clock.json` | – (read at each update) |
| Wallpaper | `~/.local/state/wallpaper/current` (a link) | `wallpaper.json` (the image's name) | `wallpaper restore` |
| Launcher | `launcher.json` | `launcher.json` | – (watched) |
| Launcher's apps | `apps.json` | `apps.json` | `sync-apps` |
| App shortcuts | `app-keys` | `keys.json` | `hyprctl reload` |
| Startup apps | `autostart` | `autostart.json` | – (next login) |
| Notifications | `notifications.json`, `sounds`, `net-watch` | `notifications.json` | – (watched, read when used) |
| Screensaver | `idle` | `idle.json` | `idle start` |
| Region | `~/.config/locale.conf` | `region.json` | `nightdrive region set` |
| Browser | `~/.config/nightdrive/firefox` | `firefox.json` | `firefox-prefs apply` |
| Places | `~/.config/nightdrive/places.json` | `places.json` | – |
| Snippets | `~/.config/nightdrive/snippets.json` | `snippets.json` | – |
| Text from a screenshot | `~/.config/nightdrive/ocr-languages` | `screenshot.json` | – |
| Translate | `~/.config/nightdrive/translate/` | `translate/` | – |
| Files | `~/.config/nightdrive/files/` | `files/` | – (when it starts) |
| Companion's buttons | `~/.config/nightdrive/companion.json` | `companion.json` | – |
| Claude's access | `~/.config/nightdrive/claude-access.json`, `claude-allowed.json` | `claude/` | – |
| Claude writes | `claude-write.json`, `~/.config/nightdrive/claude-write.txt` | `claude/` | – |
| Claude in the bar | `claude-bar-mode*`, `claude-sessions-bar` | `claude/bar.json` | – (watched) |
| Home | `home.json`, `home-favorites`, `~/.config/nightdrive/home-assistant-networks` | `home.json` | – (watched) |
| Mail | `~/.config/nightmail/` | `mail/` | – (when it starts) |
| Contacts | `~/.config/contacts/accounts.conf` | `contacts/` | – |
| Calendar | `~/.config/calendar/calendars.conf`, `colors.json` | `calendar/` | – (its next sync) |
| Recorder | `~/.config/recorder/settings.json`, but the mic | `recorder/` | – |
| Programs | – | `programs/` | the missing ones installed |

Without a folder, the files are in `~/.local/state/nightdrive/`. Region and Browser keep writing the files other
programs read (`locale.conf`, Firefox's profile): those are written from the setting, not synced themselves.

## What stays with each machine

| | Why |
|---|---|
| Displays: `display`, `arrangement`, `virtual-displays`, `config/hypr/local.lua` | the machine's own screens, scale and keyboard |
| Mouse wheel speed: `mouse-scroll` | the mouse |
| Audio: `eq-last`, `airpods/`, `anc/`, `max-volume/`, `jack/` | the machine's audio devices |
| Night light: `nightlight` | on or off for the screen you are at, like a lamp |
| Plugins turned off: `plugins-off/` | a plugin useless on one machine may be needed on another |
| Recorder's mic | the machine's microphones |
| VNC Display: `~/.config/nightdrive/vnc-display/` | the devices paired with this machine, and its key |
| Backup: `backup.conf`, `backup-excludes.txt` | each machine backs up its own disk |
| Claude: `claude-leads`, `mcp-install.json` | the sessions running here; where Nightdrive is installed |
| The update channel | the branch of this machine's checkout |

## What never syncs

- **Secrets**: passwords stay in each machine's keyring (`secret-tool`), Home Assistant's token in its file. After a
  sync brings a mail, contacts or calendar account, sync says which ones still need their password on this machine.
- **History and one-time state**: Claude's undo log, usage, questions and leads; Deck's and Tasks' undo and trash;
  reminders and scheduled runs (they fire on the machine that made them, else twice); seen places, failed units,
  crash reports muted, the welcome and the apps once offered, plugins' installed markers, the launcher's history.
- **Files written from settings**: `~/.cache`, GTK and dconf, `hypridle.conf`, `plugins.d/`.
- **App data**: Tasks, Notes and the rest go through the Hub's own sync, by file, not by `nightdrive sync`.
- **Deck's folder** (`~/.config/deck`): it holds Deck's data (curations, the shelf, history) and its API keys with its
  few settings. It is data for the Hub's app sync, not settings.
- **Your private additions** (the git-ignored local slots): they are already a repository of your own.

## Decisions

- **Plugins**: which are installed is a program list (`programs/plugins.txt`): a missing one is installed, unless it
  doesn't fit the machine (its `plugin.conf`). Off is per machine (above).
- **Programs**: only added, never removed by sync; a package for another architecture is skipped.
- **Startup apps** are shared; an app not installed is skipped.
- **Wallpaper** is shared by name: Nightdrive's own images work everywhere, one of yours (`~/Pictures/Wallpapers`) only
  where it is; elsewhere the wallpaper stays as it was.
- **Screensaver** times are shared, a preference like the theme. A machine that wants others overrides them.
- **Mail, Contacts and Calendar**: accounts and settings are shared, signatures with them; passwords are not (above).
