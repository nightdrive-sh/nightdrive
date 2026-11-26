# Home Assistant

Your smart home on the desktop: lights, switches and scenes from the Launcher and the top bar.

| Keys | |
| --- | --- |
| Enter | Turn a device on or off |
| ← → | Dim a light |
| Shift+Enter | Pin a device to the top bar's Home menu |

- Launcher › Home has your rooms, devices, scenes and scripts.
- In the top bar's Home menu, a click switches a device and the scroll wheel dims it. The house fades while Home Assistant doesn't answer, and a right click opens Home Assistant itself.
- Give it several addresses (home, Tailscale, Nabu Casa), and it uses the first one that answers.

## Setting up

The installer asks for your Home Assistant addresses and a long-lived access token (in Home Assistant: your profile › Security; a 1Password op:// reference works too). Run it again to change them.

An `http://` address sends the token as plain text, so it is used only on your home network: anywhere else, whatever answers `homeassistant.local` would get it. Away from home Home uses Tailscale or an `https://` address (Nabu Casa), so give it one of those too. An `http://` address on your tailnet (`ha:8123`) counts as Tailscale while it really goes through it.

The installer asks whether the network you're on is your home network. On a network you haven't answered for, where your local address answers, a notification asks: This is home, or Not here. A home network is known by its Wi-Fi or wired connection and its router together, so after a new router you're asked again. `home-assistant home` shows the networks you've answered for; `home add`, `home not` and `home forget` change the answer for the one you're on.

## From a terminal, and Claude

| Command | What it does |
| --- | --- |
| `home-assistant states` | The devices and their states as JSON; `--search TEXT` only those whose name, area or id has it, `--sensors` adds the sensors |
| `home-assistant set ID STATE` | Puts a device in a state, whatever it is now: `on`/`off`, `open`/`close` (covers), `lock`/`unlock`, `run` (scenes, scripts, buttons) |
| `home-assistant toggle ID` | Switches a device the other way, as Enter in the Launcher does |
| `home-assistant brightness ID PCT` | Sets a light's brightness, 0–100 (0 turns it off) |
| `home-assistant home` | Your home networks, as JSON; `home add` / `home not` / `home forget` for the network you're on |

Claude (Settings › Claude › Access › Home Assistant) can read the states, and switch a device only after you allow it on
Nightdrive's confirmation card, which shows the device's name and room from Home Assistant beside its id, and the new
state. It dims a dimmable light on the card too (its brightness now and the new one), with Undo back to what it was.
Unless you turn them on in Access › Home Assistant › (they are on only on the Open level), Claude may not:

- unlock a lock or open a cover (a door, a gate, blinds): it only locks and closes, and runs no scene that sets one, nor a script or automation that would, also through a scene or script it starts (it reads what they do from Home Assistant, and doesn't run one it can't read: one made in YAML outside the UI's files),
- turn an automation on or off: it can run one, but not stop one that guards (a leak alarm),
- read presence, occupancy or motion sensors, read or switch an `input_boolean` that says whether anyone is home (`someone_home`, `away_mode`), or see where your phones are (the companion app's location, distance, Wi-Fi and activity sensors).

These hold for Claude's calls only: the Launcher, the Home menu and `home-assistant` in a terminal do as before. A door
Home Assistant has as a `switch` is a switch to it, and so is a script that turns that switch on: the card warns when
one's name says a door, gate or lock, but keep such a relay out of Claude's reach in Home Assistant itself.

Homepage: https://www.home-assistant.io
Needs: a Home Assistant server
