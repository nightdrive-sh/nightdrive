# Tasks

Your tasks, kept on your computer: Today, Scheduled and your lists in a window of their own, and a notification when one
comes due, with Done and Later. Claude adds and changes them (Settings › Claude › Access › Tasks); the window only shows
them for now.

## Using it

| Keys | |
| --- | --- |
| `?` | Tasks' keys |
| ↑ ↓ or `j` `k` | Move in the list; the picked task shows its whole note |
| `1`–`9` or Ctrl+↑ Ctrl+↓ | A row of the sidebar |
| `Tab` | Keys between the sidebar and the tasks |
| ⌘B | Hide or show the sidebar |
| ⌘R | Read the tasks again |

- Today has what is due today and what is late (in red); Scheduled every task with a date, by day; Done the last 100 done.
- A task due on a day without a time is notified at 9:00 that day. Later moves it on an hour, or a day without a time, and it comes again then. Done ticks it off.
- Ask Claude: "remind me to call the dentist tomorrow at 10", "what's due this week?", "move the bread to Saturday". Every change Claude makes shows a notification with Undo. A code, PIN or password in a task reaches Claude hidden (`[code hidden]`), unless Access › Tasks › *Codes, card numbers and passwords* is on.

## In a terminal

`tasks help` lists the commands: `tasks add "Buy milk" --due today --list Shopping`, `tasks list --view today`, `tasks
done ID`, `tasks snooze ID --until "tomorrow 9:00"`, `tasks trash ID`. A due time is `YYYY-MM-DD`, `YYYY-MM-DD HH:MM`,
`HH:MM`, `today`, `tomorrow` (with a time or not), or `+30m`, `+2h`, `+3d`. `--json` gives what Claude reads.

## Where they are

- Each task is a VTODO file (iCalendar, the standard), a folder per list, in `~/.local/share/nightdrive/tasks`: the layout vdirsyncer keeps a CalDAV calendar in, so syncing them with iCloud or another server can come later without a conversion. What another app wrote in a file (alarms, repeats, its own fields) is kept when Tasks changes it.
- A task moved to the trash stays in `~/.local/state/nightdrive/tasks/trash` for 30 days.
- `tasks disable` stops the notifications and takes Tasks out of the apps; your tasks stay.

Needs: nothing to set up (Python and notify-send, which Nightdrive has)
