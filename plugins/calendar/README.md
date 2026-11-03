# Calendar

Your iCloud calendars, and Google calendars by their private address, on your computer: the month, the week or the day in a window of its own, kept in sync every 15 minutes. A first version: you add, change and delete events in the window, with the `calendar` command, or by Claude when you ask it to.

## Using it

| Keys | |
| --- | --- |
| `?` | Calendar's keys |
| ← → or `h` `l` | Previous, next day |
| ↑ ↓ or `k` `j` | A week back, on |
| PgUp PgDn or `[` `]` | Previous, next month, week or day |
| `t` | Today |
| `m`, `w`, `d` | Month, week, day |
| `Enter` | Open the day's first event (a click opens any) |
| `n` | New event on the day picked (also New, or a double click on a day or in the week's hours) |
| `e` | Edit the event open (also Edit on it) |
| `Del` or `⌫` | Delete the event open, after you say yes (also Delete on it) |
| `1`–`9` or Ctrl+↑ Ctrl+↓ | A calendar of the sidebar, or All calendars |
| ⌘R | Sync now |
| ⌘B | Hide or show the sidebar |

- A new or edited event: `Tab` moves between its fields, `Enter` or Ctrl+Enter saves it, `Esc` leaves it. Days and times are shown and typed the way Launcher › Settings › Region writes them (5.11.2026 and 9:30, or 11/5/2026 and 9:30 AM); 2026-11-05 and 930 are read too, and a day without its year (5.11.) is this year's. A click into a day's field, or `↓` there, opens the month to pick from: the arrows move a day or a week, `PgUp`/`PgDn` a month, `Enter` picks, `Esc` closes it. The end moves with the start. Weeks start on the region's day (Sunday in the US). It goes in a calendar that isn't read only (below), the one you used last.
- The day view (`d`) is the week's hours for one day, wide enough for each event's time and place beside its title.
- In a narrow window the buttons show as icons, and below about 500 px the month or week shows as a list of its days; the day keeps its hours.
- Editing keeps what Calendar doesn't show (alarms, invitees); another calendar moves the event there. A recurring event, or one in a read-only calendar, isn't changed or deleted here: the card says so. A deleted event goes from the server too, and the window has no undo for it.
- A recurring event shows at each of its times.
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

With Nightdrive's tools for Claude on (Settings › Claude › Access › Calendar), Claude can read your calendars and events, add or change an event (you can undo either from the notification), and delete one after you allow it on Nightdrive's card. It doesn't change or delete recurring events, nor anything in a read-only calendar. Changing an event asks on the card the first time in each calendar, and every time in or out of a `shared` one.

The first event Claude adds to a calendar asks on the card, and once you allow it, Claude adds to that calendar without asking; a `shared` one asks every time, and a refusal remembers nothing. `nightdrive mcp access allowed` lists the calendars allowed so, and `nightdrive mcp access forget calendar_add` makes them all ask again (or `forget calendar_add "Family (icloud/family)"`, one of them).

## In a terminal

| Command | What it does |
| --- | --- |
| `calendar` | Opens Calendar, or brings it forward |
| `calendar show [DAY]`, `month`, `week`, `day` | Opens it on a day (YYYY-MM-DD), the month, the week or the day |
| `calendar new [DAY]` | Opens it with a new event on DAY (or the day it shows) |
| `calendar calendars` | The calendars and how many events each has (`--json`) |
| `calendar events FROM TO` | The events from FROM up to TO, not included (YYYY-MM-DD; `--json`, `--calendar ID`, `--search TEXT`, `--limit N`) |
| `calendar add --title T --start S [--end E]` | A new event (`--calendar ID`, `--location L`, `--notes N`); S and E are YYYY-MM-DDTHH:MM, or YYYY-MM-DD for all day |
| `calendar edit CALENDAR UID` | Changes an event: a JSON object on stdin of what changes (`title`, `start`, `end`, `location`, `notes`, `move_to` another calendar); prints the id `calendar restore UNDO` takes to put it back (`--json`) |
| `calendar delete CALENDAR UID` | Deletes an event here and on the server (not a recurring one) |
| `calendar subscribe NAME [TITLE]` | A Google (or other) calendar by its private ICS address |
| `calendar sync [NAME…]` | Syncs every account's calendars now (or these) |
| `calendar enable`, `disable` | Calendar among the apps and the sync every 15 minutes, on or off (your events stay) |
| `calendar restart`, `quit`, `log` | After a change to Calendar, and its QML errors |
| `calendar vdirsyncer …`, `khal …` | vdirsyncer and khal with Calendar's config, for a closer look |

Needs: vdirsyncer, khal, an iCloud account in Contacts or a calendar's ICS address
