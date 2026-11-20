# Companion's protocol

What the web app (`web/`) and the server (`bin/companion run`) say to each other. The apps that come later (Mail, Deck,
a terminal) get their own sections here, over the same server.

## Access

The server has no port: it listens on a Unix socket, `$XDG_RUNTIME_DIR/nightdrive/companion.sock`, and lets only
tailscaled (root) connect. `tailscale serve` puts it on the tailnet over HTTPS (`https://<machine>.<tailnet>.ts.net:8443`),
which adding it to the home screen needs. tailscale serve drops a `Tailscale-User-Login` the device sent and sets its
own; the server answers only the machine's own Tailscale user's. A request without one (a tagged device, Funnel) is
refused. No other user of the computer, and no web page in a browser on it, reaches the API (`lib/access.py`).

The demo (`companion demo`) is on `127.0.0.1:8746`, answers only that Host, and does nothing on the desktop.

Pages carry a Content-Security-Policy of their own files only, and can't be framed.

Every `POST` needs the header `X-Companion: 1`: a web page elsewhere can't send one without asking first (CORS), and the
server never says yes, so a page open in a browser here can't press the buttons.

## State

`GET /api/state` → the whole state; `GET /api/events` → the same as Server-Sent Events, an `event: state` with the whole
state each time something changes, and an `event: ping` every 15 s while nothing does: the page opens the stream again
when it hears nothing for 40 s (iOS can leave a dropped connection silent).

```json
{
  "host": "nightdrive-pc",
  "demo": false,
  "theme": { "primary": "#c071eb", "accent": "#e0bff2", "...": "Theme.qml's roles" },
  "usage": { "windows": [{ "key": "session", "percent": 62, "resetsAt": "2026-11-17T15:40:00Z" }] },
  "sessions": [{
    "id": "0x5d1f2a40",          // the session's window (hyprctl address)
    "project": "nightdrive",     // its folder's name
    "dir": "/home/me/dotfiles",
    "topic": "Companion proto",  // from the window's title
    "name": "Companion proto",   // its own name (/rename), else the topic: the tile's title, the project under it
    "state": "permission",       // permission | waiting | working
    "wants": true,               // finished or stopped to ask while you were elsewhere
    "done": false,               // its last reply signs off with ✅, as the sessions bar's green check (never a PM's)
    "pm": false,                 // a project manager's session ("Project Manager", "PM"): first, with the robot
    "started": 1794868000,       // epoch seconds
    "since": 1794869200,         // when its status last changed: how long it has worked on this turn, or waited
    "last": "Bash: npm test",    // its last tool call, or the start of its last text (the question it asks)
    "asks": "input needed",      // it waits for you in its terminal (AskUserQuestion); else ""
    "question": {                // only while Companion can answer that question (claude-notify waits for it)
      "request": "Qa81Qz",
      "questions": [{ "question": "Which order?", "header": "Order", "multiSelect": false,
                      "options": [{ "label": "Newest reply", "description": "A thread moves up when…" }] }]
    },
    "permission": {              // only while state is permission
      "tool": "Bash", "what": "nightdrive sandbox check", "request": "Xa81Qz", "allow": true,
      "review": false            // true: Allow only after GET …/permission has shown it whole (below)
    }
  }],
  "active": { "session": "0x5d1f2a40", "name": "nightdrive", "detail": "Companion proto" },  // the window with the keyboard
  "presence": { "away": false, "why": "", "set": false },  // below
  "actions": [null, { "label": "Lock", "icon": "lock", "preset": "lock" }, null, null, null, null],
  "web": "3fa2c91d"              // a stamp of web/'s files: when it changes, the page offers to reload
}
```

An answer names the `request` it was shown: when the session asks something else by then, it is refused, and the
hook (which gets `allow|deny REQUEST` in `<window>.answer`) ignores one for another request. When `what` is all it
allows (a short command, as the desktop notification has it: `hypr/scripts/claude-notify`), the page shows it and Allow
beside it. Anything else (an edit, a write, an MCP tool, a long command or one with more set) has `review`: the hook left
its whole input in `<window>.input`, and the page shows it with `GET /api/sessions/ID/permission` before offering Allow
(`lib/permission.py`). An input over 200,000 characters isn't left: `allow` is false, only Deny, and the terminal has it.

A question with choices (AskUserQuestion) reaches the same hook as a permission request, which leaves `<window>.ask`
(the `question` above) and waits for `answer REQUEST {"question": "answer", …}` in `<window>.answer`; it hands that to
Claude Code as the terminal would, and the terminal's question closes. An answer is a choice's `label`, several joined
with `", "` (`multiSelect`), or words of your own (the terminal's *Type something*), after them. The hook follows Claude
Code's record of the session (`<config dir>/sessions/<pid>.json`): it waits while the question or request is open in the
terminal, up to a day (link.sh gives the hook that timeout), and stops within a second when it is answered anywhere or
the session ends, taking `question` (or `permission`) with it. Without that record (an older Claude Code) it waits 590 s
and stops when its window gets the keyboard: then `question` goes and `asks` stays, answered in the terminal.

`presence` says whether you are at the computer: away (`why`) when it is `locked`, `idle` (no input for 5 minutes,
from logind's idle hint, which hypridle sets) or you `set` it. Away, a tap on a tile opens the session's view on the
page instead of bringing its window up. `POST /api/presence` `{ "away": true }` sets it (`set` is true): it holds until
the computer's own view changes (locked, idle, in use again), then that counts again (`lib/presence.py`).

## Sessions

`GET /api/sessions/ID/permission` → its permission request whole: the `permission` above with `fields`, every key of
the tool's input in its order, `[{ "key": "new_string", "text": "…", "hidden": 0 }]`. A value is text as it is (a string)
or JSON, nothing cut; a character that wouldn't show (a bidi override, a zero-width or odd space, a control) is written
`⟨U+202E⟩`, and `hidden` counts them. 404 when it no longer asks, or its input wasn't left.

`GET /api/sessions/ID/log` → what the session said and did lately, oldest first, from its transcript (the page's view
of one session): `[{ "role": "user" | "assistant", "kind": "text" | "tool", "text": "…", "status": "…" }]`, at most 60, a
text up to 6000 characters. Tool results and thinking are left out, but a tool line has `status` from its result:
`error` (it failed), `denied` (you or a safety check said no), `running` (no result yet); none when it went through. A
tool's `text` is named to read: `Dashboard: log add` for `mcp__claude_ai_Dashboard__log_add`, `Inbox: update` for
`mcp__nightdrive__inbox_update`, a command without its leading `cd …&&`. `last` uses the same names.

| Request | Body | Does |
| --- | --- | --- |
| `POST /api/sessions/ID/allow` | `{ "request": "…" }` | Answers its permission request Allow (refused when `allow` is false; with `review`, the page sends it only from the request shown whole) |
| `POST /api/sessions/ID/deny` | `{ "request": "…" }` | Answers it Deny |
| `POST /api/sessions/ID/reply` | `{ "request": "…", "answers": { "Which order?": "Newest reply" } }` | Answers its `question`: every question, by its text |
| `POST /api/sessions/ID/send` | `{ "text": "…", "submit": true }` | Types the text in its prompt; `submit` presses Enter |
| `POST /api/sessions/ID/stop` | | Esc in its window: stops what it does |
| `POST /api/sessions/ID/focus` | | Brings its window up on the desktop |
| `POST /api/sessions/ID/close` | | Closes its window (⌘W): the session ends, its conversation kept |
| `POST /api/sessions/new` | `{ "text": "…" }` | A new session in ~/Projects, the text as its first prompt |
| `POST /api/send` | `{ "text": "…", "submit": false }` | Types the text in the window that has the keyboard; `"submit": "session"` presses Enter only when that window is a session's |

`ID` must be a session's window from the state: no other window is typed into. Sending and stopping go through the
desktop: its window comes to the front, as with ⌘⌃C (Send to Claude), and nothing is typed until it has the keyboard.

## Inbox

Nightdrive Inbox's messages (docs/inbox.md), through its own command (`nightdrive inbox … --json`, `lib/inbox.py`): the
store and its rules are the Inbox's, the same for its window, Claude's tools and this page. The state has
`"inbox": { "unread": 3, "total": 16, "stamp": "afba79a1" }`; `stamp` changes with any message (a new one, read,
archived, added to), and the page reads the list again then while its view is open.

`GET /api/inbox` → `{ "messages": [...], "total": 16, "unread": 3 }`, the newest 100 not archived, as `inbox list
--json` gives them (`id`, `title`, `at`, `read`, `task`, `sender: { short, label }`, `attachments`: how many) without
`from`. `GET /api/inbox/ID` → the message whole: its `body` (Markdown) and `attachments: [{ name, type, size, url }]`,
`actions` as a count. `GET /api/inbox/ID/files/NAME` → one of its files, only one it lists. 404 when it isn't there.
It answers byte ranges (`Range: bytes=…` → 206 with `Content-Range`, 416 past the end): iOS's `<audio>` and `<video>`
play nothing without them. `?as=m4a` on an audio file gives it as AAC (`audio/mp4`), converted by ffmpeg once and kept
in `~/.cache/nightdrive/companion/media` (30 days unused): the page asks for that when the browser can't play the file
itself, as Safari can't Ogg/Opus (`lib/media.py`, `web/media.js`). Video isn't converted.

| Request | Body | Does |
| --- | --- | --- |
| `POST /api/inbox/ID/read` | | Marks it read (the page does when it opens one) |
| `POST /api/inbox/ID/unread` | | Marks it unread |
| `POST /api/inbox/ID/archive` | | Moves it to the archive |
| `POST /api/inbox/ID/unarchive` | | Back in the Inbox |

`ID` is a whole id (`20261120-133100-da82`). The buttons (open, run, session, task) and push are not here yet.

## Actions

Six slots. `GET /api/presets` → `[{ "id": "lock", "label": "Lock", "icon": "lock" }, …]`.

| Request | Body | Does |
| --- | --- | --- |
| `POST /api/actions/N/run` | | Runs slot N (0–5) |
| `POST /api/actions/N` | `{ "preset": "lock" }`, or `{ "label", "icon", "command" }`, or `null` | Sets slot N, `null` empties it |

They're kept in `~/.config/nightdrive/companion.json`. A command runs with `bash -c`, detached, as you.

Answers: `200 {"ok": true}`, or `4xx {"error": "…"}` with the reason in plain words.

## The app

Nightdrive's iOS app (iPhone and iPad; its own repo, `nightdrive-companion`) shows this page in a web view and adds,
before the page's scripts run, `window.nightdrive`: `{ app: "ios", version: 2, device: "iPad", SpeechRecognition,
microphone }`. A browser has no `window.nightdrive`; version 1 (no `device`, `microphone`, `remote`) is the app's first.

`SpeechRecognition` is the app's own dictation (Apple's speech recognition, natively) in the Web Speech API's shape:
`lang`, `continuous`, `interimResults`, `start()`, `stop()`, `abort()`, and `onstart`, `onresult` (`results[0][0].transcript`:
all the words so far; `results[0].isFinal`), `onerror` (`error`: `not-allowed`, `no-speech`, `network`,
`language-not-supported`, `audio-capture`, `aborted`) and `onend`, last and once. `web/speech.js` takes it before the
browser's. Underneath, the page posts `{ id, op: "start" | "stop" | "abort", lang }` to
`webkit.messageHandlers.nightdriveSpeech`, and the app answers by calling `window.nightdrive._speech({ id, type, text,
final, error })`. Only this page's own origin, in the main frame, is heard. A new `start` ends the one before.

A recognition with `remote = true` (its `start` posts `remote: true`) is the computer's dictation, not a button held on
the page: while it listens the app shows a banner of its own over the page, *Listening for <computer>*.
`microphone(wanted)` posts `{ id: 0, op: "microphone", wanted }`: the page says whether the computer wants this device
as its microphone (the state's `mic.wanted`); while it does and the device is charging, the app keeps the screen on.

## The microphone

With the lid closed, the computer's dictation key listens through the app instead of the built-in microphone
(`lib/mic.py`, Dashboard #3173). The state has `"mic": { "wanted": true }` while the lid is closed.

A page in the app (bridge 2 and later) names itself with a random id per load, `DEVICE` (`app-<uuid>`), opens its stream
as `GET /api/events?mic=DEVICE`, and says it is ready while it is shown:

| Request | Body | Does |
| --- | --- | --- |
| `POST /api/mic` | `{ "device": "…", "name": "iPad", "ready": true }` | Ready (every 10 s while shown; it lapses after 25 s), or `false` when hidden |
| `POST /api/mic/event` | `{ "device": "…", "id": 3, "type": "started" \| "error" \| "text", "text": "…", "error": "…" }` | The app's answer about dictation `id` |

The server sends commands on that stream alone (its newest, if the page opened another), as `event: mic` with
`{ "op": "start" | "stop" | "abort", "id": 3 }`. On `start` the page listens (`remote`) and posts `started`, or `error`
when it can't; on `stop` it hears 0.4 s more, then posts `text`, its words (also after an error once it listened). On
`abort` it drops them and posts nothing.

The computer's side is `companion mic start | stop [ID] | abort | status [--json]` (`bin/companion`), over a Unix socket
only this user's processes may use (`lib/mic_socket.py`). `start` uses the device ready most recently and returns once it
listens; it gives up after 2.5 s (aborting it) and `hypr/scripts/dictate` then uses the computer's own microphone. `stop`
waits up to 8 s for the words. Meanwhile the server keeps `$XDG_RUNTIME_DIR/dictate-remote` (`waiting NAME`, `listening
NAME`, `transcribing NAME`) for the dictation card (`quickshell/Dictation.qml`).
