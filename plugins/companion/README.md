# Companion

Nightdrive on an iPad or a phone: your Claude Code sessions, a big dictation button and six buttons of your own, as a web app on the home screen. It reaches the computer over Tailscale, from anywhere.

- **Sessions** are tiles that keep their places: project managers' sessions (a name with *Project Manager* or *PM*) first, then in the order the sessions started; one that needs you shows it in its colour. Answer a permission request (Allow, Deny), answer a question by dictating, stop a session (Esc). A tap on a tile brings its window up on the desktop; *Show* opens the session on the whole screen: what it said and did lately, as it goes, with its buttons, and *Close session*, which closes its window on the computer. A tile shows what the session did last.
- **Dictate:** hold the button and talk, let go and it is sent into the window that has the keyboard on the computer, which the panel names; into a Claude session with Enter, as its prompt. Hold a session's *Answer* to talk into that session the same way. A tap on it, or *New session*, opens a box with the same button, and *Write* to type instead.
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
- Only your own Tailscale user gets in, from their own devices (not a tagged one, not over Funnel); nothing else on the computer reaches the server. Anyone with that login's device in hand can type into your sessions, and a command in a slot runs on the computer as you: keep the iPad locked.

Needs: the Tailscale plugin, logged in on the computer and the iPad or phone
