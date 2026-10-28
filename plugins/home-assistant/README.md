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

Claude (Settings › Claude › Access › Home Assistant) can read the states, and switch a device only after you allow it on
Nightdrive's confirmation card, which shows the device and its new state.

Homepage: https://www.home-assistant.io
Needs: a Home Assistant server
