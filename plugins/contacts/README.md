# Contacts

Your contacts from iCloud, Google or another CardDAV server, on this computer and kept in sync. Contacts is one of Nightdrive's own apps, on every install like Mail and Deck (Settings › Apps › Nightdrive apps turns it off or on): a quiet window with the accounts, the list and the open card. They are kept as vCard files in `~/.local/share/contacts`, one folder per account, synced by vdirsyncer both ways every 30 minutes, so they open at once and are there offline too. iCloud keeps a contact's photo apart from the card, behind your sign-in: the sync fetches the new ones into `~/.cache/contacts/photos`, cut to the part chosen on the iPhone, and until then the initials show. A contact you add, edit or delete here goes to the server at once, and on to your phone. Mail completes addresses from them, and the launcher finds them (Mail and the launcher, below).

## Using it

- `contacts` (or the launcher: Contacts) opens the window. Press `?` (or Ctrl+?) in it to see its keys.
- All contacts shows each person once: the cards of one person in iCloud and Google (the same name, and a number or address in common) are one, with every line of them. Under it each account has its own, as it is there, and the groups (Apple's, or a card's categories) theirs.
- `↑` / `↓` or `j` / `k` move in the list, `Space` and ⇧Space scroll the card. `/` or ⌘F searches names, companies, email addresses and numbers (040 123 finds +358 40 123 too), `Esc` clears the search.
- Ctrl+↑ / Ctrl+↓ or `1`–`9` pick a row of the sidebar, ⌘B hides it, ⌘R reads the contacts again.
- A click on an email address writes to it (in the email app: launcher › Settings › Apps › Default apps), on a link opens it, and on a number or an address copies it. `w` (or Write above the card) writes to the first address.
- ⌘, opens the settings: your accounts and how many contacts each has, when they last synced, Sync now (`S`) and Add an account with Claude (`A`). launcher › Settings › Apps › Contacts opens them too.
- ⌘N (or the button by the search) adds a contact, ⌘E or `e` (or Edit) edits the open one, and `Delete` deletes it, after asking. More under Editing.
- Pictures show when the card has one inside it, or one on the web (Google's). iCloud's are fetched by the sync (above); until then, and for a contact without one, the initials show.

## Mail and the launcher

- In Nightdrive Mail, To and Cc complete from your contacts as well as from your mail: your contacts first, by their names here. Beside a sender's address, a button opens their card here, or adds them: Add to contacts opens the editor with their name and address in it.
- The launcher's search (⌘Space) finds people by name, company, email address or number (`0401234` finds +358 40 123 4567 too). Enter on one shows their card in the launcher: Open in Contacts, then their numbers and addresses, which Enter copies, and their email addresses, which Enter writes to (⇧Enter copies). Settings › Launcher › Include contacts leaves them out of the search.

## Editing

The editor takes the card's place: the name, company and job title, then the numbers, email addresses, addresses and links, each with its label (mobile, home, work… or one of your own: Custom…), and the birthday (3.5.1980, or 3.5. without the year) and a note. Tab goes from field to field, ⌘S (or ⌘⏎) saves, and Esc leaves, asking first if something changed. A new contact goes in the account the sidebar is on (in All contacts, the first one), and with more than one account the editor's top line lets you pick another. A person whose cards in several accounts show as one is edited a card at a time: the top line says which; Delete deletes them all.

Saving writes only what you changed: whatever else the card holds (an iPhone's related names and social profiles, Google's own fields, the photo) stays as it was. The change goes to the account's server at once (`contacts sync ACCOUNT`), and the line under the list says when it's there; offline, it goes at the next sync.

If the same contact was changed on the phone too before the change here reached the server, the two are merged a field at a time: what only one side changed is that side's; a number, address or link added on either side stays and one removed on either goes; and a field both changed (the name, the note) keeps this computer's. Contacts keeps the card as it was before your edit in `~/.local/state/contacts/base` until the next sync has sent it, to tell the two sides' changes apart.

## Setting up an account

Contacts reads your accounts from `~/.config/contacts/accounts.conf`, one section each, and signs in with an app password kept in the login keyring. Claude can do these steps with you: Contacts' first start offers it, and so do Welcome to Nightdrive (launcher › System › Set up Nightdrive) and `contacts setup`, which open Claude Code in a terminal and go through them a step at a time. Your password goes only into the login keyring, by a command you run yourself. Without Claude, Welcome shows the steps one at a time.

1. Contacts comes with Nightdrive. If you removed it, install it again (launcher › System › Install › Recommended › Contacts, or `nightdrive plugins install contacts`): it installs vdirsyncer, python3-vobject, libsecret (secret-tool) and ImageMagick (for iCloud's photos).

2. Make an app password for Contacts in your account's settings, as mail apps need:
   - iCloud: [account.apple.com](https://account.apple.com) › Sign-In and Security › App-Specific Passwords.
   - Google: [myaccount.google.com/apppasswords](https://myaccount.google.com/apppasswords) (it needs 2-Step Verification; a Google Workspace account needs its admin to allow app passwords).

3. Put the password in the login keyring, so it is never in a file (it asks for the password):

```
secret-tool store --label="Contacts: you@icloud.com" service contacts.icloud.com user you@icloud.com
```

   For Google, `service carddav.googleapis.com`. If Nightdrive Mail already reads the same account with an app password, that one does for contacts too: skip this step and use Mail's `password-cmd` (from `~/.config/nightmail/account.conf`) in the next.

4. Tell Contacts about the account: `~/.config/contacts/accounts.conf`. The name in the section (`icloud` here) is the account's folder under `~/.local/share/contacts`: a-z, 0-9, `-` and `_`.

```
[account icloud]
type = icloud
address = you@icloud.com
password-cmd = secret-tool lookup service contacts.icloud.com user you@icloud.com

[account work]
type = google
address = you@example.com
password-cmd = secret-tool lookup service carddav.googleapis.com user you@example.com
```

   Another CardDAV server (Fastmail, Nextcloud, Runbox…) is `type = carddav` with its address as `url = https://…`; `address` is then the user name you sign in with.

5. Fetch the contacts and see how many came: `contacts sync`, then `contacts accounts`.

6. Run `contacts enable` (or the plugin's installer again): Contacts joins the apps, and the sync runs every 30 minutes from then on. It skips its round while the login keyring is locked.

Google's CardDAV with an app password works, but Google's own documentation asks for OAuth. If Google ever stops taking it, vdirsyncer's `google_contacts` with an OAuth client of your own is the way left.

## In a terminal

| Command | What it does |
| --- | --- |
| `contacts` | Opens Contacts, or brings it forward |
| `contacts search TEXT` | Opens Contacts on what a search finds |
| `contacts show WHO` | Opens the card of WHO: an email address, a number, or a card's id |
| `contacts new [NAME] [EMAIL]` | A new contact in the editor, with these filled in |
| `contacts settings` | Opens the settings: the accounts, Sync now, Add an account |
| `contacts people` | Everyone as JSON (names, numbers, email and street addresses), as Mail and the launcher read them |
| `contacts setup` | Sets up an account with Claude, in a terminal |
| `contacts sync [NAME…]` | Syncs every account's contacts both ways now (or these accounts'), then fetches iCloud's new photos |
| `contacts accounts` | The accounts and how many contacts each has here |
| `contacts enable`, `disable` | Contacts among the apps and the sync every 30 minutes, on or off (your contacts and accounts stay) |
| `contacts restart`, `quit`, `log` | After a change to Contacts, and its QML errors |
| `contacts vdirsyncer …` | vdirsyncer with Contacts' config, for a closer look |

Needs: vdirsyncer, ImageMagick, an iCloud, Google or CardDAV account
