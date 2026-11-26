# Network Drives

A Storage Box, an SFTP server or any rclone remote as a folder in your home, the same in every app: Files, the Open dialogs, a terminal. Opened and saved files stay in a cache, so they open offline too, and what you save without a network is uploaded once it is back. Without a network no app hangs on the folder: a file that has to be fetched gives an error instead.

- Each drive is a folder under `~/Storage` (or where you say), mounted at login with rclone. It shows in Files' sidebar with the disks.
- An ssh drive logs in as ssh does, with its Host in `~/.ssh/config` and its key or agent (1Password's too), so no password is stored anywhere. Its `.ssh` folder is hidden, so its keys can't be deleted by accident.
- Any other remote (S3, WebDAV, Jottacloud, Google Drive …) is first made with `rclone config`, which keeps what it needs to log in.
- `--read-only` mounts a drive that nothing can change through, e.g. a photo library.
- The top bar shows an icon only when a drive needs a look: orange while one waits for its host (offline), red when one failed, and a count while files upload. Its menu lists the drives and has Connect again.
- Files connects a drive only when you open it, so with 1Password locked it asks to unlock then, not when Files opens. Nautilus and GTK apps' own Open dialogs start GNOME's disk monitor, which connects every drive at once.
- While a drive isn't mounted, its folder is an empty local folder. Something saved there keeps the drive from mounting, and the menu says so, rather than vanishing under the drive: move it away and Connect again.

## Without a network

Folders opened in the last minute, the files in the cache, free space and saving all work offline. A folder not opened in the last minute, or a new folder, gives an error after a few seconds. Opening a file that isn't in the cache yet gives an error after 25–40 seconds (rclone tries to fetch it several times). Files saved offline are uploaded once the network is back, within a few minutes. A computer started without a network mounts its drives once their hosts answer.

## In a terminal

    netdrive add Files --ssh storage-files                    # ~/Storage/Files, from a Host in ~/.ssh/config
    netdrive add Photos --ssh storage-photos --read-only      # ~/Storage/Photos, read only
    netdrive add Work --remote s3:bucket --path ~/Work        # any rclone remote, a folder of your choice
    netdrive list                                             # the drives and their state (--json)
    netdrive stop Photos                                      # unmount, and not at login (start mounts it again)
    netdrive restart all                                      # connect again now
    netdrive refresh Files                                    # show changes made elsewhere now, not in a minute
    netdrive remove Photos                                    # forget it; the files on the server stay

A Hetzner Storage Box's sub-account as an ssh Host (port 23, then `ssh-copy-id -p 23 -s storage-files` once for the key):

    Host storage-files
        HostName u123456-sub1.your-storagebox.de
        User u123456-sub1
        Port 23

Each drive is a user service, `nightdrive-netdrive@NAME.service`: `journalctl --user -u nightdrive-netdrive@Files` shows its log. The list is in `~/.config/nightdrive/netdrive.json`, the cache in `~/.cache/netdrive` (at most 20 GB a drive, a file kept 7 days after its last use). Drives aren't in `nightdrive backup`: it stays on the computer's own disk.

Homepage: https://rclone.org
Needs: rclone and fuse3 (installed with it), and a server or an rclone remote
