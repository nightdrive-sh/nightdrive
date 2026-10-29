# VNC Display

Use an iPad, an iPhone or any tablet, phone or computer with a VNC app as one more display of this computer, as Sidecar does on a Mac. The device shows a display of its own in a free VNC app, over Tailscale, at home or away, and each device has its own workspace on it.

## On the computer

Add the device in Settings › Other displays › Add a display: an iPad, iPhone, MacBook Pro 16-inch or 4K display, or Other device for the rest (an Android tablet, a laptop): its screen's width and height in pixels, and a scale shown as the size things look (Tab and ⇧Tab move between the fields). Its row there turns its display on and off, and shows how to connect: Show QR code puts a code for the device's camera on your display, with the password beside it. The password shows only when you ask for it. Or in a terminal, which prints the address, user name and password:

    vnc-display add ipad               # an iPad, beside your displays
    vnc-display add iphone             # an iPhone, a display for when you're away from the desk
    vnc-display add ipad --home        # also on the home Wi-Fi, without Tailscale on the iPad

- The first display gets workspace 9 (⌘9), the next 8, then 7 and 6: Workspace on its page in Settings › Other displays changes it, to any of 2–9 (1 stays on your main display). The top bar shows it as a tablet or phone icon.
- An iPad's display is to the right of yours: the pointer slides over the edge onto it. A phone's is away, so the pointer never strays there. Place on its page in Settings › Other displays puts it on another side; several on one side go outwards in the order you added them.
- The display is there while the device is connected. When the device disconnects, the display goes, its windows move to workspace 1 and its icon leaves the top bar; it comes back when the device connects again. While its row is on, this computer waits for the device, also after a login: turn it off in Settings › Other displays (or `vnc-display off ipad`) and nothing listens for it.
- The device uses this computer's own pointer and keyboard: a tap on the iPad moves the pointer there.
- Size on its page changes the display's size and scale (a connected device reconnects to it), and Name renames it. The name is also the user name in the VNC app, so change it there too.
- Sizes: `ipad` (11-inch), `ipad-13`, `ipad-mini`, `iphone`, `iphone-max` (Pro Max), `macbook-16` (MacBook Pro 16-inch), `display-4k` (3840 × 2160 at scale 2), or your own in pixels and scale, e.g. `2752x2064@2`. A second device of the same kind needs a name: `vnc-display add ipad ipad2`.

## On the iPad or iPhone

1. Install Tailscale from the App Store and sign in with the same account as on this computer. Leave it on: it also works on mobile data, away from home.
2. Install RealVNC Viewer from the App Store (free; other VNC apps work too).
3. Scan the QR code from Settings › Other displays with the camera, or add a connection by hand with the address, such as `nightdrive:5900` (this computer's Tailscale name). Type the user name and password, and let the app remember them. The first time, the app asks whether to trust the computer: yes.

In RealVNC Viewer, Touch panel mode under the connection's settings makes your finger a touchpad, which is easier for small targets. If the name doesn't connect (MagicDNS off in Tailscale), use the IP address Settings › Other displays shows.

Another device works the same way with Tailscale and any VNC app: RealVNC Viewer on Android, Remmina or TigerVNC on Linux.

On a Mac, use TigerVNC Viewer (free, no account: tigervnc.org, or `brew install --cask tigervnc-viewer`). macOS's own Screen Sharing can't connect, and RealVNC Viewer on a Mac wants an account. TigerVNC draws one pixel per point, not Retina's two, so `macbook-16` is 1728 × 1080 at scale 1: in full screen (F8 › Full screen) it fills the screen below the notch at the Mac's default size, softer than the Mac's own apps. It asks for the password every time.

## Limits

- One pointer and keyboard for all the displays: while you use the iPad, the desk's pointer is there too.
- No sound: it plays on this computer.
- Over mobile data the picture lags more than on Wi-Fi, and it uses data: fine for a chat or notes, not for video.

## In a terminal

| Command | What it does |
| --- | --- |
| `vnc-display add DEVICE [NAME]` | A new display for a device, with a password of its own. `--home`: also on the home Wi-Fi. `--beside` or `--away` changes where it goes |
| `vnc-display show NAME` | The addresses, user name and password (`--json` for scripts) |
| `vnc-display qr NAME` | The connection as a QR code (an SVG file) |
| `vnc-display list` | The devices, their workspaces and whether they're on or connected (`--json` for scripts) |
| `vnc-display workspace NAME N` | Gives its display workspace N (2–9), its windows too: a device that has N takes this one's |
| `vnc-display place NAME PLACE` | Puts its display right, left, above or below yours, or away (out of the pointer's reach) |
| `vnc-display size NAME DEVICE` | Changes its display's size and scale: a size as `add` takes it (`ipad-13`, `2560x1600@2`). A connected device reconnects |
| `vnc-display rename NAME NEW` | Renames it; the new name is also its user name in the VNC app |
| `vnc-display off NAME` | Turns it off: nothing listens for it, and a connected device's display goes, its windows back to yours |
| `vnc-display on NAME` | Turns it back on, with the same password: its display comes when the device connects |
| `vnc-display remove NAME` | Forgets the device: its display and its password |

## Privacy

- Nothing listens until you add a device. Each one has its own port, from 5900 up, and listens only on this computer's Tailscale addresses (IPv4 and IPv6), which only your own devices can reach. With `--home`, also on the home Wi-Fi it was added on, and only while you're on that network.
- The QR code holds only the address. Every device has its own random password; `remove` makes it useless. The passwords are kept in `~/.config/nightdrive/vnc-display`, readable only by you.
- The connection is encrypted (RSA-AES). Apps that use Apple's own login (such as Screens) are let in without it over Tailscale, which encrypts everything anyway, but not on the home Wi-Fi.

Homepage: https://github.com/any1/wayvnc
Needs: Tailscale on this computer and on the device, and a VNC app on the device
