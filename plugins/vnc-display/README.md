# VNC Display

Use an iPad or iPhone as one more screen of this computer, as Sidecar does on a Mac. The device shows a screen of its own in a free VNC app, over Tailscale, at home or away, and each device has its own workspace on it.

## On the computer

Add the device in a terminal. It prints the address, user name and password to type into the VNC app:

    vnc-display add ipad               # an iPad, beside your screens
    vnc-display add iphone             # an iPhone, a screen for when you're away from the desk
    vnc-display add ipad --home        # also on the home Wi-Fi, without Tailscale on the iPad

- The first screen gets workspace 9 (⌘9), the next 8, then 7 and 6. The top bar shows it as a tablet or phone icon.
- An iPad's screen is to the right of your screens: the pointer slides over the edge onto it. A phone's is far off, so the pointer never strays there.
- The screen stays on, also after a login, until you turn it off. While it's on but no device shows it, its windows are out of sight: `vnc-display off ipad` when you don't use it, `vnc-display on ipad` to bring it back.
- The device uses this computer's own pointer and keyboard: a tap on the iPad moves the pointer there.
- Sizes: `ipad` (11-inch), `ipad-13`, `ipad-mini`, `iphone`, `iphone-max` (Pro Max), or your own in pixels and scale, e.g. `2752x2064@2`. A second device of the same kind needs a name: `vnc-display add ipad ipad2`.

## On the iPad or iPhone

1. Install Tailscale from the App Store and sign in with the same account as on this computer.
2. Install a VNC app, such as RealVNC Viewer (free).
3. Add a connection in it with the address `vnc-display add` printed (`vnc-display show ipad` shows it again), then the user name and password. The first time, the app asks whether to trust the computer: yes.

In RealVNC Viewer, Touch panel mode under the connection's settings makes your finger a touchpad, which is easier for small targets.

## In a terminal

| Command | What it does |
| --- | --- |
| `vnc-display add DEVICE [NAME]` | A new screen for a device, with a password of its own. `--home`: also on the home Wi-Fi. `--beside` or `--away` changes where it goes |
| `vnc-display show NAME` | The addresses, user name and password |
| `vnc-display list` | The devices, their workspaces and whether they're on (`--json` for scripts) |
| `vnc-display off NAME` | Turns the screen off: its windows go back to your screen, and nothing listens for it |
| `vnc-display on NAME` | Turns it back on, with the same password |
| `vnc-display remove NAME` | Forgets the device: its screen and its password |

## Privacy

- Nothing listens until you add a device. Each one has its own port, from 5900 up, and listens only on this computer's Tailscale address, which only your own devices can reach. With `--home`, also on the home Wi-Fi it was added on, and only while you're on that network.
- Every device has its own random password; `remove` makes it useless. The passwords are kept in `~/.config/nightdrive/vnc-display`, readable only by you.
- The connection is encrypted (RSA-AES). Apps that use Apple's own login (such as Screens) are let in without it over Tailscale, which encrypts everything anyway, but not on the home Wi-Fi.

Homepage: https://github.com/any1/wayvnc
Needs: Tailscale on this computer and on the device, and a VNC app on the device
