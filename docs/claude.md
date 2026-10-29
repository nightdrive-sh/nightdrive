# Claude and your desktop

With Nightdrive's tools on, Claude Code can use your desktop: find a mail and draft the reply, add a task or an event,
play an album, set the wallpaper, tell you which key does what. You ask in plain words in any Claude Code session (⌘⌥Enter
in the Launcher, `nightdrive ask`, a terminal), and you decide in Settings how far it may go.

The tools come from `nightdrive mcp`, an MCP server on your own computer. Each tool runs a command an app already has
(`nightmail`, `contacts`, `deck`, `tasks`…), so nothing is there only for Claude, and everything works without Claude too.
Claude writes (⌘⇧C) and Mail's replies don't get the tools: what they read can't make them do anything.

## Three kinds of tools

| Kind | Examples | What happens |
| --- | --- | --- |
| **Reads** | search mail, today's events, what plays, the newest downloads, the docs | at once |
| **Changes** | the wallpaper, the volume, a new task, a note, a draft, a file to the trash | at once, with a notification that has **Undo** |
| **Actions with consequences** | sending mail, a Home Assistant device, installing software, a screen's resolution | only after you allow it on Nightdrive's card |

Any read, change or delete can ask on the card too: that is your choice in Access, area by area (below). On the
Normal level, reading what is private (mail, contacts, calendar, notes, notifications, a window on screen) and every
delete do.

**The card** shows exactly what will be done: the recipients and the text, the device and its new state, every package
dnf would install. **Enter** allows, **Esc** refuses, and so does no answer in 60 seconds. A card too long for the screen
allows only once you have scrolled to its end. The card is Nightdrive's, not
Claude Code's, so no Claude Code setting skips it, and a mail or a web page Claude reads can't send or switch anything
without you seeing it first. A screen or network change also asks afterwards whether to keep it, and goes back by itself
in 20 seconds unless you do.

**Undo** is on the notification for an hour; then Redo undoes the undo. Claude keeps the last 100 changes, so you can
also ask it later ("undo the wallpaper"). A change that couldn't be undone isn't offered as a change at all.

## Settings › Claude › Access

Launcher › Settings › Claude › *Access*, much like the privacy settings of a phone:

- **On or off** at the top: whether Claude Code has Nightdrive's tools at all.
- **The level** sets every area at once:
  - *Strict*: only Nightdrive's docs and status, so Claude can explain how things work.
  - *Normal*, the default: reading your mail, contacts, calendar, notes, notifications or a window on screen asks you
    each time; the rest is allowed. Changes run at once with Undo; deleting asks.
  - *Open*: everything allowed.
- **Areas…** opens the Access window (`nightdrive mcp access open`). Each area has up to three choices, **Read**,
  **Modify** and **Delete**, each *Allow*, *Ask* or *No*:
  - *Allow*: Claude does it when it needs to (a change comes with Undo).
  - *Ask*: Nightdrive's card asks you each time, showing what Claude wants to read, change or delete. A read's card
    can't show what will be found, only what Claude looks for.
  - *No*: Claude doesn't see those tools at all.

  The picked row says in plain words what its choices let Claude do, and › lists every tool in the area. A dot marks a
  choice of your own; picking a level again puts them back to the level's (it asks first). An app's area shows while
  the app is installed.
- **An area's own choices**, in its details (›), are on or off, and the level sets them too: off on Strict and Normal, on
  on Open (but *Remove what Nightdrive needs*, off on every level). Space turns the picked one on or off;
  `nightdrive mcp access option home-assistant unlock on` in a terminal.
  Home Assistant has three:
  - *Unlock and open*: off, Claude only locks locks and closes covers (doors, gates, blinds). Opening is yours.
  - *Turn automations on or off*: off, Claude can run an automation but not stop one from running by itself (a leak
    alarm).
  - *Presence and location*: off, Claude doesn't get presence, occupancy or motion sensors, nor where your phones are
    (Home Assistant's app: address, distance, Wi-Fi), which tell whether anyone is home.

  Its card also shows the device's name and room from Home Assistant beside the id Claude gave, so `switch.sonoff_…`
  can't hide the oven.

  Software has three. What they leave out you install or remove yourself: the Launcher's Install and Remove are as
  they were.
  - *Install from any source*: off, every package of an install, dependencies too, comes from Fedora's own
    repositories, Nightdrive's COPR or, on a Mac, Fedora Asahi Remix's; a Flathub app's publisher is verified. Not RPM
    Fusion, other COPRs or repositories you added. Claude's search marks what it can't install.
  - *Remove what Nightdrive needs*: off, nothing goes that Nightdrive installs (Hyprland, Quickshell, PipeWire, Firefox,
    kitty…, the lists `install.sh` uses), nor what would take one along.
  - *Plugins from other repositories*: off, Claude installs only Nightdrive's own plugins.

  Its card says where the software comes from (Fedora, Flathub and whom it verified).

Sending, devices and installing **always ask**, whatever the level or your choice: where all of an area's Modify or
Delete is such, the choice is only *Ask* or *No*. What Claude reads goes to Anthropic with its answer.

**These choices cover only Nightdrive's tools.** What Claude Code may do with its own, running commands and editing
files, is set in Claude Code, and a command can do what a tool here can't without asking: `nightmail` sends mail, `nightdrive
mcp access level open` changes these choices. Keep Claude Code asking before commands: if your `~/.claude/settings.json`
allows `Bash` as a whole or has `defaultMode` `bypassPermissions`, the Access window, its page in Settings and
`nightdrive mcp status` warn you.

A change applies at once: a session already open may still list a tool you set to *No*, but its use is refused; a new
session sees the new list. Welcome to Nightdrive asks for the level once, at the first login, with *Off* picked.
In a terminal: `nightdrive mcp access` shows what applies, `nightdrive mcp access level strict|normal|open`, `set mail
read allow` (an area, `read`, `modify` or `delete`, and `allow`, `ask` or `no`).

## What each area gives

*Ask* on Normal is in bold; † always asks.

| Area | Read | Modify | Delete |
| --- | --- | --- | --- |
| Docs and status | the docs and keys of this version, the version, plugins, displays | undo Claude's own changes | |
| Mail | **unread, search, threads, accounts** | a new draft, archive; send a draft † | **to Trash †** |
| Contacts | **search, a card** | | |
| Calendar | **calendars, events** | add an event | **an event †** |
| Tasks | lists and tasks | add, done, later | **to the trash** |
| Notes | **list, search, read (`~/Notes`)** | a new note, add to the end of one | **to the trash** |
| Deck | what plays, search, albums | play, queue, pause and skip, like, Pick for me | |
| Ferry | whether it's on, devices, the box | send files or a text to a device † | |
| Home Assistant | devices and sensors (presence and location: a choice) | switch a device, lock, close, run a scene or an automation † (unlock, open, an automation on or off: choices) | |
| Notifications | **the latest** | send one, Do Not Disturb | |
| Appearance | wallpaper and theme now | wallpaper, theme, colour, night light, bar style | |
| Sound and display | volume, outputs, screens, network, Bluetooth, battery | volume, output, brightness; a screen's scale or resolution, Wi-Fi or networking off † | |
| What's on screen | **a picture of a window** | | |
| Apps and files | windows, newest files | open an app or a file, bring a window forward; open a web address † | **files to the trash** |
| Software | search, details, what an install would change | install a package, Flatpak or plugin † (from other repositories, unverified Flathub apps, others' plugins: choices) | **remove a package or Flatpak †** (what Nightdrive needs: a choice) |

## What Claude never gets

- Passwords and the keyring, and the windows Send to Claude leaves out (password managers, private browser windows, the
  apps you list there): Claude sees no title of theirs and no picture.
- Hidden files and folders (`~/.ssh`, `~/.config`…): not listed, opened, trashed or sent with Ferry.
- Anything that can't be taken back without asking: no permanent delete (mail goes to Trash, files and notes to the
  trash), no recurring events deleted, no attachments Claude adds to a mail (your own draft's go, and the card names them).
- Shutting down, users, the clipboard history.

The server has no network port: it runs only when Claude Code on this computer starts it, and what a tool returns goes
to Anthropic as part of that session, like anything else Claude reads.

## Turning it off

- One area, or one of its Read, Modify and Delete: *No* in the Access window.
- Everything but the docs: the level *Strict*.
- All of it: the switch at the top of Access, or `nightdrive mcp remove`. `nightdrive mcp install` gives the tools back,
  and `nightdrive mcp status` tells whether they're on.

`install` registers the server in Claude Code for every session and allows its tools there, so Claude Code doesn't ask
about each one on top of the card; `remove` takes away just what it added.
