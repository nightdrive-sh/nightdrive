# Calendar

Your iCloud calendars, and Google calendars by their private address, on your computer: the month or the week in a window of its own, kept in sync every 15 minutes. A first version: the window only shows the events. They are added and deleted with the `calendar` command, or by Claude when you ask it to.

## Using it

| Keys | |
| --- | --- |
| `?` | Calendar's keys |
| ← → or `h` `l` | Previous, next day |
| ↑ ↓ or `k` `j` | A week back, on |
| PgUp PgDn or `[` `]` | Previous, next month or week |
| `t` | Today |
| `m`, `w` | Month, week |
| `Enter` | Open the day's first event (a click opens any) |
| `1`–`9` or Ctrl+↑ Ctrl+↓ | A calendar of the sidebar, or All calendars |
| ⌘R | Sync now |
| ⌘B | Hide or show the sidebar |

- A double click on a day in the month opens its week. A recurring event shows at each of its times.
- The events are kept as `.ics` files in `~/.local/share/calendar`, a folder per account and calendar, and vdirsyncer syncs them. khal reads them, recurring events and all.

## Your calendars

- **iCloud**: Calendar uses the account you set up in Contacts (its README › Setting up an account): the same app password in the login keyring, nothing more to do. Your Reminders lists aren't shown (Tasks is for those).
- **Google**: Google's calendars come by their private address, read only (Google wants OAuth for anything more). In Google Calendar on the web: the calendar's Settings › Integrate calendar › Secret address in iCal format. Then `calendar subscribe NAME`, which asks for the address without showing it and keeps it in the login keyring, never in a file: anyone with the address can read the calendar. Its colour: `color = #4F8FE6` in its section of `~/.config/calendar/calendars.conf`.
- **Another CalDAV server** (Fastmail, Nextcloud…): give its CalDAV address in Calendar's own `~/.config/calendar/calendars.conf`, for a Contacts account of `type = carddav`:

```
[account work]
caldav-url = https://caldav.example.com/
```

- In the same file, `read-only = yes` in an account's section makes its sync only download, and `read-only = Family, Work` keeps Calendar from adding to or deleting from those calendars. `off = yes` leaves the account's calendars out.

## Claude

With Nightdrive's tools for Claude on (Settings › Claude › Access › Calendar), Claude can read your calendars and events, add an event (you can undo it from the notification), and delete one after you allow it on Nightdrive's card. It doesn't delete recurring events, nor change anything in a read-only calendar.

## In a terminal

| Command | What it does |
| --- | --- |
| `calendar` | Opens Calendar, or brings it forward |
| `calendar show [DAY]`, `month`, `week` | Opens it on a day (YYYY-MM-DD), the month or the week |
| `calendar calendars` | The calendars and how many events each has (`--json`) |
| `calendar events FROM TO` | The events from FROM up to TO, not included (YYYY-MM-DD; `--json`, `--calendar ID`, `--search TEXT`, `--limit N`) |
| `calendar add --title T --start S [--end E]` | A new event (`--calendar ID`, `--location L`, `--notes N`); S and E are YYYY-MM-DDTHH:MM, or YYYY-MM-DD for all day |
| `calendar delete CALENDAR UID` | Deletes an event here and on the server (not a recurring one) |
| `calendar subscribe NAME [TITLE]` | A Google (or other) calendar by its private ICS address |
| `calendar sync [NAME…]` | Syncs every account's calendars now (or these) |
| `calendar enable`, `disable` | Calendar among the apps and the sync every 15 minutes, on or off (your events stay) |
| `calendar restart`, `quit`, `log` | After a change to Calendar, and its QML errors |
| `calendar vdirsyncer …`, `khal …` | vdirsyncer and khal with Calendar's config, for a closer look |

Needs: vdirsyncer, khal, an iCloud account in Contacts or a calendar's ICS address
