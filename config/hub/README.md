# Nightdrive Hub: the client

Nightdrive's side of [Nightdrive Hub](https://github.com/nightdrive-sh/nightdrive-hub), a small server that carries
apps' files between one person's computers (Tasks first). Every computer keeps a full copy and reads it; the Hub tells
each what changed and keeps every version. Its rules are the Hub's `docs/protocol.md`.

```sh
nightdrive hub join https://hub.tailnet.ts.net   # remember the Hub, sync once, then every 5 minutes (systemd timer)
nightdrive hub sync                              # now; --json for the status, --allow-deletes (below)
nightdrive hub status [--json]                   # the last sync, and what waits to be sent
nightdrive hub timer on|off
nightdrive hub leave                             # stop syncing; the files stay
```

## What it does with your files

- Nothing is deleted because it is missing somewhere. Only a deletion made on another computer deletes here, and only
  a file not changed here since: a deleted task goes to Tasks' trash (30 days), anything else to
  `~/.local/state/nightdrive/hub/trash/`.
- An edit beats a deletion, on either side: the edited file comes back.
- The same task edited on two computers: both are kept. The Hub's stays in place and this computer's becomes a task of
  its own, its title followed by the computer's name. (Merging field by field comes later.)
- A new Hub (another server id) or a first sync: files with the same content match, differing ones are both kept, and
  nothing is deleted on either side.
- Many files gone at once (over 20 and over half) are held back: `sync --allow-deletes` sends them. A folder gone
  altogether (a disk not mounted) stops its sync until it is back.
- A Hub out of reach isn't an error: the changes wait and go with the next sync.

## The files

| File | What |
| --- | --- |
| `lib/cli.py` | the command, status, timer |
| `lib/sync.py` | one sync of one collection: first from the Hub, then to it |
| `lib/manifest.py` | what this computer and the Hub last agreed on (`~/.local/state/nightdrive/hub/<collection>.json`) |
| `lib/client.py` | the Hub's requests |
| `lib/apps.py`, `lib/tasks_rule.py` | each app's folder and its answer to a conflict or a deletion |
| `lib/settings.py` | `~/.config/nightdrive/hub.json` (the Hub joined), the state folder, the lock |
| `lib/testhub.py`, `lib/devices.py` | for the tests: a Hub in memory, devices with homes of their own |

`e2e_test.py` runs the sync scenarios against the real Hub when its checkout is in `~/Projects/nightdrive-hub` (or
`NIGHTDRIVE_HUB_SRC`); the other tests need nothing.
