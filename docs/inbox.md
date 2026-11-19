# Inbox

Inbox keeps messages for you to look at when you have time: Claude's "done, have a look" with screenshots, a summary of
what changed, a checklist to try, a build to start. A notification says something needs you now and is soon gone; a
message in Inbox makes no sound and pops nothing up, and waits until you read or archive it. Something with a date
belongs in Tasks instead.

Any Claude Code session can leave one, in any project and on any of your Claude accounts, with Nightdrive's tools on
(`inbox_post`; Settings › Claude › Access › Inbox). You don't have to ask: tell a session "leave the results in my
Inbox", or let a long piece of work end there. The session is named as the sender by itself, with its folder, its
account and the Dashboard task number in its name, so you can go back to it. Apps and scripts can leave messages too.

A message has a title, text, files (pictures, a diff, a log) copied in so they stay as they were, and buttons: open a
file or folder, open a web address, run a command, go to a session, open a task. A button that runs a command shows
the whole command and the folder it runs in, and runs only after you confirm it; nothing in Inbox runs by itself. A
session can add to a message it left (the build is ready, here's its button); it then comes back as unread.

## The command

```
nightdrive inbox post TITLE [--body TEXT|-] [--attach FILE]… [--action KIND LABEL VALUE]… [--task N] [--app NAME]
nightdrive inbox list [--unread|--archived|--all] [--mine]      show ID      count
nightdrive inbox read ID…|--all [--unread]      archive ID… [--undo]      update ID …      delete ID
```

Each takes `--json`. An id may be shortened to its last four characters. A button is `--action open|url|run|session|task
LABEL VALUE`, e.g. `--action run "Start the game" "godot --path ."` (run from `--dir`, default the current folder).
An app names itself with `--app NAME`; a message from neither a Claude session nor an app is marked as such.

Files can come from your home folder or `/tmp`, up to 10 per message and 25 MB each, and never hidden ones (`~/.ssh`,
`.env`). The messages are in `~/.local/share/nightdrive/inbox`, one folder each, the archived ones in its `archive/`.
