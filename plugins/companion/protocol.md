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
state each time something changes (and a comment every 15 s to keep the connection up).

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
    "state": "permission",       // permission | waiting | working
    "wants": true,               // finished or stopped to ask while you were elsewhere
    "started": 1794868000,       // epoch seconds
    "last": "Bash: npm test",    // its last tool call, or the start of its last text (the question it asks)
    "permission": {              // only while state is permission
      "tool": "Bash", "what": "nightdrive sandbox check", "request": "Xa81Qz", "allow": true
    }
  }],
  "actions": [null, { "label": "Lock", "icon": "lock", "preset": "lock" }, null, null, null]
}
```

An answer names the `request` it was shown: when the session asks something else by then, it is refused, and the
hook (which gets `allow|deny REQUEST` in `<window>.answer`) ignores one for another request. The page shows `what`
whole. `allow` is false when the request doesn't show all it allows (a long command, an edit, an MCP tool): then only Deny, and
the rest is answered in the terminal. The same rule as the desktop notification's (`hypr/scripts/claude-notify`).

## Sessions

| Request | Body | Does |
| --- | --- | --- |
| `POST /api/sessions/ID/allow` | `{ "request": "…" }` | Answers its permission request Allow (refused when `allow` is false) |
| `POST /api/sessions/ID/deny` | `{ "request": "…" }` | Answers it Deny |
| `POST /api/sessions/ID/send` | `{ "text": "…", "submit": true }` | Types the text in its prompt; `submit` presses Enter |
| `POST /api/sessions/ID/stop` | | Esc in its window: stops what it does |
| `POST /api/sessions/ID/focus` | | Brings its window up on the desktop |
| `POST /api/sessions/new` | `{ "text": "…" }` | A new session in ~/Projects, the text as its first prompt |
| `POST /api/send` | `{ "text": "…", "submit": false }` | Types the text in the window that has the keyboard |

Sending and stopping go through the desktop: its window comes to the front, as with ⌘⌃C (Send to Claude).

## Actions

Five slots. `GET /api/presets` → `[{ "id": "lock", "label": "Lock", "icon": "lock" }, …]`.

| Request | Body | Does |
| --- | --- | --- |
| `POST /api/actions/N/run` | | Runs slot N (0–4) |
| `POST /api/actions/N` | `{ "preset": "lock" }`, or `{ "label", "icon", "command" }`, or `null` | Sets slot N, `null` empties it |

They're kept in `~/.config/nightdrive/companion.json`. A command runs with `bash -c`, detached, as you.

Answers: `200 {"ok": true}`, or `4xx {"error": "…"}` with the reason in plain words.
