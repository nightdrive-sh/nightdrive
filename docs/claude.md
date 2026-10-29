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
| **Actions with consequences** | sending mail, a Home Assistant device, installing software, a screen's resolution, Do Not Disturb on | only after you allow it on Nightdrive's card |

Any read, change or delete can ask on the card too: that is your choice in Access, area by area (below). On the
Normal level, reading what is private (mail, contacts, calendar, notes, notifications, a window on screen) and every
delete do.

**The card** shows exactly what will be done: the recipients and the text, the device and its new state, every package
dnf would install, every path a trash takes (a folder with how many files are in it), the app and title of the window
Claude wants to see. **Enter** allows, **Esc** refuses, and so does no answer in 60 seconds, a locked screen (the lock
covers the card and takes the keys) and stopping Claude in Claude Code (Esc there, or its own timeout for a tool):
the card closes then, so nothing is allowed that Claude no longer waits for. A card too long for the screen
allows only once you have scrolled to its end. The card is Nightdrive's, not
Claude Code's, so no Claude Code setting skips it, and a mail or a web page Claude reads can't send or switch anything
without you seeing it first. A screen or network change also asks afterwards whether to keep it, and goes back by itself
in 20 seconds unless you do.

**Undo** is on the notification for an hour; then Redo undoes the undo. Claude keeps the last 100 changes, so you can
also ask it later ("undo the wallpaper"). A change that couldn't be undone isn't offered as a change at all. An undo
that does what only the card allows (Do Not Disturb back on) asks on the card too, and one that would move the focus
waits while you type: **Try again** on the notification runs it.

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
  on Open (but *Remove what Nightdrive needs* and *Codes, card numbers and passwords*, off on every level, and Contacts'
  parts of a card, below). Space turns the picked one on or off;
  `nightdrive mcp access option home-assistant unlock on` in a terminal.
  Home Assistant has three:
  - *Unlock and open*: off, Claude only locks locks and closes covers (doors, gates, blinds). Opening is yours.
  - *Turn automations on or off*: off, Claude can run an automation but not stop one from running by itself (a leak
    alarm).
  - *Presence and location*: off, Claude doesn't get presence, occupancy or motion sensors, nor where your phones are
    (Home Assistant's app: address, distance, Wi-Fi), which tell whether anyone is home.

  Its card also shows the device's name and room from Home Assistant beside the id Claude gave, so `switch.sonoff_…`
  can't hide the oven.

  Contacts has a box for each part of a card beside the name: *Company*, *Job title*, *Email addresses* and *Phone
  numbers*, on on Normal, as they are what Claude needs to write or call someone; *Street addresses*, *Birthday*, *Web
  addresses* and *Note*, off on Normal, as they are other people's. A part that is off isn't given, nor searched or
  looked up by: Claude can't find who a number or a street belongs to. A note, when on, and the company, title and
  nickname (a shared address book's are anyone's text) come with card numbers, codes and passwords masked. Claude's
  search needs a word of two characters or more and gives at most 25 people, so the address book isn't read a letter
  at a time.

  Mail, Calendar, Notes, Ferry and Notifications have *Codes, card numbers and passwords*, off on every level: what
  Claude reads there comes with them hidden, before it leaves your computer. One-time codes and meeting passcodes
  (`[code hidden]`), login and password reset links (`[login link hidden]`), card numbers with their expiry and CVV
  (`•••• 4242`), IBANs (`FI •••• 0785`), Finnish identity codes, passwords and API keys; a Ferry text that is a code or
  a password is hidden whole. Order and phone numbers, dates, prices and other links stay as they are. Invisible
  characters are taken out first and digits of other forms (`４`, `⁴`) read as 0–9, so a code split by them or spaced
  out (`4 8 2 9 1 3`) is hidden too. A reply Claude drafts comes back with its quote hidden the same way: the card that
  sends it shows `[code hidden]` where the mail has the code, and the draft goes out whole. It goes by patterns, so a
  code written in an unusual way may get through, and now and then a number that isn't one is hidden.
  Turn it on for an area whose codes Claude should read (`nightdrive mcp access option mail secrets on`).

  What's on screen has a list instead, empty on every level: *Apps it sees without asking*. Its rows are the apps open
  now, and Space or a click ticks one. Claude's picture of a window asks each time on Normal, and the card names the
  app and the window's title; a ticked app's windows Claude sees without the card. Password managers and private
  windows never, ticked or not. In a terminal: `nightdrive mcp access option screen apps add kitty` (a window class or
  the app's name), `remove` to take it off.

  Mail has a list too, empty at first: *Mail Claude never gets*. Type an address (`maija@example.com`), a domain
  (`bank.fi`, which takes `mail.bank.fi` along) or a tag (`tag:health`) in the field under it and press Enter; Space
  takes the picked one off. Mail from or to an address or domain on it, and mail with a tag on it, isn't in Claude's
  unread, searches or threads: a thread shows only its other messages, and a draft can't answer one. Its
  notifications are left out of the latest notifications as well, as they name the sender and the subject. Your own
  `nightmail` in a terminal still shows everything. `nightdrive mcp access option mail blocked add bank.fi`.

  Notifications has *Apps whose notifications Claude doesn't see*, empty at first: its rows are the apps in the
  notification history. `nightdrive mcp access option notifications apps add Signal` (the name a notification shows).

  A list that hides can't be read (edited by hand, say): its area's Read goes to *No* until it is fixed.

  Apps and files has *Folders Claude can use*: Claude finds, opens, trashes and sends (Ferry) files, and takes a new
  wallpaper, only in these folders and those inside them. Strict has none, Normal Downloads, Documents, Pictures and
  Desktop, wherever they are (`~/Lataukset` in Finnish), Open the whole home. A path counts where it really is: a link
  can't lead into one of them or out of one, and a hard link (a file with another name too, which could be anywhere)
  isn't opened or sent, nor read as a note: copy it instead. Hidden files never, whatever the list. `~/Projects` isn't
  on Normal's on purpose: it holds code, repositories and settings with their keys, and Claude Code reaches it with
  its own tools.
  The rows are home's own folders and those at its top, Space ticks one; type a deeper one (`~/Work/Invoices`) in the
  field. A refusal names the folders and this place. Notes, Mail, Calendar, Tasks and the wallpapers keep their own,
  and Claude Code's own commands aren't limited by it. `nightdrive mcp access option apps-files folders add
  ~/Projects`. A list that can't be read gives Claude no folder.

  Software has three. What they leave out you install or remove yourself: the Launcher's Install and Remove are as
  they were.
  - *Install from any source*: off, every package of an install, dependencies too, comes from Fedora's own
    repositories, Nightdrive's COPR or, on a Mac, Fedora Asahi Remix's; a Flathub app's publisher is verified. Not RPM
    Fusion, other COPRs or repositories you added. Claude's search marks what it can't install.
  - *Remove what Nightdrive needs*: off, nothing goes that Nightdrive installs (Hyprland, Quickshell, PipeWire, Firefox,
    kitty…, the lists `install.sh` uses), nor what would take one along.
  - *Plugins from other repositories*: off, Claude installs only Nightdrive's own plugins.

  Its card says where the software comes from (Fedora, Flathub and whom it verified).

Sending, devices, installing and turning Do Not Disturb on (it hides alerts) **always ask**, whatever the level or
your choice: where all of an area's Modify or Delete is such, the choice is only *Ask* or *No*. Turning it off is a
change with Undo. What Claude reads goes to Anthropic with its answer.

**These choices cover only Nightdrive's tools.** What Claude Code may do with its own, running commands and editing
files, is set in Claude Code, and a command can do what a tool here can't without asking: `nightmail` sends mail, `nightdrive
mcp access level open` changes these choices. Keep Claude Code asking before commands: if your `~/.claude/settings.json`
or `settings.local.json` allows any command (`Bash`, `Bash(*)`, or any arguments to a shell, an interpreter or
`nightdrive`: `Bash(nightdrive *)`) or has `defaultMode` `bypassPermissions`, the Access window, its page in Settings
and `nightdrive mcp status` warn you. A project's own `.claude/settings` aren't read: look at them yourself.

A change applies at once: a session already open may still list a tool you set to *No*, but its use is refused; a new
session sees the new list. Welcome to Nightdrive asks for the level once, at the first login, with *Off* picked.
In a terminal: `nightdrive mcp access` shows what applies, `nightdrive mcp access level strict|normal|open`, `set mail
read allow` (an area, `read`, `modify` or `delete`, and `allow`, `ask` or `no`).

## What each area gives

*Ask* on Normal is in bold; † always asks.

| Area | Read | Modify | Delete |
| --- | --- | --- | --- |
| Docs and status | the docs and keys of this version, the version, plugins, displays | undo Claude's own changes | |
| Mail | **unread, search, threads, accounts** (without the senders, domains and tags you block) | a new draft, archive; send a draft † | **to Trash †** |
| Contacts | **search, a card** (company, title, emails, numbers; addresses, birthday, web addresses, note: choices) | | |
| Calendar | **calendars, events** | add an event | **an event †** |
| Tasks | lists and tasks | add, done, later | **to the trash** |
| Notes | **list, search, read (`~/Notes`)** | a new note, add to the end of one | **to the trash** |
| Deck | what plays, search, albums | play, queue, pause and skip, like, Pick for me | |
| Ferry | whether it's on, devices, the box | send files or a text to a device † | |
| Home Assistant | devices and sensors (presence and location: a choice) | switch a device, lock, close, run a scene or an automation † (unlock, open, an automation on or off: choices) | |
| Notifications | **the latest** (without the apps you list, nor Mail's of blocked mail) | send one, Do Not Disturb off; on † | |
| Appearance | wallpaper and theme now | wallpaper, theme, colour, night light, bar style | |
| Sound and display | volume, outputs, screens, network, Bluetooth, battery | volume, output, brightness; a screen's scale or resolution, Wi-Fi or networking off † | |
| What's on screen | **a picture of a window** (the apps you tick: without asking) | | |
| Apps and files | windows, newest files (in the folders it can use: a choice) | open an app or a file, bring a window forward; open a web address † | **files to the trash** |
| Software | search, details, what an install would change | install a package, Flatpak or plugin † (from other repositories, unverified Flathub apps, others' plugins: choices) | **remove a package or Flatpak †** (what Nightdrive needs: a choice) |

Claude doesn't bring a window forward while you type, nor open an app, a file or an address: after a key it waits for
two quiet seconds, five at most, and otherwise gives up, so what you type doesn't land in another window.

## What Claude never gets

- Passwords and the keyring, and the windows Send to Claude leaves out (password managers, private browser windows, the
  apps you list there): Claude sees no title of theirs and no picture.
- Hidden files and folders (`~/.ssh`, `~/.config`…): not listed, opened, trashed or sent with Ferry, on any level.
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
