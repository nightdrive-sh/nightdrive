#!/usr/bin/env python3
"""iCloud's contact photos, fetched into the cache after a sync (`contacts sync` runs it), for cards.py to show.

    photos.py fetch [NAME…]    fetch the photos the accounts' cards (or these accounts') point to and the cache lacks,
                               and remove the fetched ones no card points to any more

iCloud keeps a photo apart from its card: PHOTO;VALUE=uri:https://gateway.icloud.com/… behind the account's sign-in, so
the window can't load it itself. Here it is fetched with the account's own password-cmd, as vdirsyncer does, and
written as PHOTO_DIR/icloud-<sha1>.jpg, named by the address and the crop: a new photo on the phone is a new address,
so a photo once fetched never needs fetching again. Only reads the cards: it never writes to an address book.

An iPhone's photo is often the whole picture with the part to show in X-ABCROP-RECTANGLE=ABClipRect_1&x&y&w&h&hash,
counted from the bottom left as Apple does: that square is cut out here (ImageMagick), and made small for the cache.
"""

import base64
import configparser
import hashlib
import os
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import vobject

HOME = Path.home()
DATA_DIR = Path(os.environ.get("XDG_DATA_HOME", HOME / ".local/share")) / "contacts"
ACCOUNTS = Path(os.environ.get("XDG_CONFIG_HOME", HOME / ".config")) / "contacts/accounts.conf"
PHOTO_DIR = Path(os.environ.get("XDG_CACHE_HOME", HOME / ".cache")) / "contacts/photos"
PREFIX = "icloud-"              # the fetched ones, apart from the photos cards.py writes from inside a card
SIZE = 512                      # the cached photo's longest side, in pixels: the card shows it at most ~200
TIMEOUT = 20                    # seconds for one photo
WORKERS = 6                     # photos fetched at once
PASSWORD_TIMEOUT = 30           # seconds for password-cmd (a keyring may be slow to answer)


def signed_in(url):
    """Whether the photo at url needs the account's sign-in: iCloud's (cards.py shows the others' straight from the web)"""
    host = urllib.parse.urlsplit(url).hostname or ""
    return host == "icloud.com" or host.endswith(".icloud.com")


def crop_of(item):
    """(x, y, w, h) of ABClipRect_1&x&y&w&h&hash, or None"""
    raw = item.params.get("X-ABCROP-RECTANGLE", [""])[0]
    parts = raw.split("&")
    if len(parts) < 5 or parts[0] != "ABClipRect_1":
        return None
    try:
        x, y, w, h = (int(float(p)) for p in parts[1:5])
    except ValueError:
        return None
    return (x, y, w, h) if w > 0 and h > 0 else None


def cached(item):
    """The cache's file for a card's PHOTO item: whether it is there yet or not"""
    crop = crop_of(item)
    key = item.value + ("#" + ",".join(map(str, crop)) if crop else "")
    return PHOTO_DIR / (PREFIX + hashlib.sha1(key.encode()).hexdigest() + ".jpg")


def wanted(account):
    """{file: (url, crop)} for the account's cards' photos that need its sign-in"""
    out = {}
    for path in sorted((DATA_DIR / account).rglob("*.vcf")):
        try:
            card = vobject.readOne(path.read_text(errors="replace"))
        except Exception:       # cards.py leaves a card it can't read out too
            continue
        for item in card.contents.get("photo", [])[:1]:
            if isinstance(item.value, str) and item.value.startswith("https://") and signed_in(item.value):
                out[cached(item)] = (item.value, crop_of(item))
    return out


def password(values):
    """The account's password from its password-cmd (only asked when there is something to fetch)"""
    done = subprocess.run(["sh", "-c", values["password-cmd"]], capture_output=True, text=True, timeout=PASSWORD_TIMEOUT)
    if done.returncode != 0:
        raise RuntimeError("password-cmd failed")
    return done.stdout.rstrip("\n")


def shrink(data, crop, out):
    """The picture's crop (Apple's, from the bottom left) at most SIZE pixels a side, as JPEG into out"""
    args = ["magick", "-", "-auto-orient"]
    if crop:
        x, y, w, h = crop
        # SouthWest: ImageMagick counts y from the bottom too
        args += ["-gravity", "SouthWest", "-crop", f"{w}x{h}+{x}+{y}", "+repage", "+gravity"]
    args += ["-resize", f"{SIZE}x{SIZE}>", "-strip", "-quality", "85", "jpg:" + str(out)]
    subprocess.run(args, input=data, check=True, capture_output=True, timeout=TIMEOUT)


def fetch_one(url, crop, auth, out):
    request = urllib.request.Request(url, headers={"Authorization": auth})
    with urllib.request.urlopen(request, timeout=TIMEOUT) as reply:
        data = reply.read()
    tmp = out.with_suffix(".tmp")
    try:
        shrink(data, crop, tmp)
    except (subprocess.SubprocessError, OSError):
        tmp.write_bytes(data)       # without ImageMagick (or on a picture it can't read) the whole one; Avatar crops it
    tmp.replace(out)


def fetch(names):
    parser = configparser.ConfigParser(interpolation=None)
    parser.read(ACCOUNTS)
    sections = {s.partition(" ")[2]: parser[s] for s in parser.sections() if s.startswith("account ")}
    keep, failed = set(), 0
    for name, values in sections.items():
        photos = wanted(name)
        keep |= set(photos)
        if names and name not in names:
            continue
        missing = {f: v for f, v in photos.items() if not f.exists()}
        if not missing:
            continue
        try:
            auth = "Basic " + base64.b64encode(f"{values['address']}:{password(values)}".encode()).decode()
        except (RuntimeError, subprocess.SubprocessError, KeyError) as e:
            print(f"photos: {name}: {e}", file=sys.stderr)
            failed += len(missing)
            continue
        PHOTO_DIR.mkdir(parents=True, exist_ok=True)

        def one(item):
            out, (url, crop) = item
            try:
                fetch_one(url, crop, auth, out)
                return 0
            except (urllib.error.URLError, OSError) as e:
                print(f"photos: {name}: {url}: {e}", file=sys.stderr)
                return 1
        # A few at a time: the first sync of an account fetches them all, and the sync's lock waits for it
        with ThreadPoolExecutor(WORKERS) as pool:
            failed += sum(pool.map(one, missing.items()))
    # A photo no card points to any more (a new one on the phone, a contact deleted) goes; the cards' own stay
    if PHOTO_DIR.is_dir():
        for f in PHOTO_DIR.glob(PREFIX + "*"):
            if f not in keep:
                f.unlink(missing_ok=True)
    return failed


if __name__ == "__main__":
    if sys.argv[1:2] != ["fetch"]:
        sys.exit(__doc__)
    sys.exit(1 if fetch(sys.argv[2:]) else 0)
