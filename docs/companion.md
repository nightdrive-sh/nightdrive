# Companion

Nightdrive on an iPad or a phone: your Claude Code sessions, a big dictation button and six buttons of your own, as a web app on the home screen. It reaches the computer over Tailscale, from anywhere.

- **Sessions** are tiles that keep their places: project managers' sessions (a name with *Project Manager* or *PM*) first, in the sessions bar's order (by workspace), then the rest in the order they started. Their icons are the sessions bar's. Answer a permission request (Allow, Deny), answer a question by dictating, stop a session (Esc). A session at work takes words too, as its terminal does mid-turn: *Answer* beside *Stop*. A question Claude asks with choices (AskUserQuestion) shows whole, each choice a button with what it means: *Question* on the tile opens it, *Show* has it under the session. *Own answer* takes words of your own instead, dictated or written; with several questions or choices, *Send answers*. A finished session's tile (the green check) has *End* beside *Show* and *Answer*, which ends it without asking. On a narrow tile (a phone, a portrait iPad), Show, Stop and End are their icons alone. A tap on a tile brings its window up on the computer; *Show* opens the session on the whole screen: what it said and did lately, as it goes (a run of steps is one line, *8 steps · Bash, Dashboard, Inbox*, that a tap opens; a failed or denied step, and the newest while it works, show anyway), with its buttons: *Answer* to hold and talk as on the tile, *Write* to type, and *End*, which closes its window on the computer. What you send shows at the end at once, faded until the session has it; words that don't get there say so, with *Send again*. A swipe from the left edge goes back to the tiles (in a browser, its Back does too).
- **Dictate:** hold the button and talk, let go and it is sent into the window that has the keyboard on the computer, which the panel names; into a Claude session with Enter, as its prompt. Hold a session's *Answer* to talk into that session the same way. A tap on it, or *New session*, opens a box with the same button, and *Write* to type instead.
- **The computer's microphone** (Nightdrive's iOS app): with the computer's lid closed, its dictation key (F5, Fn, and ⌘⇧ with it for Ask Claude) listens through the app instead, while the app is open in front on the iPad or iPhone. The app shows *Listening for <computer>*, the computer's dictation card names the device (*IPAD*), and the words go where the computer's own dictation would put them. They are recognised on the device (Apple's speech recognition). While the computer wants it and the iPad is charging, its screen stays on, so it keeps hearing. With the lid open, or no app ready, the computer's own microphone listens.
- **Actions:** tap an empty slot to pick what it does (Lock, Mute mic, Do not disturb, music, a new Claude session) or write a command of your own. Hold a slot to change it.
- **Usage:** the gauge in the top right corner: every Claude account's 5-hour and week limits.
- **Inbox:** the mailbox beside it, with how many are unread, opens [Inbox](inbox.md)'s messages: their text and pictures, newest first; opening one marks it read. *Mark unread* and *Archive* are under it. On an iPad on its side the list and the message are side by side. Other files open in the browser; a message's buttons are only in the Inbox on the computer for now.
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
- A question with choices or a permission request stays here as long as it is open in the terminal, up to a day, and goes once it is answered anywhere. With an older Claude Code, which keeps no record of its sessions, it is here for about ten minutes, and not when it was asked while you were in that session's window: then answer it in its terminal (the tile says so).
- Dictation uses the browser's speech recognition (Apple's). Where there is none, a tap opens a box to write in.
- Only your own Tailscale user gets in, from their own devices (not a tagged one, not over Funnel); nothing else on the computer reaches the server. Anyone with that login's device in hand can type into your sessions, and a command in a slot runs on the computer as you: keep the iPad locked.
- How the page and the server talk: [config/companion/protocol.md](../config/companion/protocol.md).
