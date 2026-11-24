# Hub

Nightdrive Hub keeps your apps' data the same on all your computers, through a small server of your own instead of a
paid cloud. Tasks is the first app it syncs; Notes, Recorder and Inbox come later. Every computer keeps a full copy and
works on it, online or not: the Hub only carries the changes between them and keeps every version.

## Joining a Hub

The Hub is a server on one of your machines, reached over Tailscale: [its repository](https://github.com/nightdrive-sh/nightdrive-hub)'s
`install-server.sh` sets one up. Then on each computer:

```sh
nightdrive hub join https://<machine>.<tailnet>.ts.net:8470
```

That syncs once and then every few minutes. **Settings › Hub** shows the Hub, when the last sync went through, what each
app's last sync did, and *Sync now*. In a terminal:

```sh
nightdrive hub sync              # now (--json for the result)
nightdrive hub status [--json]   # the last sync, and what waits to be sent
nightdrive hub timer on|off      # the sync every few minutes
nightdrive hub leave             # stop syncing; every file stays on this computer
```

A Hub out of reach (a laptop away from home) isn't an error: the changes wait on the computer and go with the next sync.

## The same task edited on two computers

When both computers changed a task before they synced, the two are merged field by field: a new title on one and a
new due date on the other both stay. When both changed the same field (the title on both), the newer change wins, and
the other value is written at the end of the task's notes (*Edited on two computers. Not kept from the older edit …*),
so nothing is lost. A field cleared on one computer and changed on the other keeps the change.

When there is no earlier version both agreed on (the first sync of a computer that already had tasks), both are kept
instead: the Hub's in the task's place, and this computer's as a task of its own beside it, its title followed by the
computer's name. Delete the one you don't want.

## Deletions

- A task deleted on another computer goes to Tasks' trash here (30 days).
- An edit beats a deletion: a task edited on one computer and deleted on the other comes back.
- Nothing is deleted because it is missing somewhere. Many tasks gone at once (over 20, and over half) are held back:
  `nightdrive hub sync --allow-deletes` sends them. A tasks folder gone altogether (a disk not mounted) stops its sync
  until it is back.

## When the Hub is lost

Every computer has all the files, so losing the Hub loses no tasks. Set up a new one (`install-server.sh`, the same
address or another) and join it on each computer (`nightdrive hub join URL`; at the same address the next sync notices
by itself). The first computer fills the new Hub, and the others add what only they have. Nothing is deleted on any
of them, even a task deleted while the Hub was gone (it comes back: delete it again). Each computer remembers what its
files were before, so a task changed on only one computer takes that change everywhere; only one changed on two is
merged or kept twice, as above.

## Backup and restore

The Hub keeps every version of every file. Each night it lets go of versions replaced over 90 days ago, copies its
data to `~/nightdrive-hub-backup` on the same machine, and checks the data (`install-server.sh` sets this up; a run
that finds a problem shows in `systemctl --user --failed` there). That copy is a guard against mistakes, not against
losing the machine: [`nightdrive backup`](backup.md) on the Hub's machine takes it elsewhere every day. The commands, on
the Hub's machine:

```sh
cd ~/.local/share/nightdrive-hub
python3 -m hub doctor --data ~/nightdrive-hub [--fix] [--json]    # is the data whole?
python3 -m hub backup --data ~/nightdrive-hub DEST [--json]        # a copy, brought up to date
python3 -m hub restore DEST --data NEWDIR [--json]                 # a Hub again from a copy
python3 -m hub prune --data ~/nightdrive-hub [--days 90] [--dry-run] [--json]
```

You need a backup only when the computers lost their files too, or for an old version. A restored Hub gets a new id,
so each computer syncs with it as with a new Hub: nothing is deleted, and an edit made after the copy isn't rolled
back to the copy's older version. Restore into a new folder, then stop the Hub (`systemctl --user stop
nightdrive-hub`), put the folder in place of `~/nightdrive-hub`, and start it again.

`doctor --fix` (with the Hub stopped: `systemctl --user stop nightdrive-hub`) puts right what it can and moves any
file edited by hand under `~/nightdrive-hub/.doctor/`. Damaged content it can't put right; the computers have it, and
restoring a copy or a new Hub has them send it again.

## Limits

- Only your own Tailscale user gets in. The traffic is encrypted; the files on the Hub's disk are not.
- How the client works and what it keeps where: [config/hub/README.md](../config/hub/README.md).
