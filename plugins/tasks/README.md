# Tasks

Your tasks, kept on your computer: Today, Upcoming and your lists in a window of their own, and a notification when one
comes due, with Done and Later. You add, edit and tick them off in the window; Claude adds and changes them too (Settings ›
Claude › Access › Tasks).

## Using it

| Keys | |
| --- | --- |
| `?` | Tasks' keys |
| `n` | New task (also New, or `tasks new [LIST]`): ⏎ or Ctrl+⏎ adds it, Tab the next field, ← → another list |
| ⏎ or `e` | Edit the picked task (a double click too): Ctrl+⏎ saves |
| Space | Done (a click on its circle too); in Done, open again |
| Delete | To the trash |
| ⌘Z | Undo the last change (also Undo in the message at the top) |
| ↑ ↓ or `j` `k` | Move in the list; the picked task shows its whole note |
| `1`–`9` or Ctrl+↑ Ctrl+↓ | A row of the sidebar |
| `Tab` | Keys between the sidebar and the tasks |
| ⇧N | New list (also + by the sidebar's title) |
| F2 | Rename the list on show (also Rename) |
| Delete in the sidebar | Delete the list (also Delete): its tasks go to the trash with it, and Undo brings it all back |
| `/` or ⌘F | Search every list, by the words in a task's title or note (also `tasks search [WORDS]`): ⏎ or ↓ to the tasks found, Esc ends it |
| ⌘B | Hide or show the sidebar |
| ⌘R | Read the tasks again |

- A new task's due is a day and a time, either may stay empty: `today`, `fri`, `+3d` or a date the way Settings › Region writes it (`5.11.2026`, `11/5/2026`), and `9:30`, `930`, `14` or `3pm` (`3:30 PM`). A click into the day, its calendar glyph or ↓ opens a month to pick from: ← → a day, ↑ ↓ a week, PgUp PgDn a month, ⏎ picks, Esc closes it. The panel says how it reads them as you type. A new task goes in the list you're looking at, else the one you used last. In an edit, another list moves the task there, and only what you changed is written: what another app set (a low priority, its own fields) stays.
- Today has what is due today and what is late (in red); Upcoming every task with a date, under the next 7 days one by one, then Later; Done the last 100 done. The window, the notifications and `tasks list` write when a task is due the way Settings › Region does (`Fri 6.11. 9:30`; `Fri 11/6 9:30 AM` in the US).
- A task due on a day without a time is notified at 9:00 that day. Later moves it on an hour, or a day without a time, and it comes again then. Done ticks it off.
- Ask Claude: "remind me to call the dentist tomorrow at 10", "what's due this week?", "move the bread to Saturday", "make a list for the trip". Every change Claude makes shows a notification with Undo. A code, PIN or password in a task reaches Claude hidden (`[code hidden]`), unless Access › Tasks › *Codes, card numbers and passwords* is on.

## In a terminal

`tasks help` lists the commands: `tasks add "Buy milk" --due today --list Shopping`, `tasks list --view upcoming`, `tasks list --query milk`, `tasks
edit ID --due fri --list Home` (`--no-due` takes the date away), `tasks done ID` (`tasks undone ID` opens it again), `tasks snooze ID --until "tomorrow 9:00"`, `tasks trash ID`, `tasks list-new
Shopping`, `tasks list-rename Shopping Groceries`, `tasks list-remove Groceries` (`--with-tasks` for one that has tasks). A due is `[DAY] [TIME]`: the day `today`, `tomorrow`,
`mon` … `sun` (the next one), `2026-11-05`, `+3d` or a date the way Settings › Region writes it (`5.11.`, `11/5/2027`), the time `9:30`, `930`, `14` or `3pm` (alone: the next such time);
or `+30m`, `+2h`. `tasks when "fri 930"` shows how one reads. `--json` gives what Claude reads.

## Where they are

- Each task is a VTODO file (iCalendar, the standard), a folder per list, in `~/.local/share/nightdrive/tasks`: the layout vdirsyncer keeps a CalDAV calendar in, so syncing them with iCloud or another server can come later without a conversion. What another app wrote in a file (alarms, repeats, its own fields) is kept when Tasks changes it.
- A task moved to the trash stays in `~/.local/state/nightdrive/tasks/trash` for 30 days.
- `tasks disable` stops the notifications and takes Tasks out of the apps; your tasks stay.

Needs: nothing to set up (Python and notify-send, which Nightdrive has)
