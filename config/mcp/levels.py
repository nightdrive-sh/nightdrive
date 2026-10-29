#!/usr/bin/env python3
"""The levels of Settings › Claude › Access: what each area's Read, Modify and Delete are until the user sets one
apart (plan: Dashboard #1761, the model #1831; Normal is the security review's defaults, note 93 and logs 3295-3306).

    strict   only Nightdrive's docs and status: Claude explains how things work
    normal   the default. Reading what is private (mail, people, calendar, notes, notifications, the picture of a
             window) asks each time; the rest is allowed. Changes run at once with Undo, deleting asks everywhere
    open     everything allowed
Whatever the level, a tool with consequences (sending, devices, installing: class act) is at most Ask: Allow for its
right still shows the card, since that card is all that stands between a mail Claude read and one it sends.

An area's own choices (areas.py's options: Home Assistant's locks, #1830; Software's sources, #1835; the masking of
secrets, #1789) are on or off by level too: OPTIONS. A list choice is empty at every level unless OPTIONS gives it
its entries (the folders Claude can use, #1849).
"""

from areas import RIGHTS

VALUES = ("allow", "ask", "no")

# Read Ask on Normal: what a stranger may have written (mail, invitations, notifications: prompt injection) or what is
# other people's or private (contacts, notes), and the picture of a window, which could show anything
PRIVATE = ("mail", "contacts", "calendar", "notes", "notifications", "screen")

LEVELS = {
    "strict": {"default": {"read": "no", "modify": "no", "delete": "no"},
               "areas": {"nightdrive": {"read": "allow"}}},
    "normal": {"default": {"read": "allow", "modify": "allow", "delete": "ask"},
               "areas": {a: {"read": "ask"} for a in PRIVATE}},
    "open": {"default": {"read": "allow", "modify": "allow", "delete": "allow"},
             "areas": {}},
}

# An area's own choices, on (allowed) or off per level. Normal is the security review's (log 3295): Claude locks and
# closes but doesn't unlock or open, as a card allowed while tired mustn't open the front door; runs an automation but
# doesn't turn one off, a silent danger (the leak alarm stops); leaves out the sensors that tell whether anyone is home
OPTIONS = {
    "home-assistant": {
        "unlock": {"strict": False, "normal": False, "open": True},
        "automations": {"strict": False, "normal": False, "open": True},
        "presence": {"strict": False, "normal": False, "open": True},
    },
    # Contacts (log 3303): what finds the person and reaches them, as writing or calling is what Claude needs them
    # for; where they live, their birthday and the note are other people's and stay out
    "contacts": {
        "company": {"strict": False, "normal": True, "open": True},
        "title": {"strict": False, "normal": True, "open": True},
        "emails": {"strict": False, "normal": True, "open": True},
        "phones": {"strict": False, "normal": True, "open": True},
        "addresses": {"strict": False, "normal": False, "open": True},
        "birthday": {"strict": False, "normal": False, "open": True},
        "urls": {"strict": False, "normal": False, "open": True},
        "note": {"strict": False, "normal": False, "open": True},
    },
    # Masking (logs 3300, 3301, 3304, 3306): codes, login links and card numbers are what an injection wants most and
    # what Claude doesn't need, so they stay hidden on Open too; the user may show them area by area
    **{area: {"secrets": {"strict": False, "normal": False, "open": False}}
       for area in ("mail", "calendar", "notes", "ferry", "notifications")},
    # Software (log 3302): Fedora's own repositories and Flathub's verified apps only, as a name one letter off or an
    # unknown publisher is how a bad package gets in; never removing what the desktop runs on, not even on Open (the
    # user may turn it on); Nightdrive's own plugins only, as another's installer runs its code
    "software": {
        "any_source": {"strict": False, "normal": False, "open": True},
        "nightdrive_packages": {"strict": False, "normal": False, "open": False},
        "any_plugin": {"strict": False, "normal": False, "open": True},
    },
    # The folders Claude can use (#1849), a list: on Normal where what you download, write and keep as pictures is,
    # not the rest of home (projects, mail exports, backups); on Open the whole home, hidden files never
    "apps-files": {
        "folders": {"strict": [], "normal": ["Downloads", "Documents", "Pictures", "Desktop"], "open": ["~"]},
    },
}


def preset(level, area, right):
    """The value a level gives one right of one area."""
    rules = LEVELS[level]
    return rules["areas"].get(area, {}).get(right) or rules["default"][right]


def option_preset(level, area, option):
    """Whether a level turns one of an area's own choices on; one it doesn't know is off. A list's: what is on it
    (a copy, so a change to the user's own doesn't change the level's)."""
    value = OPTIONS.get(area, {}).get(option, {}).get(level, False)
    return list(value) if isinstance(value, list) else value


assert all(set(LEVELS[l]["default"]) == set(RIGHTS) for l in LEVELS)
assert all(set(v) == set(LEVELS) for o in OPTIONS.values() for v in o.values())
