#!/usr/bin/env python3
"""A stand-in for pactl in bluetooth_test.py: one Bluetooth headset (an AirPods-like card) whose microphone source
exists only in a headset profile, as PipeWire's does. Its state is the JSON file FAKE_PACTL_STATE ({profile,
switches: [profiles set, in order]}); FAKE_PACTL_NO_SOURCE keeps the source from appearing."""

import json
import os
import sys

CARD = "bluez_card.34_0E_22_1C_90_DC"
STATE = os.environ["FAKE_PACTL_STATE"]


def load():
    try:
        with open(STATE) as f:
            return json.load(f)
    except OSError:
        return {"profile": "a2dp-sink", "switches": []}


def profile(sources, desc):
    return {"description": desc, "sinks": 1, "sources": sources, "available": True}


state = load()
args = [a for a in sys.argv[1:] if a not in ("-f", "json")]
if args == ["list", "cards"]:
    out = [{"name": "alsa_card.platform-sound", "active_profile": "HiFi", "properties": {},
            "profiles": {"HiFi": profile(1, "HiFi")}},
           {"name": CARD, "active_profile": state["profile"], "properties": {"device.description": "Jari (AirPods)"},
            "profiles": {"off": profile(0, "Off"), "a2dp-sink": profile(0, "A2DP (AAC)"),
                         "headset-head-unit-cvsd": profile(1, "CVSD"), "headset-head-unit-msbc": profile(1, "mSBC"),
                         "headset-head-unit": profile(1, "LC3")}}]
    print(json.dumps(out))
elif args == ["list", "sources"]:
    out = [{"name": "alsa_input.platform-sound", "properties": {}}]
    if state["profile"].startswith("headset") and not os.environ.get("FAKE_PACTL_NO_SOURCE"):
        out.append({"name": "bluez_input.34:0E:22:1C:90:DC", "properties": {"api.bluez5.address": "34:0E:22:1C:90:DC"}})
    print(json.dumps(out))
elif args[:1] == ["set-card-profile"] and len(args) == 3:
    if args[1] != CARD:
        print(f"Failure: No such entity: {args[1]}", file=sys.stderr)
        sys.exit(1)
    state["profile"] = args[2]
    state["switches"].append(args[2])
    with open(STATE, "w") as f:
        json.dump(state, f)
else:
    print("fake pactl: " + " ".join(sys.argv[1:]), file=sys.stderr)
    sys.exit(1)
