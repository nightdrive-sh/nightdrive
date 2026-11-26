"""A fresh start's choice between two different contents of one file (sync.py, manifest.start).

After a new Hub (the old one lost: the first device to sync fills it, "seeds") or a Hub put back from a backup, this
computer has no agreement with the Hub to go by. A file both have with different content could be an edit made here,
one made elsewhere, or the Hub's copy could simply be old. The entry this computer had with the Hub before (`before`:
the content agreed last and a few earlier ones) tells them apart:

- The Hub's content is the one agreed last, or an earlier one: the Hub's is old, and this computer's is the newer.
- This computer's file is still the one agreed last, and the Hub's is none it has seen: the change was made elsewhere.
- Anything else (both changed, or no entry before): unknown, so both are kept, by the app's rule.

So devices that seed a new Hub one after another don't make copies of each other's files, a backup older than this
computer doesn't roll its edits back, and a device that was behind takes the newer content rather than pushing its own.
"""

OURS, HUBS, BOTH = "ours", "hubs", "both"


def choose(before, here, hub):
    """OURS, HUBS or BOTH for a file whose content here (`here`, a hash) differs from the Hub's (`hub`). `before` is
    the manifest entry the file had before the fresh start, or None."""
    agreed = (before or {}).get("h")
    if not agreed:
        return BOTH
    if hub == agreed or hub in (before.get("p") or []):
        return OURS
    if here == agreed:
        return HUBS
    return BOTH
