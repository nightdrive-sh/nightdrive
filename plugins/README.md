# Plugins

A plugin is an optional part of Nightdrive with files of its own: a top bar icon and its menu, a service, commands,
keys. Each one is a folder, `plugins/<id>/`, and the folder's name is its id. Users choose plugins when installing, or
later in Launcher › System › Install or with `nightdrive plugins`. A plugin that isn't installed, or is turned off,
doesn't show anywhere: no bar icon, menu, keys or shortcut lines.

This page is all you need to make one. [`ferry/`](ferry) is the full example of a bar module with its menu, over an app
that has its own repo and install script; [`localsend/`](localsend) has a service, a command and a Files extension of
its own; [Disk](#a-small-example-disk), at the end, is a small one to copy.

One-line parts (a web app, an app from dnf or Flathub, with no files of their own) stay lines in
[`plugins.txt`](../plugins.txt), with their page in `docs/plugins/<id>.md`. Ids are unique across both.

## What a folder can hold

Only `plugin.conf` and `README.md` are required. The other files are used only while the plugin is installed and on
(`bin/`, `systemd/` and `nautilus-python/` are linked either way, see below).

| File | What it is | Ferry's |
| --- | --- | --- |
| `plugin.conf` | Name, icon, description, how to install it and how to tell it's installed | [plugin.conf](ferry/plugin.conf) |
| `README.md` | Its page: the Launcher shows it, and GitHub (and later the website) the same file. Pictures go in the folder | [README.md](ferry/README.md), [ferry.jpg](ferry/ferry.jpg) |
| `steps.md` | Its setup by hand, a step at a time, for Welcome to Nightdrive without Claude (see [below](#setting-up-by-hand-stepsmd)) | — (Mail's [steps.md](mail/steps.md)) |
| `module.jsonc` | A top bar module | [module.jsonc](ferry/module.jsonc) |
| `status` | The module's state, one line of JSON | [status](ferry/status) |
| `icons/` | The module's own SVG icons, for a logo Lucide hasn't got | — (Tailscale's [icons/](tailscale/icons)) |
| `<Name>Menu.qml` | The menu a click on the module opens (more `.qml` files beside it if it needs them) | [FerryMenu.qml](ferry/FerryMenu.qml) |
| `<Name>Levels.qml` | Its pages in the Launcher, and rows of its own at the root, in the root search and above the search field | — (Deck's [MusicLevels.qml](deck/MusicLevels.qml)) |
| `bindings.lua` | Keys | — (Deck's [bindings.lua](deck/bindings.lua)) |
| `SHORTCUTS.md` | Its lines in the key list (⌘⇧K, Launcher › Keybindings) | — (Deck's [SHORTCUTS.md](deck/SHORTCUTS.md)) |
| `hyprland.lua` | Hyprland settings: window rules, and programs that start with the session | — (Deck's [hyprland.lua](deck/hyprland.lua)) |
| `quit-commands` | What ⌘Q runs on its window instead of closing it, e.g. to stop a player that plays on without one | — (Deck's [quit-commands](deck/quit-commands)) |
| `systemd/` | User units, linked to `~/.config/systemd/user` | — (LocalSend's [nightdrive-localsend.service](localsend/systemd/nightdrive-localsend.service)) |
| `bin/` | Commands, linked to `~/.local/bin` | — (LocalSend's [localsend](localsend/bin/localsend)) |
| `nautilus-python/` | Files extensions, linked to `~/.local/share/nautilus-python/extensions` | — (LocalSend's [localsend.py](localsend/nautilus-python/localsend.py)) |
| anything else | Whatever it needs, used by its own files | [install.sh](ferry/install.sh) (installs Ferry from its repo), [hook](ferry/hook) (Ferry runs it when its box changes) |

`link.sh` links `bin/`, `systemd/` and `nautilus-python/` whether the plugin is installed or not, so its installer can
use them. The rest is picked up by `nightdrive plugins installed`, which installing and turning a plugin off or on run: it
lists the plugins that are on, with their modules, menus and icons, in `~/.cache/nightdrive/plugins.d/`. The bar reads its
modules from there, and Hyprland, the key list and ⌘Q read `bindings.lua`, `hyprland.lua`, `SHORTCUTS.md` and
`quit-commands` straight from the folders listed. Nothing is written into the repo.

## plugin.conf

`key=value` lines; a `#` line is a comment. The keys mean the same as the columns of `plugins.txt` (`version`, `author`
and `order` are the folders' own). `name`, `icon`, `description`, `installed`, `version` and `author` are required
(`nightdrive plugin check` says so); the rest have defaults.

```
# Ferry (README.md). install and installed run in this folder.
name=Ferry
icon=inbox
description=Files and text both ways with your phone over Tailscale, no app (experimental)
default=off
install=install.sh
installed=systemctl --user -q is-enabled ferry.service
units=ferry.service
group=plugin
version=0.3.0
author=@jarilehtinen
```

| Key | What it is |
| --- | --- |
| `name` | Shown in the Launcher and `install.sh`; the README's title is the same |
| `icon` | A [Lucide](https://lucide.dev/icons) icon name |
| `description` | One line. Ending it in `(experimental)` marks the plugin as experimental in the Launcher and on the website (the README needn't say so) |
| `default` | `on`: ticked in `install.sh`'s list; `off` (default): not |
| `install` | A shell command, or a script in the folder, run in the folder in a terminal (it may ask things, and `sudo` works). Running it again must be safe. Default: nothing to install |
| `installed` | A shell test, run in the folder: the plugin is installed while it succeeds. Make it quick: every `nightdrive plugins` runs all of them |
| `packages` | The dnf packages the installer installs and the plugin needs, separated by spaces, e.g. `notmuch isync zenity`. Marked as installed by you once the installer has run (and by `nightdrive update`), so removing something that had pulled one in earlier, such as KDE with `nightdrive minimal`, leaves it in place. Not installed from here: the installer does that, after the repo it may need |
| `units` | User units the installer set up outside the folder, space-separated (Ferry's `ferry.service`, which Ferry's own install writes): `nightdrive plugins off` stops them with the folder's `systemd/` ones |
| `group` | Where it is listed: `plugin` (default, Install › Plugins: a feature of the desktop), `recommended` (Install › Recommended: an app Nightdrive sets up), `webapp`, or `app`: one of Nightdrive's own apps (below) |
| `bundled` | For an `app`: `yes` (default) comes with every install; `no` doesn't (below) |
| `version` | `MAJOR.MINOR.PATCH`, e.g. `1.0.0` (`0.x` while it's experimental). It shows on the plugin's page in the Launcher and on the website, so a bug report can name it. See [Versions](#versions) |
| `author` | Who made it: a GitHub user (`@name`) or a name |
| `setup` | A shell command, run in the folder, that sets the installed plugin up with Claude: Claude Code in a terminal, going through the README's steps with the user. The plugin's page gets a button Set up with Claude (and the key C) for it. For a plugin whose use needs more than its installer can ask, such as Mail's account (`bin/nightmail setup`). Start Claude through `~/.config/hypr/scripts/claude-setup ID NAME`, with your steps on its stdin: it holds the session to them, and Welcome to Nightdrive sees it running. Installed plugins with a `setup` are rows in Welcome to Nightdrive (Launcher › System › Set up Nightdrive) |
| `configured` | A shell test, run in the folder, like `installed`: the setup is done while it succeeds (an account written, a login made). Welcome shows the plugin's row as Done by it. Quick, as `installed`. Without it, a setup counts as done once its Claude session has closed |
| `welcome` | The plugin's row in Welcome to Nightdrive: one line, in plain words, of what setting it up gives you (with Claude or without). Default: `description` |
| `order` | A number, default 50: `install.sh` installs the plugins in this order, and the lists show them in it. Lower goes first; the same order keeps the folders' (alphabetical) order, then `plugins.txt`'s lines. Home Assistant has 90: its installer asks for addresses, so it runs last |

An `app` (Mail, Contacts, Deck, Ferry) is part of Nightdrive, like the apps that come with macOS: every install gets it without asking,
it isn't listed in System › Install while it's installed, and its settings are in Settings › Apps (Nightdrive apps
turns one off or on). One the user removed is back in Install › Recommended, to install again from there.
`nightdrive update` installs an app that an existing install has never had (one made an app later, or a new one), once:
the ids it has offered are kept in
`~/.local/state/nightdrive/apps-offered` (`install.sh` writes the ones it offered, left out or not), and an app the
user removed afterwards is never installed again. Whether a new app comes with Nightdrive or would be bloat there (then
it is `recommended`) is decided for each app. An app that most users wouldn't want on every install, but that is still
one of Nightdrive's own (built on the apps' kit, Settings › Apps once installed), has `bundled=no`: `install.sh` lists
it unticked, `nightdrive update` never installs it, and it waits in Install › Recommended (Garage). Only the repo's own plugins can be apps: `nightdrive update` doesn't
install an external plugin by its group.

Pick `installed` so it follows what the installer did: a unit that is enabled, a command that exists. A plugin with
nothing to install can use `installed=true`, but then everyone who has the folder has it on, which suits an external
plugin (adding it is the choice) better than one in this repo.

## The top bar module: module.jsonc and status

`module.jsonc` is one module in [`config/topbar/modules.jsonc`](../config/topbar/modules.jsonc)'s format (its header
explains every key), with a few differences:

- `name` defaults to the id. `needs` is implied (the id: the module goes when the plugin does), so leave it out.
- `after`: the module it goes right of (`"system"`, `"tailscale"` …), or `before`: the one it goes left of. Either can be
  a list, and the first one that is in the bar counts: Home Assistant's `"before": ["deck", "claude"]`. Without them, at
  the right end.
- `size`: its icon size in px.
- `label` (required) and `glyph` (a Lucide name): its row in Launcher › Settings › Top bar › Items, where it can be
  hidden.
- Its commands (`status`, `right`, `middle`, `drop`) run in the plugin's folder with bash, so `bin/<command>` finds
  the plugin's own command (Ferry's is installed elsewhere: `~/.local/bin/ferry add`).

```jsonc
// Ferry's top bar module; its state: ./status; a click opens FerryMenu.qml; files dropped on the icon go to the box.
{ "interval": 5, "drop": "~/.local/bin/ferry add", "after": "system", "size": 17, "label": "Ferry – Device mailbox", "glyph": "inbox" }
```

`status` is an executable script in the folder (the module runs it without a `status` key). It prints one line of JSON,
`{"icon": "inbox", "text": "2", "class": "active"}`: the icon is a Lucide name (or `pack:name` from Iconify, or the name
of an SVG in the plugin's `icons/`, drawn in `currentColor`: Tailscale's logo), the text comes after it, and the class is one of `off` (dimmed), `warning`, `critical`, `active` (highlighted), `pulse` (highlighted, the icon fading in and out: something in progress) or `stale`.
`"dot": true` adds a small red dot to the icon, for something that waits for you. No icon and no text hides the module. The shared helper prints that line:

```bash
#!/bin/bash
. ~/.config/topbar/scripts/emit          # emit ICON TEXT [CLASS]
systemctl --user -q is-active ferry.service || { emit inbox "" off; exit; }
n=$(jq '[.items[]? | select(.to == "computer" and (.seen | not))] | length' ~/.local/share/ferry/items.json 2>/dev/null)
if (( ${n:-0} > 0 )); then emit inbox "$n" active; else emit inbox ""; fi
```

Keep it fast and quiet: it runs every `interval` seconds. `qs ipc call bar refreshModule ferry` (or
`TopBar.refresh("ferry")` in QML) updates it right away, e.g. after the menu changed something.

## The menu

`<Name>Menu.qml` opens on a click on the module whose name is `<name>` (`FerryMenu.qml` for `ferry`; `"menu"` in
module.jsonc picks another). It is loaded from the plugin's folder, and `import qs` brings the parts the core menus use.
The structure is fixed so that every menu looks like one desktop; what goes inside is free (Deck's player, the
calendar's grid, Ferry's drop zone and QR code are all fine).

- **`MenuHeader` first**: `MenuHeader { width: parent.width; title: "Ferry" }`. Optional `subtitle` (dimmed, on the
  right), an on/off toggle (`showToggle`, `checked`, `onToggled`) and a small button (`action: "Clear"`,
  `onActionClicked`, `actionEnabled`), and an icon button at the right edge (`tool: "settings"`, `toolLabel`, `onToolClicked`:
  Ferry's Settings).
- **Rows are `MenuRow`**: `icon`, `label`, `detail` (dimmed, on the right), `onClicked`. `danger: true` red,
  `active: true` the selected one, `interactive: false` an information row. Rows get keyboard navigation (⌘⇧Space) for
  free.
- **Buttons are `MenuButton`** (Open …, Settings…, Send): a round-ended pill, `icon`, `label`, `onClicked`; `usable:
  false` dims it, `busy` adds animated dots, `danger` makes it red and `gap` gives it more room above (10 where no
  `Divider` sets it apart). Keyboard navigation comes with it too.
- **Section titles are `MenuSection`**: `title`, and an optional `subtitle` on the right (what the numbers below mean).
- **Hint, error and empty-state lines are `MenuNote`**: `variant` `"dim"` (default), `"warning"` or `"danger"`; it
  wraps, and an empty one takes no room. Not a `Text` of your own.
- **Colours only from `Theme.*`** (`Theme.text`, `Theme.dim`, `Theme.primary`, `Theme.accent`, `Theme.warning`,
  `Theme.danger` …), fonts only `Theme.font` and `Icons.family` (icons: `Icons.g("name")`). No hex colours or font
  names: the themes change them.
- **Commands with `Sh`** (`command: [...]` or `script: "…"`, the output in `onResult`), or
  `Quickshell.execDetached([...])` for one that just starts something. Your own command's path:
  `Qt.resolvedUrl("bin/<command>")` without the `file://`; one in `~/.local/bin`, `Quickshell.env("HOME") +
  "/.local/bin/<command>"` (FerryMenu.qml's `ferry`), since Quickshell's PATH may not have that folder.
- `Divider` is the separator line; `Slider`, `BusyDots` and `Plugins.has("tailscale")` (is another plugin on?) are there
  too.
- **A text field** needs the keyboard, which a menu doesn't have by default: `readonly property bool wantsKeyboard`
  true while one shows (Ferry's Aa).
- **Settings with more room** (a window of its own, as AirPods settings and Theme Editor) use the `Setting…` parts, so
  they look and behave alike: `SettingToggle` (`title`, `desc`, `checked`, `onPicked: v => …`), `SettingLevel` (a slider:
  `value`, `to`, `unit`, `lowText`/`highText`, `labelWidth` for the title in front of it; `onPicked` when the mouse
  lets go), `SettingChoice` (a few options side by side: `options`, `current` index), `SettingColor` (swatches in
  `presets`, a hex field and a spectrum; `onPicked: hex => …`), `SettingDropdown` (`model: [{ value, name, swatch }]`,
  `current`, `onPicked`) and `SettingButton` (`text`, `strong` for the main action, `active`). Each one reports the
  change and leaves its value to you: set `checked`, `value` or `current` from what your command reads back.

The skeleton every menu has:

```qml
import QtQuick
import Quickshell
import qs

// What the menu shows and does, in a sentence or two
Column {
    id: m
    width: parent ? parent.width : 320
    spacing: 8
    signal close()                     // emit it to close the menu (after a row that opens a window, say)
    // readonly property int preferredWidth: 340   // a wider card than the default 320

    MenuHeader { width: parent.width; title: "Name" }
    // MenuSection, MenuRow, MenuNote …
}
```

A change to a plugin's menu doesn't reload on save like the core menus: restart Quickshell to see
it (`qs kill; setsid -f qs`).

**Pages in the Launcher.** A `<Name>Levels.qml` is a Launcher level file like the core's (`config/quickshell/*Levels.qml`;
`levels`, `titles`, `parents`, `items`, `activate`, `footer`, `entered`), loaded only while the plugin is on. It may also
have `rootItems` (rows at the Launcher's root: Deck's Music), `toolItems` (rows in Tools: Keep Awake's), `rootRows()`
(rows for the root search: Deck's albums) and `topRow`, a row above the search field (Deck's player), with `topKey(event)` for its keys and `topPress()` for Ctrl+Space.
`inputs` lists its levels whose field is a value being typed, not a search: ⌘⇧V there picks from the clipboard history
into the field.
Deck's [MusicLevels.qml](deck/MusicLevels.qml) has most of them, Keep Awake's [KeepAwakeLevels.qml](keep-awake/KeepAwakeLevels.qml)
is a small one to copy. The same restart applies.

## The page: README.md

The Launcher's page for the plugin (Install › Plugins › the plugin), GitHub's, and later the website's. The name, icon
and description come from `plugin.conf`; the README is the body. Follow this shape:

1. `# Name`, the same as `name` in plugin.conf.
2. One paragraph: what it does for the user.
3. A screenshot, if the plugin has something to see: `![Ferry's menu in the top bar](ferry.jpg)`, the file in the
   folder. The Launcher shows the first picture.
4. How to use it, as a list. A longer page splits it under `##` headings, such as `## On the computer`,
   `## On the phone`, `## In a terminal` and `## Privacy` (Ferry's README); the Launcher shows them as section titles.
   Commands read best as a table (`| Command | What it does |`), which the Launcher shows as items.
5. Last, the fact lines, each on its own line and in this order (the ones that apply, at least one):
   `Homepage: https://…`, `Needs: …`, `Keys: ⌘⇧I` (required when the plugin has `bindings.lua`). The Launcher shows
   them as facts under the text.

The Launcher shows each paragraph and each `- ` item as plain text: links keep their text, `**` and backticks go. Write
each `- ` item on one line, however long (as Ferry's README does): the Launcher ends an item at the line break, and the
rest of it would be a paragraph of its own (`nightdrive plugin check` points out the line).

Commands go in a code block, indented by 4 spaces after a blank line (or in ``` fences), one command a line. The
Launcher shows it in a box with its lines as they are, and a `command   # comment` line with the comment dimmed in a
column beside the commands (under the command when there isn't room), so keep the comments short, as Ferry's are.

## Setting up by hand: steps.md

Welcome to Nightdrive asks first whether you have Claude. Without, Enter on a plugin's row shows its `steps.md` in the
window, a step at a time (without a `steps.md`, Enter opens the plugin's page). Its third answer, *I'll do it myself*,
opens the plugin's `README.md` in Apostrophe instead, so keep the README's setup section complete on its own. Write
`steps.md` for someone new to Linux: what the step is for, then what to do. The first step says why the plugin matters
in Nightdrive. `config/welcome/steps` reads it; Tailscale's, Mail's and Deck's are examples.

- Each `## Title` is a step: its paragraphs (Markdown), at most one fenced code block, and lines of their own:
  - `Ask: key | Label | example`: a field to fill in. `{key}` in a later code block, button or test becomes its value,
    kept only while the window is open; a command that needs one waits until it is filled in.
  - `Edit: ~/path`: the code block is the file's template. Enter writes it, if the file isn't there yet, and opens it
    in the text editor. Without `Edit:`, the code block is a command: Enter runs it in a terminal, y copies it.
  - `Run: Label | command` and `Open: Label | https://…`: a button that runs a command in the plugin's folder, or opens
    a page. `Open:` with a file of the folder's (`README.md`) opens it in Apostrophe, for the details a step leaves out.
  - `Done when: test`: a quick shell test, run in the folder every few seconds; the step shows Done while it succeeds.
- The row counts as done by `configured` in plugin.conf, as with Claude; Finish on the last step marks it started.

## Keys: bindings.lua and SHORTCUTS.md

`bindings.lua` is run by Hyprland's config while the plugin is on. It gets `{ id, dir, mod, scripts }` as `...`: `mod`
is ⌘ (Super), `dir` the plugin's folder, `scripts` the core's `config/hypr/scripts`. One that fails is left out with a
line in Hyprland's log; it can't take the other keys with it.

Which modifier: a key that opens an app is Hyper (Caps Lock) + a letter, `"MOD3 + M"` (Deck); one for a desktop
feature, such as a menu, is ⌘⇧ or ⌘⌥ + a letter. ⌘ + a letter alone belongs to the apps (copy, save, reload…).
In SHORTCUTS.md Hyper is written `Hyper M`.

A plugin's Hyper key is a default: when the user picks an app for the same key (Launcher › Settings › Apps ›
App shortcuts), the core leaves the plugin's binding out and its line out of the key list. Settings › Apps › App shortcuts names
the plugin by its SHORTCUTS.md section, so give the key's line the app's name (`Hyper M  Music (Deck, …)`).

```lua
local p = ...
hl.bind(p.mod .. " + SHIFT + I", hl.dsp.exec_cmd("qs ipc call menu toggle disk"))   -- opens the plugin's menu
```

Check that the key is free in [`config/hypr/bindings.lua`](../config/hypr/bindings.lua) and
[`SHORTCUTS.md`](../config/hypr/SHORTCUTS.md). Then add the same key to the plugin's own `SHORTCUTS.md`, in that file's
format: a `## Section` line, then each key as two spaces, the keys, two or more spaces and the description (lined up at
column 22, as in the core's file). Its lines show only while the plugin is on, so they need no `{id}` tag:

```
## Disk
  ⌘ ⇧ I              Disk: free space and what takes it
```

Hyprland reloads by itself when `nightdrive plugins installed` changes the list of plugins that are on. After editing
`bindings.lua` of a plugin that is already on, run `hyprctl reload`.

## Hyprland settings: hyprland.lua

`hyprland.lua` holds the plugin's other Hyprland settings, such as a window rule. Hyprland's config runs it while the
plugin is on, after the core's settings and before your `local.lua`. It gets `{ id, dir, scripts, start }` as `...`:
`start(cmd)` runs a command once when the session starts, with the desktop's other programs (at the login screen's
autologin, once it is unlocked). One that fails is left out with a line in Hyprland's log.

```lua
-- Deck's window: floating, centred
hl.window_rule({ name = "float-deck", match = { class = "^deck$" }, float = true, size = "720 440", center = true })
```

```lua
-- Screen Mirroring: doubletake's daemon, with the session
local p = ...
p.start("sh -c '[ -x \"$HOME/.local/bin/doubletake\" ] && exec \"$HOME/.local/bin/doubletake\" -daemonize'")
```

A program started with `start` runs from the next login on: the installer starts it for the session it runs in, if
it's needed right away. Keys go in `bindings.lua`, not here (the top bar menu repeats those while it's open). Name a
window rule after the plugin, so it can't replace one of the core's. After editing it, `hyprctl reload`.

## Services and commands: systemd/, bin/ and nautilus-python/

Units in `systemd/` are linked to `~/.config/systemd/user`, files in `bin/` to `~/.local/bin` and Files extensions in
`nautilus-python/` to `~/.local/share/nautilus-python/extensions`, by `link.sh` (and `nightdrive plugins add` for an
external one). A name that something else already has is left alone, so an external plugin can't replace Nightdrive's
commands or services. The installer enables the units (LocalSend's `bin/localsend enable`), and `installed` usually
tests for that. Enable a unit by its path in the folder (`systemctl --user enable --now …/systemd/nightdrive-localsend.service`, as
`localsend enable` does): `systemctl --user disable` removes a linked unit's link too, and the path links it again. Name them
so they can't clash: `nightdrive-<id>.service`, a command named after the plugin. A Files extension runs whether the
plugin is on or not, so it checks that itself (LocalSend's tests its unit and `~/.local/state/nightdrive/plugins-off/<id>`).

## Trying it out

```sh
nightdrive plugins install disk    # runs its installer in a terminal, then gathers its parts
nightdrive plugins installed       # after changing module.jsonc, or adding a menu file
qs kill; setsid -f qs              # after changing its menu
hyprctl reload                     # after changing its bindings.lua or hyprland.lua (SHORTCUTS.md shows right away)
nightdrive plugin check disk       # the rules on this page
```

Or in the headless container (`nightdrive sandbox`, [docs/sandbox.md](../docs/sandbox.md)), which leaves your desktop
alone: a folder put in the container's `~/.local/share/nightdrive/plugins/` is picked up as an external plugin, and its
installed test can be faked there.

## nightdrive plugin check

`nightdrive plugin check [id]` checks one plugin, or all of them without an id, and exits with 1 and the findings if
something is off. `nightdrive sandbox check` runs it too. It checks a plugin folder (the repo's and the external ones):

- The id: the folder's name is letters, digits, `-` and `_`, and no other plugin (or `plugins.txt` line) has it.
- `plugin.conf`: only `key=value` lines and known keys, each once; `name`, `icon`, `description`, `installed`,
  `version` and `author` are there; `default` is `on` or `off`, `group` one of the four, `version` is
  `MAJOR.MINOR.PATCH` and `order` a number; `install` and `installed` parse as shell (`bash -n`).
- The icons are Lucide names: plugin.conf's `icon`, module.jsonc's `glyph`, and the ones `status` prints with `emit`
  (or one of the bar's own in `config/topbar/icons`; a `pack:name` isn't checked).
- `README.md` is there: the `# Name` title is plugin.conf's `name`; at least one fact line, all of them last, each once
  and in order, none empty; `Keys:` when the plugin has `bindings.lua`; each `- ` item on one line; and the pictures
  it shows exist.
- `module.jsonc` parses and has only known keys, no `needs` and a `label`; `after` or `before` (not both) is a name or a
  list of names; the module has a `status` key or an executable `./status`.
- Each `<Name>Menu.qml` opens from a module of the plugin's, and has `MenuHeader` before the rows.
- The QML files have no hex colours or font names.
- `SHORTCUTS.md`'s lines are ones the key list reads (the format above).
- `hyprland.lua` binds no keys: those go in `bindings.lua`.
- The scripts' syntax: `bash -n`, Python's `ast.parse`, and `luac -p` for Lua only where `luac` is installed
  (without it, a note lists the files left unchecked: `sudo dnf install lua`).

For a `plugins.txt` line it checks the eight fields, the icon, `default` and `group`, and `docs/plugins/<id>.md` (if
there is one) as its README, with the same rules as above. Findings are `file:line: message` lines; an unknown id
exits with 2.

## Off and on

A plugin that misbehaves can be turned off without uninstalling it:

```sh
nightdrive plugins off ferry    # the desktop treats it as not installed, and its units are stopped
nightdrive plugins on ferry     # back as it was
```

Off hides its module, menu, Launcher rows, keys and shortcut lines, leaves out its `hyprland.lua`, and stops the units in
its `systemd/`. They stay enabled, so its `installed` test still succeeds, and a drop-in keeps them from starting until
it's on again. The state is an empty file, `~/.local/state/nightdrive/plugins-off/<id>`. The same switch is on the plugin's page in the Launcher
(Tab to it). The commands work even when the bar is stuck: every plugin's QML runs in the same Quickshell, with no
isolation, so a terminal is the way out.

`nightdrive update check` doesn't count commits that only touch the folders of plugins that aren't installed or are off.

## Versions

A plugin's `version` names what a user has, for a bug report: the Launcher shows it on the plugin's page, and
`nightdrive plugins` lists it. Raise it when a release changes the plugin, by these rules:

- **PATCH** (`1.0.0` → `1.0.1`): fixes and small changes. This is the usual step.
- **MINOR** (`1.0.1` → `1.1.0`): something new the user can see or do.
- **MAJOR** (`1.1.0` → `2.0.0`): a change that needs the user to do something, such as running its installer again.
  A plugin starts at `0.1.0` while it's experimental, and goes to `1.0.0` when it isn't.

For the plugins in this repo every release does it (changes are made in `dev`, and `main` gets them only in a
release): `nightdrive release` runs `nightdrive plugins bump`, which raises the patch version of every plugin whose folder
has changed since its version was last set, and commits the bumped `plugin.conf` files with the release. A plugin that
got something new takes a bigger step by name (`nightdrive plugins bump ferry --minor`), committed before the release.

```sh
nightdrive plugins bump --dry-run        # what a release would raise, and the commits behind it
nightdrive plugins bump                  # patch for every plugin that changed
nightdrive plugins bump ferry --minor    # one plugin, a bigger step (--major too)
```

An external plugin is its own repo, and its author sets its version in the same way.

## A plugin of your own, in its own repo

A plugin that isn't part of Nightdrive lives in a repo of its own, with the folder's files at its top (`plugin.conf` at
the root). Name the repo after the id, optionally with a `nightdrive-plugin-` prefix: `nightdrive-plugin-disk` gets the
id `disk`.

```sh
nightdrive plugins add https://github.com/you/nightdrive-plugin-disk   # clones it into ~/.local/share/nightdrive/plugins/disk
nightdrive plugins install disk                                         # then installs it, as any plugin
nightdrive plugins remove disk                                          # turns it off and deletes the folder
```

- `add` refuses an id that Nightdrive's own plugins (or `plugins.txt`) already have: give it another,
  `nightdrive plugins add URL OTHER-ID`.
- The Launcher marks it as external. `nightdrive update` pulls it with Nightdrive, and `update check` counts its
  commits.
- `remove` stops if the folder has changes or commits of its own that aren't pushed: `--force` removes it anyway. What
  the installer put elsewhere (packages, settings) stays.
- Its code runs as the user, like Nightdrive's own: say what it does in its README, and keep it readable.

To make it part of Nightdrive instead, send a pull request with the folder under `plugins/`.

## A small example: Disk

Free space in the top bar, and a menu that lists the disks and opens ncdu. Five files in `plugins/disk/` (or at the top
of `nightdrive-plugin-disk`):

`plugin.conf`

```
# Disk (README.md): free space in the top bar, and what takes it up (ncdu)
name=Disk
icon=hard-drive
description=Free space in the top bar, and what takes it up
default=off
install=sudo dnf install -y ncdu
installed=command -v ncdu
group=plugin
version=0.1.0
author=@you
```

`module.jsonc`

```jsonc
// Disk's top bar module: the free space on /, from ./status; a click opens DiskMenu.qml, a right click ncdu
{ "interval": 60, "after": "system", "size": 16, "label": "Disk (free space)", "glyph": "hard-drive",
  "right": "~/.config/hypr/scripts/terminal --class floating-tui -- ncdu ~" }
```

`status` (executable: `chmod +x status`)

```bash
#!/bin/bash
# Disk's top bar module (module.jsonc): the free space on /, orange when less than 10 % is left
. ~/.config/topbar/scripts/emit
read -r avail used < <(df -h --output=avail,pcent / | tail -1)
if (( ${used%\%} > 90 )); then emit hard-drive "$avail" warning; else emit hard-drive "$avail"; fi
```

`DiskMenu.qml`

```qml
import QtQuick
import Quickshell
import qs

// Disk: the mounted disks and their free space (df); a click opens one in Files, and the last row shows what takes up
// the home folder (ncdu in a terminal)
Column {
    id: m
    width: parent ? parent.width : 320
    spacing: 8
    signal close()

    property var disks: []           // [{ mount, size, avail, used }], df's lines
    property string error: ""        // df's message if it failed

    Component.onCompleted: df.running = true

    Sh {
        id: df
        script: "df -h --output=target,size,avail,pcent -x tmpfs -x devtmpfs -x efivarfs | tail -n +2"
        onResult: text => {
            if (df.exitCode !== 0) { m.error = text.trim() || "df failed"; return }
            m.disks = text.trim().split("\n").filter(l => l).map(l => {
                const f = l.trim().split(/\s+/)
                return { mount: f[0], size: f[1], avail: f[2], used: parseInt(f[3]) }
            })
        }
    }

    MenuHeader { width: parent.width; title: "Disk" }

    MenuNote { variant: "danger"; text: m.error }

    MenuSection { title: "Disks"; subtitle: "free" }
    Column {
        width: parent.width
        spacing: 2
        Repeater {
            model: m.disks
            delegate: MenuRow {
                required property var modelData
                width: m.width
                icon: "hard-drive"
                label: modelData.mount
                detail: modelData.avail + " of " + modelData.size
                danger: modelData.used > 90
                onClicked: { Quickshell.execDetached(["xdg-open", modelData.mount]); m.close() }
            }
        }
    }

    Divider { padBottom: 6 }
    MenuButton {
        width: parent.width
        icon: "folder-search"
        label: "What takes up the space"
        onClicked: { Quickshell.execDetached([Quickshell.env("HOME") + "/.config/hypr/scripts/terminal", "--class", "floating-tui",
                                              "--", "ncdu", Quickshell.env("HOME")]); m.close() }
    }
}
```

`README.md`

```markdown
# Disk

How much room is left on the disk, at a glance in the top bar, and what takes it up when it runs low.

- The top bar shows the free space on the system disk, orange when less than 10 % is left.
- Its menu lists the mounted disks with their free space: a click opens one in Files.
- What takes up the space (also a right click on the icon) opens ncdu on your home folder: browse the biggest folders and delete what you don't need.

Homepage: https://dev.yorhel.nl/ncdu
Keys: ⌘⇧I
```

Add `bindings.lua` and `SHORTCUTS.md` from [Keys](#keys-bindingslua-and-shortcutsmd) for ⌘⇧I, then
`nightdrive plugins install disk` and `nightdrive plugin check disk`.
