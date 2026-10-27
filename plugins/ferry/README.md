# Ferry

A mailbox between your computers and your phone. Leave photos, files, text or a link at one end, and pick them up at the other. The phone needs no app, and the two don't have to be on the same network: Ferry goes over Tailscale, so it works from anywhere.

![Ferry's menu in the top bar](ferry.jpg)

Ferry is an app of its own, for Linux, the Mac and the iPhone, and comes with Nightdrive: its latest release, with its window and Files' "Open With → Ferry", and its menu in Nightdrive's top bar, where other desktops have Ferry's tray icon. Its window floats in the middle in Nightdrive's colours, and ⌘⇧T tiles it. `nightdrive update` updates Ferry too (removed, `nightdrive apps install ferry` brings it back). Welcome to Nightdrive sets it up after Tailscale. A Ferry from before, when the plugin had its own server, moves over with its phones and its box.

## On the computer

- The menu lists what your other devices sent: a click on a row copies a text or opens a file (the round mark on the right says which), a file drags out into another app, and Clear empties the list (files stay in Downloads).
- Below the list are the three ways to send, as in the phone's app: **Aa** types a text, **Send Clipboard** sends the clipboard, and **+** picks files. They go to the device in the pill above them: click it to pick another of your computers or phones (Ferry remembers the last one picked), or to add a device.
- Drag files over the menu and the list turns into a tile for each device: drop them on the one they're for. Files dropped on the inbox icon in the top bar go to the picked device.
- **Settings** beside Clear opens the settings: click a device there twice to forget it when you no longer use it. It leaves the lists on all your devices, and a phone gets no more notifications. It stays gone until you add it again with Add Device, which is there too.
- A send to a phone waits in the box until that phone picks it up, and only that phone gets the notification. A send to another computer goes straight there: it shows up in that computer's menu, and Send Clipboard puts it on that computer's clipboard. A computer that's asleep can't take one.
- Files from the phone go to Downloads, and you get a notification when something arrives (a photo or an image shows in it, as a screenshot does).
- What the phone sends with Clipboard lands on the computer's clipboard too, ready to paste (an image also stays in Downloads).
- Everything leaves the box after 7 days. A text that looks like a code or a password leaves after 15 minutes, or as soon as it's copied (Send Clipboard's is copied already, so the box doesn't keep it at all).
- A notification doesn't show a code or a password: it says "Code or password · open to see", and its Copy still copies it. What Send Clipboard brings, and a code or a password you copy, stays out of the clipboard history (cliphist).

## On the phone

Pick Add Device in the pill's list in Ferry's menu, scan the QR code (or open the address) in the phone's browser and add the page to the Home Screen. Open Ferry from there and tap Turn on notifications.

- Received has what your computers sent to this phone: tap a row to copy a text or save a file, or swipe it away.
- The bar at the bottom sends: **Aa** for a text, **Send Clipboard** for the clipboard (a text, or an image such as a screenshot: iOS doesn't give a page a photo copied from Photos), and **+** for photos and files.
- With Ferry on several computers, the phone sees them all on one page and sends to the one you're using (the one with the latest key press or mouse move). Tap its name above the bar to pick another for one send.

If Ferry's menu says Tailscale needs permission, run these once:

```
sudo tailscale set --operator=$USER
ferry enable
```

## In a terminal

The `ferry` command does the same, and `ferry help` lists all of it.

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
