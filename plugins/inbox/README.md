# Inbox

The messages Claude's sessions and apps leave for you to look at when you have time, in a window: a "done, have a look"
with screenshots, a summary of what changed, a build to start. Newest first, the unread ones marked, with who left each
one, so you can go back to the session. The messages themselves are Nightdrive's ([Inbox](../../docs/inbox.md)): a
session can leave one whether this window is installed or not.

## Using it

| Keys | |
| --- | --- |
| `?` | Inbox's keys |
| ↑ ↓ or `j` `k` | Move in the list (`Home` `End`: the newest, the oldest) |
| `/` or ⌘F | Search the titles, text and senders. `Enter` or ↓ to the messages, `Esc` back to every one |
| `e` | Archive: out of the way, kept in Archive (there: back to the inbox). ⌘Z in the notice undoes it |
| `u` | Mark read or unread |
| `Delete` | Delete the message and its files for good, after asking |
| `1` … `8` | Press the message's buttons in order |
| `s`, `t` | Go to the session that left it; open its task |
| `i` | Its first picture over the whole window: ← → the others, `Esc` back, `o` in the image viewer |
| `f` | Inbox, Unread, Archive and the senders: ↑ ↓ pick, `Enter` back to the messages |
| `Space` ⇧Space | Scroll the message |
| ⌘B | Hide or show the sidebars |

- A message is marked read once it has been open a moment, so moving past one with the arrows leaves it unread.
- From lists each project Claude's sessions worked in, each app, and Other. A click on a message's sender shows only that session's (or app's) messages; `Esc` shows every one again.
- Pictures show large, two side by side where there is room (a before and an after); a click shows one over the window. Other files are listed under them, and a click opens one in its app.
- A button that runs a command shows the whole command under it. Pressing it only shows a card with the command and the folder it runs in; `Enter` there runs it, in the background, its output in `~/.local/state/nightdrive/inbox-runs/`. Nothing runs by itself.
- A message from neither a Claude session nor an app (a terminal, a script) has its sender in red: nothing says who left it, so look at its buttons first.
- The task button opens the task at the address in `~/.config/nightdrive/inbox.json` (`{"task_url": "https://…/tasks/{n}"}`); without one, it copies the task's number.
- Below 960 px the sidebar hides (`f` or the button by the list's title shows it); below 640 px the list and the message take turns, `Esc` back to the list.

## In a terminal

| Command | What it does |
| --- | --- |
| `inbox` | Open the window |
| `inbox show ID` | The window on that message (an id or its last four characters) |

The messages are `nightdrive inbox`'s: `post`, `list` (`--from`, `--search`), `show`, `read`, `archive`, `delete` and
`press` (docs/inbox.md).

Needs: nothing to set up
