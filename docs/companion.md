# Companion

Nightdrive on an iPad or a phone: your Claude Code sessions, a big dictation button and six buttons of your own, as a web app on the home screen. It reaches the computer over Tailscale, from anywhere.

- **Sessions** are tiles that keep their places: project managers' sessions (a name with *Project Manager* or *PM*) first, in the sessions bar's order (by workspace), then the rest in the order they started. Their icons are the sessions bar's. Answer a permission request (Allow, Deny), answer a question by dictating, stop a session (Esc). A question Claude asks with choices (AskUserQuestion) shows whole, each choice a button with what it means: *Question* on the tile opens it, *Show* has it under the session. *Own answer* takes words of your own instead, dictated or written; with several questions or choices, *Send answers*. A tap on a tile brings its window up on the computer; *Show* opens the session on the whole screen: what it said and did lately, as it goes, with its buttons: *Answer* to hold and talk as on the tile, *Write* to type, and *End*, which closes its window on the computer.
- **Dictate:** hold the button and talk, let go and it is sent into the window that has the keyboard on the computer, which the panel names; into a Claude session with Enter, as its prompt. Hold a session's *Answer* to talk into that session the same way. A tap on it, or *New session*, opens a box with the same button, and *Write* to type instead.
- **Actions:** tap an empty slot to pick what it does (Lock, Mute mic, Do not disturb, music, a new Claude session) or write a command of your own. Hold a slot to change it.
- **Usage:** the gauge in the top right corner: every Claude account's 5-hour and week limits.
- **Away:** when the computer is locked or has had no input for 5 minutes, the top bar says *Away* and a tap on a tile opens the session here instead of bringing its window up there. Tap *Away* / *At the computer* to say it yourself: that holds until the computer sees you lock it, leave it or come back.
- The colours follow your theme.

## Turning it on

Needs Tailscale, logged in, on the computer and the iPad (Settings › Tailscale). Then **Settings › Companion** (or `nightdrive companion on`) turns it on and shows the address: `https://<computer>.<tailnet>.ts.net:8443`. Open that on the iPad in Safari, then Share › *Add to Home Screen*.

`nightdrive companion off` turns it off, `url` prints the address, `status --json` says how it is. It is off until you turn it on, and starts with the desktop while it is on. While no page has it open, the server sleeps: it costs no battery.

If Tailscale refuses (*Run once: sudo tailscale set --operator=$USER*), run that once in a terminal and turn it on again.

## Limits

- Several computers: each has its own address, and a web app of its own on the iPad.
- Sending text and Stop bring the session's window to the front on the computer, as Send to Claude does.
- A permission request for an edit, a write, an MCP tool or a long command has *Review*: it shows what it would do whole (the file, the text taken out and put in, the tool's input), with Deny and Allow under it. A character that wouldn't show is written out as ⟨U+…⟩. One over 200,000 characters is answered in the terminal.
- A question with choices can be answered here for about ten minutes, and not when it was asked while you were in that session's window on the computer, or once you go there or close its notification: then answer it in its terminal (the tile says so).
- A permission request asked while you're in that session's window on the computer isn't shown: Claude Code asks there.
- Dictation uses the browser's speech recognition (Apple's). Where there is none, a tap opens a box to write in.
- Only your own Tailscale user gets in, from their own devices (not a tagged one, not over Funnel); nothing else on the computer reaches the server. Anyone with that login's device in hand can type into your sessions, and a command in a slot runs on the computer as you: keep the iPad locked.
- How the page and the server talk: [config/companion/protocol.md](../config/companion/protocol.md).
