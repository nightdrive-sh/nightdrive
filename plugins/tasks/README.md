# Tasks

Your tasks, kept on your computer: Today, Scheduled and your lists in a window of their own, and a notification when one
comes due, with Done and Later. You add and edit them in the window; Claude adds and changes them too (Settings › Claude ›
Access › Tasks). Ticking off and lists in the window come next.

## Using it

| Keys | |
| --- | --- |
| `?` | Tasks' keys |
| `n` | New task (also New, or `tasks new [LIST]`): ⏎ or Ctrl+⏎ adds it, Tab the next field, ← → another list |
| ⏎ or `e` | Edit the picked task (a double click too): Ctrl+⏎ saves |
| ↑ ↓ or `j` `k` | Move in the list; the picked task shows its whole note |
| `1`–`9` or Ctrl+↑ Ctrl+↓ | A row of the sidebar |
| `Tab` | Keys between the sidebar and the tasks |
| ⌘B | Hide or show the sidebar |
| ⌘R | Read the tasks again |

- A new task's due is a day and a time, either may stay empty: `today`, `fri`, `5.11.`, `+3d` and `9:30`, `930` or `14`. The panel says how it reads them as you type. A new task goes in the list you're looking at, else the one you used last. In an edit, another list moves the task there, and only what you changed is written: what another app set (a low priority, its own fields) stays.
- Today has what is due today and what is late (in red); Scheduled every task with a date, by day; Done the last 100 done.
- A task due on a day without a time is notified at 9:00 that day. Later moves it on an hour, or a day without a time, and it comes again then. Done ticks it off.
- Ask Claude: "remind me to call the dentist tomorrow at 10", "what's due this week?", "move the bread to Saturday". Every change Claude makes shows a notification with Undo. A code, PIN or password in a task reaches Claude hidden (`[code hidden]`), unless Access › Tasks › *Codes, card numbers and passwords* is on.

## In a terminal

`tasks help` lists the commands: `tasks add "Buy milk" --due today --list Shopping`, `tasks list --view today`, `tasks
edit ID --due fri --list Home` (`--no-due` takes the date away), `tasks done ID`, `tasks snooze ID --until "tomorrow 9:00"`, `tasks trash ID`. A due is `[DAY] [TIME]`: the day `today`, `tomorrow`,
`mon` … `sun` (the next one), `5.11.`, `2026-11-05` or `+3d`, the time `9:30`, `930` or `14` (alone: the next such time);
or `+30m`, `+2h`. `tasks when "fri 930"` shows how one reads. `--json` gives what Claude reads.

## Where they are

- Each task is a VTODO file (iCalendar, the standard), a folder per list, in `~/.local/share/nightdrive/tasks`: the layout vdirsyncer keeps a CalDAV calendar in, so syncing them with iCloud or another server can come later without a conversion. What another app wrote in a file (alarms, repeats, its own fields) is kept when Tasks changes it.
- A task moved to the trash stays in `~/.local/state/nightdrive/tasks/trash` for 30 days.
- `tasks disable` stops the notifications and takes Tasks out of the apps; your tasks stay.

Needs: nothing to set up (Python and notify-send, which Nightdrive has)
