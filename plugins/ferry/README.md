# Ferry

A mailbox between your computers and your phone: leave photos, files, text or a link at one end, and pick them up at the other. The phone needs no app, and Ferry goes over Tailscale, so it works from anywhere.

![Ferry's menu in the top bar](ferry.jpg)

Ferry is an app of its own, for Linux, the Mac and the iPhone, and comes with Nightdrive: its latest release, with its menu in the top bar; `nightdrive update` updates it too (removed, `nightdrive apps install ferry` brings it back). Welcome to Nightdrive sets it up after Tailscale. ⌘⇧T tiles its window. A Ferry from before, when the plugin had its own server, moves over with its phones and its box.

## On the computer

- The menu lists what your other devices sent: a click copies a text or opens a file, and a file drags out into another app.
- **Aa**, **Send Clipboard** and **+** send a text, the clipboard or files to the device in the pill above them. Click the pill to pick another device or add one. Files dragged over the menu can be dropped on any device's tile, or on the inbox icon in the top bar for the picked one.
- A send to a phone waits in the box until that phone picks it up. A send to another computer goes straight there (not while it's asleep), and Send Clipboard puts it on that computer's clipboard.
- What arrives goes to Downloads, with a notification. The phone's Send Clipboard lands on the clipboard too.
- Everything leaves the box after 7 days, a code or a password after 15 minutes or as soon as it's copied. Codes and passwords stay out of notifications and the clipboard history.
- **Settings** (beside Clear) forgets a device on all your devices: click it twice. Add it back with Add Device.

## On the phone

Pick Add Device in the pill's list, scan the QR code (or open the address) in the phone's browser and add the page to the Home Screen. Open Ferry from there and tap Turn on notifications.

- Received has what your computers sent: tap a row to copy a text or save a file, or swipe it away.
- **Aa**, **Send Clipboard** and **+** send as on the computer. iOS doesn't give a page a photo copied from Photos: send it with +.
- With Ferry on several computers, the phone sends to the one you're using (the latest key press or mouse move). Tap its name above the bar to pick another for one send.

If Ferry's menu says Tailscale needs permission, run these once:

```
sudo tailscale set --operator=$USER
ferry enable
```

## In a terminal

`ferry help` lists all of it.

| Command | What it does |
| --- | --- |
| `ferry send [file…]` | Sends files, or a text; with nothing, the clipboard. `--to DEVICE` for another device than the picked one |
| `ferry devices` | Your other computers running Ferry and your phones, the picked one marked |
| `ferry target [DEVICE]` | The device sends go to, or picks another |
| `ferry forget DEVICE` | Takes a device off the lists on all your devices |
| `ferry list` | What's in the box, numbered |
| `ferry get [n]` | An item from the phone (the newest without a number): a text printed, a file saved here |
| `ferry open <n>` | Opens a file |
| `ferry copy <n>` | Copies a text |
| `ferry qr` | The page's QR code, for adding a phone |

## Privacy

Only you can get in. The page isn't on the internet (tailscale serve, not Funnel), and it answers only the Tailscale user who owns the computer. Nothing that arrives is opened or run by itself. The phone is the key: if it's lost unlocked, remove it in Tailscale's admin console. Ferry suits a computer that is yours alone, and its tailnet name (computer.tailXXXX.ts.net) shows in public certificate logs.

Homepage: https://github.com/nightdrive-sh/ferry
Needs: Tailscale on the computer and the phone, with HTTPS certificates turned on for the tailnet ([Tailscale's admin console › DNS](https://login.tailscale.com/admin/dns)), then `ferry enable`
