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

**The card** shows exactly what will be done: the recipients and the text, the device and its new state, every package
dnf would install. **Enter** allows, **Esc** refuses, and so does no answer in 60 seconds. The card is Nightdrive's, not
Claude Code's, so no Claude Code setting skips it, and a mail or a web page Claude reads can't send or switch anything
without you seeing it first. A screen or network change also asks afterwards whether to keep it, and goes back by itself
in 20 seconds unless you do.

**Undo** is on the notification for an hour; then Redo undoes the undo. Claude keeps the last 100 changes, so you can
also ask it later ("undo the wallpaper"). A change that couldn't be undone isn't offered as a change at all.

## Settings › Claude › Access

Launcher › Settings › Claude › *Access*, much like the privacy settings of a phone:

- **On or off** at the top: whether Claude Code has Nightdrive's tools at all.
- **The level** sets every row at once:
  - *Strict*: only Nightdrive's docs and status, so Claude can explain how things work.
  - *Normal*: reads and changes you can undo, no actions with consequences. The default.
  - *Open*: the actions too, each one still asking on the card.
- **A row per area**, each *Off*, *Reads* or *Reads and changes*: Nightdrive's docs and status, Mail, Contacts, Calendar,
  Tasks, Notes, Deck, Ferry, Home Assistant, Notifications, Appearance, Sound and display, Apps and files, Software. An
  app's row shows while the app is installed.
- **Actions with consequences** on or off, apart from the level.

An area that is off isn't there for Claude at all: its tools aren't listed, so Claude doesn't know they exist. A change
here applies at once: a session already open may still list a tool you turned off, but its use is refused; a new
session sees the new list. Welcome to Nightdrive asks for the level once, at the first login.
In a terminal: `nightdrive mcp access` shows what applies, `nightdrive mcp access level strict|normal|open`, `area mail
read`, `act on|off`.

## What each area gives

| Area | Reads | Changes (Undo) | Asks on the card |
| --- | --- | --- | --- |
| Docs and status | the docs and keys of this version, the version, plugins, displays | undo Claude's own changes | |
| Mail | unread, search, threads, accounts | a new draft, archive | send a draft, delete to Trash |
| Contacts | search, a whole card (with notes and birthdays) | | |
| Calendar | calendars, events | add an event | delete an event |
| Tasks | lists and tasks | add, done, later, to the trash | |
| Notes | list, search, read (`~/Notes`) | a new note, add to the end of one, to the trash | |
| Deck | what plays, search, albums | play, queue, pause and skip, like, Pick for me | |
| Ferry | whether it's on, devices, the box | | send files or a text to a device |
| Home Assistant | devices and sensors | | switch a device, run a scene or an automation |
| Notifications | the latest | send one, Do Not Disturb | |
| Appearance | wallpaper and theme now | wallpaper, theme, colour, night light, bar style | |
| Sound and display | volume, outputs, screens, network, Bluetooth, battery | volume, output, brightness | a screen's scale or resolution, Wi-Fi or networking off |
| Apps and files | windows, a picture of one on screen, newest files | open an app or a file, bring a window forward, to the trash | open a web address |
| Software | search, details, what an install would change | | install or remove a package or Flatpak, install a plugin |

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

- One area: its row *Off*.
- Everything but the docs: the level *Strict*.
- All of it: the switch at the top of Access, or `nightdrive mcp remove`. `nightdrive mcp install` gives the tools back,
  and `nightdrive mcp status` tells whether they're on.

`install` registers the server in Claude Code for every session and allows its tools there, so Claude Code doesn't ask
about each one on top of the card; `remove` takes away just what it added.
