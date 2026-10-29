#!/usr/bin/env python3
"""The levels of Settings › Claude › Access: what each area's Read, Modify and Delete are until the user sets one
apart (plan: Dashboard #1761, the model #1831; Normal is the security review's defaults, note 93 and logs 3295-3306).

    strict   only Nightdrive's docs and status: Claude explains how things work
    normal   the default. Reading what is private (mail, people, calendar, notes, notifications, the picture of a
             window) asks each time; the rest is allowed. Changes run at once with Undo, deleting asks everywhere
    open     everything allowed
Whatever the level, a tool with consequences (sending, devices, installing: class act) is at most Ask: Allow for its
right still shows the card, since that card is all that stands between a mail Claude read and one it sends.
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


def preset(level, area, right):
    """The value a level gives one right of one area."""
    rules = LEVELS[level]
    return rules["areas"].get(area, {}).get(right) or rules["default"][right]


assert all(set(LEVELS[l]["default"]) == set(RIGHTS) for l in LEVELS)
