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

An `http://` address sends the token as plain text, and the addresses are tried wherever you are: on another network, whatever answers `homeassistant.local` gets it. Use an `https://` address or Tailscale where you can (the installer warns about the others).

## From a terminal, and Claude

| Command | What it does |
| --- | --- |
| `home-assistant states` | The devices and their states as JSON; `--search TEXT` only those whose name, area or id has it, `--sensors` adds the sensors |
| `home-assistant set ID STATE` | Puts a device in a state, whatever it is now: `on`/`off`, `open`/`close` (covers), `lock`/`unlock`, `run` (scenes, scripts, buttons) |
| `home-assistant toggle ID` | Switches a device the other way, as Enter in the Launcher does |
| `home-assistant brightness ID PCT` | Sets a light's brightness, 0–100 (0 turns it off) |

Claude (Settings › Claude › Access › Home Assistant) can read the states, and switch a device only after you allow it on
Nightdrive's confirmation card, which shows the device's name and room from Home Assistant beside its id, and the new
state. It dims a dimmable light on the card too (its brightness now and the new one), with Undo back to what it was.
Unless you turn them on in Access › Home Assistant › (they are on only on the Open level), Claude may not:

- unlock a lock or open a cover (a door, a gate, blinds): it only locks and closes, and runs no scene that sets one,
- turn an automation on or off: it can run one, but not stop one that guards (a leak alarm),
- read presence, occupancy or motion sensors, an `input_boolean` that says whether anyone is home (`someone_home`, `away_mode`), or where your phones are (the companion app's location, distance, Wi-Fi and activity sensors).

These hold for Claude's calls only: the Launcher, the Home menu and `home-assistant` in a terminal do as before. A door
Home Assistant has as a `switch` is a switch to it, and a script may do anything: the card warns when one's name says a
door, gate or lock, but keep such a relay or script out of Claude's reach in Home Assistant itself.

Homepage: https://www.home-assistant.io
Needs: a Home Assistant server
