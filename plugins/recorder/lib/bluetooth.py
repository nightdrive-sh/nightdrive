#!/usr/bin/env python3
"""Bluetooth headsets as microphones (#2250). Headphones such as AirPods play in A2DP, which has no microphone, so
PipeWire offers no source for them and they would be missing from the window's list. Their card's headset profile
(HSP/HFP) has one: the list shows each headset by its card, recording from it switches the card to that profile, and
saving switches it back, since music sounds poorer in headset mode.

    bluetooth.py list [--json]        the connected headsets: [{card, name, profile (now), headset (the one used)}]

    headsets() -> list      use(card) -> (source, previous profile or None)      restore(card, profile)

A headset is picked as its card's name (bluez_card.XX_XX…), which Settings' mic keeps: it works the next time too,
whatever profile the card is in by then. pactl (PipeWire's pulse side, pipewire-pulseaudio) does the switching.
"""

import json
import os
import subprocess
import sys
import time

PACTL = os.environ.get("RECORDER_PACTL", "pactl")   # a test gives a fake one
PREFIX = "bluez_card."
# Best first: LC3 (headset-head-unit on a new enough device), then mSBC (wideband), then CVSD (narrowband)
PREFERRED = ("headset-head-unit", "headset-head-unit-msbc", "headset-head-unit-cvsd")
# Seconds the headset's source has to appear after the switch (a test gives less)
SOURCE_WAIT = float(os.environ.get("RECORDER_SOURCE_WAIT", 4.0))


class BluetoothError(Exception):
    pass


def is_card(mic):
    return str(mic or "").startswith(PREFIX)


def pactl_json(*args):
    try:
        done = subprocess.run([PACTL, "-f", "json", *args], capture_output=True, text=True, timeout=10)
    except (OSError, subprocess.TimeoutExpired):
        return []
    try:
        data = json.loads(done.stdout) if done.returncode == 0 else []
    except ValueError:
        return []
    return data if isinstance(data, list) else []


def best_profile(card):
    """The card's headset profile to record with: one that has a source and can be used now."""
    usable = {name: p for name, p in (card.get("profiles") or {}).items()
              if p.get("sources", 0) > 0 and p.get("available", True) and name.startswith("headset")}
    for name in PREFERRED:
        if name in usable:
            return name
    return sorted(usable)[0] if usable else None


def headsets():
    out = []
    for card in pactl_json("list", "cards"):
        name = card.get("name", "")
        profile = best_profile(card) if name.startswith(PREFIX) else None
        if profile:
            props = card.get("properties") or {}
            out.append({"card": name, "name": props.get("device.description") or props.get("device.alias") or name,
                        "profile": card.get("active_profile"), "headset": profile})
    return out


def address(card):
    return card[len(PREFIX):] if is_card(card) else ""


def source_of(card):
    """The card's microphone in PipeWire, by its Bluetooth address (bluez_input.34_0E… or …34:0E…), or None."""
    addr = address(card)
    for src in pactl_json("list", "sources"):
        name = src.get("name", "")
        props = src.get("properties") or {}
        if name.endswith(".monitor"):
            continue
        if props.get("device.name") == card or props.get("api.bluez5.address", "").replace(":", "_") == addr or \
                (name.startswith("bluez_input.") and addr in name.replace(":", "_")):
            return name
    return None


def set_profile(card, profile):
    done = subprocess.run([PACTL, "set-card-profile", card, profile], capture_output=True, text=True, timeout=10)
    if done.returncode != 0:
        raise BluetoothError(f"The headset couldn't switch to its microphone: {done.stderr.strip() or profile}.")


def use(card):
    """The card in its headset profile; its source's node name, and the profile it was in before (None if it was
    already in a headset profile, so nothing is to be put back)."""
    found = next((h for h in headsets() if h["card"] == card), None)
    if not found:
        raise BluetoothError("The Bluetooth headset isn't connected: connect it, or pick another microphone (m).")
    previous = None
    if not str(found["profile"]).startswith("headset"):
        previous = found["profile"]
        set_profile(card, found["headset"])
    end = time.time() + SOURCE_WAIT
    while True:
        source = source_of(card)
        if source or time.time() > end:
            break
        time.sleep(0.1)
    if not source:
        if previous:
            restore(card, previous)
        raise BluetoothError("The headset's microphone didn't appear. Try again, or pick another microphone (m).")
    return source, previous


def restore(card, profile):
    """Back to the profile the card was in (A2DP), quietly: a headset switched off meanwhile has nothing to restore."""
    if card and profile:
        try:
            set_profile(card, profile)
        except (BluetoothError, OSError, subprocess.TimeoutExpired):
            pass


def main(argv):
    as_json = "--json" in argv
    args = [a for a in argv if a != "--json"]
    if args != ["list"]:
        print(__doc__.split("\n\n")[1], file=sys.stderr)
        return 2
    out = headsets()
    print(json.dumps(out) if as_json else "\n".join(f"{h['card']}  {h['name']} ({h['profile']})" for h in out)
          or "No Bluetooth headsets are connected.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
