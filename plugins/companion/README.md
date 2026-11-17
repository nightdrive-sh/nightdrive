# Companion

Nightdrive on an iPad or a phone: your Claude Code sessions, a big dictation button and five buttons of your own, as a web app on the home screen. It reaches the computer over Tailscale, from anywhere.

- **Sessions** are tiles, the ones that need you first. Answer a permission request (Allow, Deny), answer a question by dictating, stop a session (Esc) or bring its window up on the desktop. A tile shows what the session did last.
- **Dictate:** hold the button and talk, let go, read and fix it, send. It goes into the session that asks you something, else into the window that has the keyboard; tap *Into* for another session or a new one. *Press Enter* sends it as the prompt.
- **Actions:** tap an empty slot to pick what it does (Lock, Mute mic, Do not disturb, music, a new Claude session) or write a command of your own. Hold a slot to change it.
- The colours follow your theme.

## Setting up

Needs the Tailscale plugin, logged in, on the computer and the iPad. Installing turns it on and prints the address:

```
companion enable     # https://<computer>.<tailnet>.ts.net:8443
```

Open that on the iPad in Safari, then Share › *Add to Home Screen*. `companion url` prints the address again, `companion disable` turns it off. `companion demo` shows it with made-up sessions on http://127.0.0.1:8746, without touching the desktop.

## Limits

- Experimental, and only the control panel so far. Mail, Deck and a terminal come later, over the same server ([protocol.md](protocol.md)).
- Sending text and Stop bring the session's window to the front on the desktop, as Send to Claude does.
- Allow is offered only when the request shows all it allows, as in the desktop notification. Otherwise answer in the terminal.
- A permission request asked while you're in that session's window on the desktop isn't shown: Claude Code asks there.
- Dictation uses the browser's speech recognition (Apple's). Where there is none, tap the button and use the keyboard's microphone key.
- Only your own Tailscale user gets in. A command in a slot runs on the computer as you.

Needs: the Tailscale plugin, logged in on the computer and the iPad or phone
