# Mail

A quiet mail client: folders, the thread list and the open thread, nothing else on screen. New mail arrives as a notification you can answer from, and Claude can write a reply for you to read before anything is sent. Your mail stays in a folder on your computer (fetched with mbsync, searched with notmuch), so it opens at once and works offline.

## Reading

- Press `?` (or Ctrl+?) in Mail to see its keys. The ⌘ keys follow Mac Mail; on a PC keyboard they are Ctrl (Ctrl+R, Ctrl+N…), as in Thunderbird and Outlook.
- ↑ / ↓ or `j` / `k` move in the list, as in Mac Mail, and `Space` and ⇧Space page through the message. `/` or ⌘F searches (notmuch's query syntax), `Esc` clears the search.
- `1`–`6` or Ctrl+↑ / Ctrl+↓ pick a folder: Inbox, Sent, Drafts, Archive, Spam, Trash. ⌘B hides the folders.
- In a narrow window the folders hide by themselves (⌘B shows them), and narrower still the list and the thread take turns: a click, `Enter` or → opens the thread, `Esc`, ← or the arrow above it goes back to the list. With the list alone, the arrows (and PgUp / PgDn) move in it without opening anything, so nothing is marked read on the way; with the thread alone, they scroll it and `j` / `k` (or ⌥↑ / ⌥↓) go to the next thread.
- With more than one account, each has its own folders: `Tab` / ⇧Tab (or a click on an address under the folders) shows the next one. A notification's message opens in its own account.
- In a thread of three messages or more, the read ones before the last show as one line each (who, the first line, when): a click opens one. The quote at the end of a message hides behind `•••` when all of it is in an earlier message of the thread; when any of it isn't, it shows.
- `h` shows a message as text, as HTML on the dark page, or as HTML on light paper as it was sent; which one comes first is a setting (text by default). Remote images stay off. A link opens in your browser, a mailto: link as a new message; other kinds (file:, smb:, an app's own) don't open from a message.
- `⇧H` (or the button beside it) opens the HTML in your browser, where newsletters laid out in tables look as they were meant to. The page loads nothing from the network: no remote images, fonts or scripts, so the sender can't tell you opened it. Pictures sent with the message show, and links open when you click them. When the message has remote images, a bar at the top says so: Load images opens the page again with them (still without scripts).
- `Enter` or a double click opens the thread in a window of its own (in Drafts, it goes on writing the draft). Opening an unread thread marks it read; `u` marks it unread again (and read again after that). ⇧U (or ✓ beside a folder's unread count) marks the whole folder read, or with a search on, what it found; ⌘Z takes it back.
- The buttons above a message do the same with the mouse: Reply, Reply with Claude, Forward, Archive, Delete and Spam. Held under the pointer, a button shows its key. With several threads selected, the rows in the reading pane are buttons too.
- `a` archives, `d` or Delete (⌫) moves to Trash, `!` marks spam (in Spam: not spam, back to the Inbox), ⌘Z undoes them. The next sync makes the same move on the server, so your phone and webmail see it too.
- ⇧-click, ⇧↑ / ⇧↓ or ⌘A select several threads, Ctrl-click adds one or leaves it out: archive, delete, spam, `u` and a drag then move or mark them all, and ⌘Z takes them all back. `Esc` selects only one again.
- In Trash, `d` (or ⌫) deletes a thread for good, and ⌘⇧⌫ (or Empty Trash under the list) empties it. Both ask first, as there is no ⌘Z for them; the next sync deletes them on the server too.
- A message (or the selected ones) dragged sideways from the list onto Inbox, Archive, Spam or Trash moves there in the same way (⌘Z undoes it too).
- Attachments show under their message: a click opens one, Save puts it in Downloads, and Save all (with two or more) puts them all there.

## Writing

- `c` or ⌘N writes a new message, `r` replies to all, ⇧R to the sender only, `f` forwards (with the attachments).
- A reply or a forward goes from the account the message came to, a new message from the account shown. With more than one account, a click on From changes it.
- Your signature (`signature` in `account.conf`, below) is put under what you write, above the quote.
- Writing opens in a window of its own: Ctrl+Enter sends, ⌘S saves it in Drafts. `Esc` closes it (a message saved before is saved again; with something new written, the second `Esc` throws it away). Closing the window with ⌘W keeps what you wrote in Drafts.
- To and Cc offer the addresses in your mail as you type, the ones you use most first: ↑ / ↓ choose, `Tab` or `Enter` takes one.
- ⌘⇧A or Attach picks files to attach, files dropped on the window are attached too, and × takes one off.
- Mail opens mailto: links when you pick it as the email app (launcher › Settings › Apps › Default apps): then Hyper E opens Mail too.

## Claude writes the reply

- ⌘⇧C on a message has Claude write the reply, in the message's language, signed with your first name (with a signature of your own, Claude leaves the end to it). In the writing window, ⌘⇧C writes out what you started: select your draft (a start, a few points, "say yes, but next week") and Claude's reply takes its place.
- The reply shows first in a card by the mouse, with what Claude read: `Enter` puts it in place, ⌘⇧C writes another version, `Esc` cancels. Nothing is sent before you press Ctrl+Enter.
- What Claude reads is your choice, asked the first time you press ⌘⇧C: the whole thread (the best replies), or only the text you select, so the thread stays on your computer. Settings (⌘,) changes it later.
- It needs Claude Code signed in (`claude`): the reply is written by `claude -p` with no tools, not even your MCP servers or claude.ai connectors, so a message can't steer it into using them.

## Notifications

- New unread mail in the inbox gets a notification with Reply, Reply with Claude and Delete; a click opens the message in Mail. More than three at once come as one notification that counts them.
- They come after each sync even when Mail is closed: notmuch's post-new hook runs `nightmail notify`. A hook of your own is left alone; add `nightmail notify` to it yourself.
- Mail in an inbox comes within seconds: a connection to each account waits for the server to say a message has arrived (IMAP IDLE, `nightmail push`), and then fetches that inbox alone. The other folders, and an account whose server can't do that, sync every 5 minutes. Gmail can tell of new mail up to a minute late.

## Settings

⌘, (or the gear at the foot of the folders, or launcher › Settings › Apps › Mail): whether writing and message windows float (the default) or open in the grid beside Mail, how a message opens (text, HTML on the dark page, or HTML as it was sent), and what Claude reads. They are kept in `~/.config/nightmail/settings.json`. Mail's colours follow the desktop's theme.

## Setting up an account

Mail reads the mail that mbsync has fetched into `~/Mail` and notmuch has indexed, and sends through your provider's SMTP server. These steps set up one account; each command can be run as it is, after putting your own values in place of the examples (you@example.com, mail.example.com, the account name `example`). Claude can do them with you: Mail's first start, before an account, offers Set up with Claude, which opens Claude Code in a terminal to go through them a step at a time and then offers to add more accounts (`nightmail setup` does the same, and so do Welcome to Nightdrive, launcher › System › Set up Nightdrive, and asking Claude to set up Nightdrive Mail by this page). Your password goes only into the login keyring, by a command you run yourself.

1. Mail comes with Nightdrive; on an install without it, `nightdrive plugins install mail` installs it: notmuch, isync (mbsync), libsecret (secret-tool) and zenity, and it says what is still missing. Many providers want an app password for mail apps (Gmail, iCloud, Fastmail): make one in the provider's account settings first.

2. Put the password in the login keyring, so it is never in a file (it asks for the password):

```
secret-tool store --label="Mail: you@example.com" service mail.example.com user you@example.com
```

3. Tell mbsync where the mail is: `~/.config/isyncrc`. The inbox goes in a folder named `INBOX`, and the others keep the server's names:

```
IMAPAccount example
Host mail.example.com
Port 993
TLSType IMAPS
User you@example.com
PassCmd "secret-tool lookup service mail.example.com user you@example.com"

IMAPStore example-remote
Account example

MaildirStore example-local
Path ~/Mail/example/
Inbox ~/Mail/example/INBOX
SubFolders Verbatim

Channel example
Far :example-remote:
Near :example-local:
Patterns *
Create Both
Expunge Both
SyncState *
```

4. Tell notmuch where the index is: `~/.config/notmuch/default/config` (write your name and address):

```
[database]
path=Mail
[user]
name=Your Name
primary_email=you@example.com
[new]
tags=unread;inbox;
ignore=.mbsyncstate;.uidvalidity;.mbsyncstate.journal;.mbsyncstate.new;.mbsyncstate.lock
[search]
exclude_tags=deleted;spam;
[maildir]
synchronize_flags=true
```

5. Fetch the mail and index it. The first time takes a while with a big mailbox:

```
mkdir -p ~/Mail/example
mbsync -a
notmuch new
```

6. Tell Mail how to send: `~/.config/nightmail/account.conf`. `sent` and `drafts` are the folders under `~/Mail` that mbsync made (a copy of each sent message goes there, and the next sync uploads it). `signature` is optional: its further lines are indented, and it goes under what you write. `suggest-model` is optional too: the Claude model that writes replies (sonnet by default). Mail checks the server's certificate when it sends, as mbsync does when it syncs, so nothing goes out to a server whose certificate isn't valid. A server with a self-signed certificate can't be used for sending: mbsync and the inbox watch trust the one in the account's `CertificateFile` in `isyncrc`, sending doesn't.

```
[account example]
name = Your Name
address = you@example.com
smtp = mail.example.com:465
user = you@example.com
password-cmd = secret-tool lookup service mail.example.com user you@example.com
sent = example/Sent
drafts = example/Drafts
signature = Your Name
  Example Ltd · example.com
```

7. Run `nightmail enable` (or the plugin's installer again): Mail joins the apps, the notifications get their hook, new mail in an inbox comes as it arrives, and the rest syncs every 5 minutes. What is in the inbox now isn't announced as new.

8. Check it: `nightmail` opens Mail with your inbox. Send yourself a message, then `nightmail sync`: it shows in the inbox and a notification comes.

Mail finds the folders by these names: `INBOX`, `Sent`, `Drafts`, `Archive`, `Spam` and `Trash` (Archive is made the first time you archive). Runbox and Fastmail use them as they are. Where the server's names differ, map them to Mail's in `isyncrc` with a channel per folder in place of `Patterns *`: Gmail's `[Gmail]/Sent Mail`, `[Gmail]/Drafts`, `[Gmail]/Spam` and `[Gmail]/Trash`, iCloud's `Sent Messages`, `Junk` and `Deleted Messages`, Outlook's `Sent Items`, `Junk Email` and `Deleted Items`. For example:

```
Channel example-sent
Far :example-remote:"[Gmail]/Sent Mail"
Near :example-local:Sent
Create Near
Expunge Both
SyncState *
```

### More accounts

Each account gets its own folder under `~/Mail` and its own section in `account.conf`: repeat steps 2, 3 and 6 with another name in place of `example` (`[account work]`, `~/Mail/work/`, `sent = work/Sent`), then `mbsync -a` and `notmuch new`. Mail finds an account's mail by its folder (the one `sent` is in, or `maildir = …`), shows the first account in the file when it opens, and remembers the one you looked at last. In notmuch's config, `primary_email` is one of your addresses and `other_email` lists the rest (`other_email=work@example.com`), so replies to all leave every one of them out.

A Gmail or Google Workspace account (with an app password, if the Workspace allows them) is `imap.gmail.com` and `smtp.gmail.com:465`, with a channel per folder in place of `Patterns *`: `INBOX`, and `[Gmail]/Sent Mail`, `[Gmail]/Drafts`, `[Gmail]/Spam` and `[Gmail]/Trash` as `Sent`, `Drafts`, `Spam` and `Trash`. The names follow the language of the Gmail account (`[Gmail]/Lähetetyt viestit`, `[Gmail]/Roskakori` …): `mbsync -l CHANNEL` shows them. Archive is `[Gmail]/All Mail`, which holds every message, so a message deleted there is gone for good. Its channel only brings mail down and sends read marks up, and `all-mail = yes` in the account's section of `account.conf` tells Mail to copy messages out of it and never move them. Archiving is then leaving the inbox, as in Gmail:

```
Channel example-archive
Far ":example-remote:[Gmail]/All Mail"
Near :example-local:Archive
Create Near
Sync Pull PushFlags
Expunge Near
SyncState *
```

## In a terminal

| Command | What it does |
| --- | --- |
| `nightmail` | Opens Mail, or brings it forward |
| `nightmail new` | Writes a new message |
| `nightmail setup` | Sets up an email account with Claude, in a terminal |
| `nightmail settings` | Opens Mail's settings |
| `nightmail sync` | Fetches new mail now and shows it |
| `nightmail show ID`, `reply ID`, `claude ID`, `delete ID` | A message by its notmuch id, as the notifications use them |
| `nightmail enable`, `disable` | Mail among the apps, its notifications and the sync, on or off (your mail and settings stay). Run `enable` again after changing `isyncrc`. |
| `nightmail restart`, `quit`, `log` | After a change to Mail, and its QML errors |

Needs: notmuch, isync (mbsync), an IMAP account; Claude Code for Claude's replies
