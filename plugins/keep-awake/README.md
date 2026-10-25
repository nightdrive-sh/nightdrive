# Keep Awake

Keeps the computer awake while you need it: watching, presenting, a long download. No screensaver, lock, screen-off or sleep, for a few hours or until you turn it off, and then everything comes back as usual.

- The coffee cup in the top bar is lit while Keep Awake is on. A right click turns it on until you turn it off, or off again.
- Its menu (a click on the cup) has the switch, and how long: until turned off, 1, 2, 4 or 8 hours. While a timed one is on, its row shows when it ends.
- The same is in the launcher: Tools › Keep Awake (or type awake or caffeine).
- When the time is up, it turns itself off: the screensaver, lock and screen-off come again after the usual idle times (Settings › Screensaver).
- While it's on, closing the lid doesn't put the computer to sleep either. Choosing sleep yourself still works.
- Logging out or restarting turns it off.

## In a terminal

| Command | What it does |
| --- | --- |
| `keep-awake on` | Keep awake until turned off |
| `keep-awake on 90` | Keep awake for 90 minutes |
| `keep-awake off` | Back to the usual idle times |
| `keep-awake status` | Whether it's on, and until when |

It holds a systemd idle and lid inhibitor (`systemd-inhibit`), which the desktop's idle (hypridle) honours: `systemd-inhibit --list` shows it as Keep Awake.

Needs: nothing to install (systemd-inhibit comes with systemd)
