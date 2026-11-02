# Calendar

Your iCloud calendars, and Google calendars by their private address, on your computer: the month or the week in a window of its own, kept in sync every 15 minutes. A first version: you add events in the window; they are changed and deleted with the `calendar` command, or by Claude when you ask it to.

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
| `n` | New event on the day picked (also New, or a double click in the week's hours) |
| `1`–`9` or Ctrl+↑ Ctrl+↓ | A calendar of the sidebar, or All calendars |
| ⌘R | Sync now |
| ⌘B | Hide or show the sidebar |

- A new event: `Tab` moves between its fields, `Enter` or Ctrl+Enter adds it, `Esc` leaves it. A time is typed as 9:30 or 930, a day as 2026-11-05 or 5.11.2026; the end moves with the start. It goes in a calendar that isn't read only (below), the one you used last.
- In a narrow window the buttons show as icons, and below about 500 px the month or week shows as a list of its days.
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

- In the same file, `read-only = yes` in an account's section makes its sync only download, and `read-only = Family, Work` keeps Calendar from adding to or deleting from those calendars. `shared = Family` (or `yes`, the whole account) marks the calendars others see: Claude asks on Nightdrive's card every time before adding to them, as what it adds goes to those people too. `off = yes` leaves the account's calendars out.

## Claude

With Nightdrive's tools for Claude on (Settings › Claude › Access › Calendar), Claude can read your calendars and events, add an event (you can undo it from the notification), and delete one after you allow it on Nightdrive's card. It doesn't delete recurring events, nor change anything in a read-only calendar.

The first event Claude adds to a calendar asks on the card, and once you allow it, Claude adds to that calendar without asking; a `shared` one asks every time, and a refusal remembers nothing. `nightdrive mcp access allowed` lists the calendars allowed so, and `nightdrive mcp access forget calendar_add` makes them all ask again (or `forget calendar_add "Family (icloud/family)"`, one of them).

## In a terminal

| Command | What it does |
| --- | --- |
| `calendar` | Opens Calendar, or brings it forward |
| `calendar show [DAY]`, `month`, `week` | Opens it on a day (YYYY-MM-DD), the month or the week |
| `calendar new [DAY]` | Opens it with a new event on DAY (or the day it shows) |
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
