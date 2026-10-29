#!/usr/bin/env python3
"""The rows of Settings › Claude › Access, in their order, and what each lets Claude do in plain words (plan: Dashboard
#1761, the model #1831). A tool's `area` in mcp.json is one of these, or its plugin's own id (shown by that id).

Each area has up to three rights, each Allow, Ask or No (levels.py has the presets):
    read     what Claude can see of it, which goes to Anthropic with the answer
    modify   what Claude can change or do in it (a `change` tool, with Undo, or an `act` tool: sending, devices,
             installing, which never runs without the card, so at most Ask)
    delete   what Claude can remove (a tool with "deletes": true)
The words below finish "Claude …" in the Access window; a right an area has no tools for isn't shown at all.

An area may have choices of its own beside its rights (#1830), each on or off: `options`, with what on and off mean
in a sentence each. A level sets them (levels.OPTIONS), the user may set one apart, and the tool keeps to them: its
mcp.json `options` takes values out of its arguments, and its command gets them (run.environment) and refuses.
A choice with `"list": True` is a list the user keeps instead (window classes: the apps whose windows Claude sees
without asking, #1832), empty at every level unless levels.OPTIONS fills it (the folders Claude can use, #1849), with
what being on it means (`on`) and not (`off`). Its command gets it
the same way, and its `card` command may let a call on it past the card (confirm.facts). One with `"hides": True` takes
away instead (Mail's blocked senders, the apps whose notifications Claude doesn't see: #1789), so one that can't be read
closes the area's Read rather than opening it (access.load). `item` is the pattern of one entry and `item_words` what it
is in words, `offer` where the Access window finds entries to tick: the open apps (`windows`), the apps in the
notification history (`notifications`), home's own folders and those at its top (`folders`, which also takes a typed
one), or none: typed (`typed`).
"""

RIGHTS = ("read", "modify", "delete")

# What a stranger may write, or the user keep, in mail, notifications, Ferry's box, notes and invitations: hidden from
# Claude (mask.py) unless the user turns this on for the area. Contacts' note is masked always (#1789)
SECRETS = {"id": "secrets", "name": "Codes, card numbers and passwords",
           "on": "Claude reads them as they are: one-time codes, login and password reset links, card numbers, IBANs, "
                 "identity codes, passwords and keys go to Anthropic too.",
           "off": "Claude reads them hidden (•••• 4242, [code hidden], [login link hidden]): the rest of the text, "
                  "order and phone numbers, dates and links, as it is."}

# Mail's blocked list: an address, a domain or tag:NAME, with nothing that could leave a notmuch query's string
# (plugins/mail/lib/blocked.py checks the same)
MAIL_ENTRY = r'(?:tag:[^\s"()\\]{1,100}|(?:[^\s"()\\@<>]{0,64}@)?[^\s"()\\@<>.]{1,63}(?:\.[^\s"()\\@<>.]{1,63})+)'

# A folder Claude can use: ~ (the whole home), ~/A/B (no part hidden: no ., .., .ssh), or one of home's own folders by
# its xdg-user-dir name in English, which is found wherever it is (Downloads is ~/Lataukset in Finnish)
STANDARD_FOLDERS = ("Desktop", "Documents", "Downloads", "Music", "Pictures", "Videos")
FOLDER_ENTRY = r'(?:~(?:/[^/.\x00-\x1f\x7f][^/\x00-\x1f\x7f]{0,254})*|' + "|".join(STANDARD_FOLDERS) + ")"

AREAS = {
    "nightdrive": {"name": "Nightdrive's docs and status", "glyph": "book-open",
                   "read": "reads the docs and keys of this version, the version, plugins and displays",
                   "modify": "undoes its own changes"},
    "mail": {"name": "Mail", "glyph": "mail", "app": True,
             "read": "searches and reads your mail: unread, whole threads, your accounts",
             "modify": "writes new drafts and archives; sends a draft",
             "delete": "moves mail to Trash",
             "options": [
                 SECRETS,
                 # Logs 3300, 3301: the bank, health, the people close to you can be left out whole; empty at first
                 {"id": "blocked", "name": "Mail Claude never gets", "list": True, "hides": True, "offer": "typed",
                  "item": MAIL_ENTRY, "item_words": "an address, a domain or tag:NAME",
                  "words": "Mail from or to these addresses and domains (bank.fi: also mail.bank.fi), and mail with "
                           "these tags (tag:health), isn't in Claude's searches, unread or threads, nor its "
                           "notifications.",
                  "on": "Claude never gets this mail.",
                  "off": "Claude may read it."},
             ]},
    "contacts": {"name": "Contacts", "glyph": "contact", "app": True,
                 "read": "finds people by name and reads the parts of their cards you tick in its choices",
                 # The parts of a card beside the name (#1789): what is off isn't searched or given, so a street or a
                 # number Claude has can't find who it belongs to either
                 "options": [
                     {"id": "company", "name": "Company",
                      "on": "Claude gets the company a person works for.",
                      "off": "Claude doesn't get anyone's company."},
                     {"id": "title", "name": "Job title",
                      "on": "Claude gets a person's job title.",
                      "off": "Claude doesn't get job titles."},
                     {"id": "emails", "name": "Email addresses",
                      "on": "Claude gets email addresses, to write to someone.",
                      "off": "Claude doesn't get email addresses, nor find a person by one."},
                     {"id": "phones", "name": "Phone numbers",
                      "on": "Claude gets phone numbers, to call or message someone.",
                      "off": "Claude doesn't get phone numbers, nor find a person by one."},
                     {"id": "addresses", "name": "Street addresses",
                      "on": "Claude gets where people live and work, and finds them by a street.",
                      "off": "Claude doesn't get street addresses, nor find a person by one."},
                     {"id": "birthday", "name": "Birthday",
                      "on": "Claude gets people's birthdays.",
                      "off": "Claude doesn't get birthdays."},
                     {"id": "urls", "name": "Web addresses",
                      "on": "Claude gets the web addresses on a card.",
                      "off": "Claude doesn't get web addresses."},
                     {"id": "note", "name": "Note",
                      "on": "Claude reads a card's note, with card numbers, codes and passwords in it masked.",
                      "off": "Claude doesn't read notes: door codes and the like stay with you."},
                 ]},
    "calendar": {"name": "Calendar", "glyph": "calendar", "app": True,
                 "read": "reads your calendars and their events, invitations included",
                 "modify": "adds events (without guests, so no invitation goes out)",
                 "delete": "deletes events",
                 "options": [SECRETS]},
    "tasks": {"name": "Tasks", "glyph": "list-checks", "app": True,
              "read": "reads your lists and tasks",
              "modify": "adds tasks, marks them done, moves them later",
              "delete": "moves tasks to the trash"},
    "notes": {"name": "Notes", "glyph": "notebook-pen", "app": True,
              "read": "lists, searches and reads your notes in ~/Notes",
              "modify": "writes new notes and adds to the end of one",
              "delete": "moves notes to the trash",
              "options": [SECRETS]},
    "deck": {"name": "Deck", "glyph": "disc-3", "app": True,
             "read": "sees what plays, searches music and albums (the search words go to Spotify)",
             "modify": "plays, queues, pauses and skips, likes songs"},
    "ferry": {"name": "Ferry", "glyph": "smartphone", "app": True,
              "read": "sees whether Ferry is on, your devices and the box",
              "modify": "sends files or a text to your devices",
              "options": [SECRETS]},
    "home-assistant": {"name": "Home Assistant", "glyph": "house", "app": True,
                       "read": "reads your devices and sensors",
                       "modify": "switches devices, runs scenes and automations",
                       "options": [
                           {"id": "unlock", "name": "Unlock and open",
                            "on": "Claude may also unlock a lock and open a cover (a door, a gate, blinds), on "
                                  "the card.",
                            "off": "Claude only locks and closes: unlocking and opening are yours to do."},
                           {"id": "automations", "name": "Turn automations on or off",
                            "on": "Claude may also turn an automation on or off: one turned off stops running by "
                                  "itself.",
                            "off": "Claude runs an automation but can't turn one on or off, so one that guards (a "
                                   "leak alarm) keeps working."},
                           {"id": "presence", "name": "Presence and location",
                            "on": "Claude reads presence, occupancy and motion sensors too, and where your phones "
                                  "are (Home Assistant's app: address, distance, Wi-Fi): whether anyone is home goes "
                                  "to Anthropic.",
                            "off": "Claude doesn't get presence, occupancy or motion sensors, nor where your phones "
                                   "are: they tell whether anyone is home."},
                       ]},
    "notifications": {"name": "Notifications", "glyph": "bell-ring",
                      "read": "reads the latest notifications of every app",
                      "modify": "sends you a notification, turns Do Not Disturb on or off",
                      "options": [
                          SECRETS,
                          {"id": "apps", "name": "Apps whose notifications Claude doesn't see", "list": True,
                           "hides": True, "offer": "notifications", "item_words": "an app's name",
                           "words": "Their notifications aren't among the latest Claude reads. Mail's of the mail "
                                    "Access › Mail blocks aren't either.",
                           "on": "Claude doesn't see its notifications.",
                           "off": "Claude sees its notifications."},
                      ]},
    "appearance": {"name": "Appearance", "glyph": "palette",
                   "read": "sees your wallpaper and theme",
                   "modify": "changes the wallpaper, theme, colour, night light and bar style"},
    "sound-display": {"name": "Sound and display", "glyph": "volume-2",
                      "read": "reads the volume, outputs, screens, network, Bluetooth and battery",
                      "modify": "sets the volume, output and brightness; a screen's scale or resolution, the network off"},
    "screen": {"name": "What's on screen", "glyph": "scan-eye",
               "read": "takes a picture of a window on screen and looks at it",
               "options": [
                   {"id": "apps", "name": "Apps it sees without asking", "list": True, "offer": "windows",
                    "item_words": "a window class",
                    "words": "When reading asks, Claude takes a picture of these apps' windows without the card. "
                             "Password managers and private windows never, listed or not.",
                    "on": "Claude sees its windows without asking.",
                    "off": "Claude asks first."},
               ]},
    "apps-files": {"name": "Apps and files", "glyph": "folder",
                   "read": "lists your open windows and the newest files in your folders",
                   "modify": "opens apps, files and web addresses, brings a window forward",
                   "delete": "moves files to the trash",
                   "options": [
                       # #1849: the one limit every tool with a path keeps (config/hypr/scripts/files › checked)
                       {"id": "folders", "name": "Folders Claude can use", "list": True, "offer": "folders",
                        "item": FOLDER_ENTRY, "item_words": "a folder in home (~/Projects)",
                        "words": "Claude opens, finds, trashes and sends files (Ferry, a new wallpaper) only in "
                                 "these folders and those inside them, wherever a link points; hidden files never. "
                                 "~/Projects isn't on Normal's: code and its keys. Notes and Mail keep their own.",
                        "on": "Claude may use the files in it.",
                        "off": "Claude can't use its files."},
                   ]},
    "software": {"name": "Software", "glyph": "package",
                 "read": "searches software, its details and what an install would change",
                 "modify": "installs packages, Flatpaks and Nightdrive's plugins",
                 "delete": "removes packages and Flatpaks",
                 "options": [
                     {"id": "any_source", "name": "Install from any source",
                      "on": "Claude may also install from repositories you added (RPM Fusion, COPRs, others) and "
                            "Flathub apps whose publisher Flathub hasn't verified, on the card.",
                      "off": "Claude installs only from Fedora's own repositories (and Nightdrive's) and Flathub's "
                             "verified apps: the rest is yours to install from the Launcher."},
                     {"id": "nightdrive_packages", "name": "Remove what Nightdrive needs",
                      "on": "Claude may also remove a package Nightdrive installs (Hyprland, Quickshell, PipeWire, "
                            "Firefox…), on the card: the desktop could stop working.",
                      "off": "Claude can't remove a package Nightdrive installs, nor anything whose removal would "
                             "take one along."},
                     {"id": "any_plugin", "name": "Plugins from other repositories",
                      "on": "Claude may also install a plugin from someone else's repository, on the card: its "
                            "installer runs their code.",
                      "off": "Claude installs only Nightdrive's own plugins: another repository's are yours to "
                             "install."},
                 ]},
}


def name(area):
    """The row's name; a plugin's own area by its id in words (disk-usage → Disk usage)."""
    known = AREAS.get(area)
    return known["name"] if known else area.replace("-", " ").capitalize()


def glyph(area):
    return AREAS.get(area, {}).get("glyph", "puzzle")


def words(area, right):
    return AREAS.get(area, {}).get(right, "")


def options(area):
    """The area's own choices: [{id, name, on, off}], and list: True for a list."""
    return AREAS.get(area, {}).get("options", [])
