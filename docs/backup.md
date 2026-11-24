# Backup

`nightdrive backup` backs this computer up once a day with [restic](https://restic.net) to a place of your own: a
server over SSH, an S3 or B2 bucket, or a folder on another disk. restic encrypts everything on this computer before it
leaves, keeps the history as snapshots and sends only what changed.

Sync is not a backup: Hub, iCloud or Jottacloud carry a deletion or a broken file to every device. A backup keeps the
version from before, somewhere else.

## Setting it up

Install restic (`sudo dnf install restic`), then give it a repository:

```sh
nightdrive backup setup sftp:backup-box:/laptop     # an SSH host from ~/.ssh/config, a folder of its own per computer
nightdrive backup run                               # the first backup now (long); the rest go by themselves
```

Setup makes the repository, puts a new password in the keyring and prints it once: **save it in your password
manager**, as nothing in the backup can be read without it. It turns on the daily backup, too.

- **A repository made before** (a new computer, a reinstall): `setup REPO --existing` asks for its password.
- **The password from your password manager** instead of the keyring: `--password-cmd "op read op://Private/Backup/password"`.
- **Other folders than your home**: `--path /srv/data` (again for more), or `path =` lines in the settings.

A [Hetzner Storage Box](https://www.hetzner.com/storage/storage-box/) suits it: turn SSH on, make a sub-account for
backups only (so nothing that mounts your files can delete them), add your key with `ssh-copy-id -p 23 -s
USER@HOST` and a host for it in `~/.ssh/config` (`Port 23`).

## What it does

- **Once a day.** The timer looks every hour and backs up when the last good backup is 20 hours old, so a laptop asleep
  at night or away from home is backed up at its next chance.
- **Out of reach isn't an error** (a laptop on a train, a disk not plugged in) until no backup has gone through in 3
  days: then you get a notification.
- **What it leaves out** is in `~/.config/nightdrive/backup-excludes.txt` (caches, the trash, Flatpak and Steam,
  Garage's VMs; yours to edit), and other disks and network mounts always.
- **What it keeps**: 7 daily, 8 weekly, 24 monthly and 10 yearly snapshots, pruned weekly (`keep-daily =` … in the
  settings). Monthly, 5 % of the data is read back to check it.
- **The Hub's machine** backs up `~/nightdrive-hub-backup`, the Hub's own nightly copy, rather than its live data
  ([Hub](hub.md) › Backup and restore).

## Commands

```sh
nightdrive backup status [--json]           # the last backup, and the last try's state
nightdrive backup run                       # now (--json for the result)
nightdrive backup snapshots [--json]        # the backups kept
nightdrive backup restore TARGET            # the latest backup into an empty folder (SNAPSHOT TARGET for another)
nightdrive backup restore TARGET --include ~/Documents/Taxes
nightdrive backup check [--read-data 100%]  # read back and verify the data
nightdrive backup timer on|off
nightdrive backup restic mount ~/mnt        # restic itself on this repository: browse every snapshot as folders
```

A restore puts the files under their full path in the target (`TARGET/home/you/Documents/…`): move what you need from
there. The settings are `~/.config/nightdrive/backup.conf`, and they stay with this computer.
