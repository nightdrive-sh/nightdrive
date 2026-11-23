# Nightdrive Hub: the client

Nightdrive's side of [Nightdrive Hub](https://github.com/nightdrive-sh/nightdrive-hub), a small server that carries
apps' files between one person's computers (Tasks first). Every computer keeps a full copy and reads it; the Hub tells
each what changed and keeps every version. Its rules are the Hub's `docs/protocol.md`.

```sh
nightdrive hub join https://hub.tailnet.ts.net   # remember the Hub, sync once, then every 5 minutes (systemd timer)
nightdrive hub sync                              # now; --json for the status, --allow-deletes (below)
nightdrive hub status [--json]                   # the last sync, and what waits to be sent (Settings › Hub shows it)
nightdrive hub timer on|off
nightdrive hub leave                             # stop syncing; the files stay
```

## What it does with your files

- Nothing is deleted because it is missing somewhere. Only a deletion made on another computer deletes here, and only
  a file not changed here since: a deleted task goes to Tasks' trash (30 days), anything else to
  `~/.local/state/nightdrive/hub/trash/`.
- An edit beats a deletion, on either side: the edited file comes back.
- The same task edited on two computers is merged field by field from the version both last agreed on (Tasks'
  `lib/merge.py`): a field changed on one side takes that side's; changed on both, the newer `LAST-MODIFIED` wins and
  the other value goes at the end of the task's notes; a field cleared on one side and changed on the other keeps the
  change. The client keeps that agreed version itself (`~/.local/state/nightdrive/hub/base/`), as the Hub serves only
  the newest.
- With no agreed version (a first sync, a new Hub) both are kept: the Hub's stays in place and this computer's becomes a
  task of its own, its title followed by the computer's name.
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
| `lib/bases.py` | the content of that agreement, kept for a merge (`…/hub/base/<collection>/`) |
| `lib/client.py` | the Hub's requests |
| `lib/apps.py`, `lib/tasks_rule.py` | each app's folder and its answer to a conflict or a deletion |
| `lib/settings.py` | `~/.config/nightdrive/hub.json` (the Hub joined), the state folder, the lock |
| `lib/testhub.py`, `lib/devices.py` | for the tests: a Hub in memory, devices with homes of their own |

`e2e_test.py` runs the sync scenarios against the real Hub when its checkout is in `~/Projects/nightdrive-hub` (or
`NIGHTDRIVE_HUB_SRC`), as `merge_sync_test.py` does its merges; the other tests need nothing.
