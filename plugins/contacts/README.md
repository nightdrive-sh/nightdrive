# Contacts

Your contacts from iCloud, Google or another CardDAV server, on this computer and kept in sync. They are kept as vCard files in `~/.local/share/contacts`, one folder per account, fetched by vdirsyncer every 30 minutes, so they are there offline too. The Contacts window, editing, and addresses in Mail come later: for now the contacts come down from the server, and a change made to the files here gives way to the server's at the next sync.

## Setting up an account

Contacts reads your accounts from `~/.config/contacts/accounts.conf`, one section each, and signs in with an app password kept in the login keyring. Claude can do these steps with you: the plugin's page has Set up with Claude (`contacts setup` does the same), which opens Claude Code in a terminal and goes through them a step at a time. Your password goes only into the login keyring, by a command you run yourself.

1. Install the plugin (launcher › System › Install › Plugins › Contacts): it installs vdirsyncer, python3-vobject and libsecret (secret-tool).

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

6. Run `contacts enable` (or the plugin's installer again): the sync runs every 30 minutes from then on. It skips its round while the login keyring is locked.

Google's CardDAV with an app password works, but Google's own documentation asks for OAuth. If Google ever stops taking it, vdirsyncer's `google_contacts` with an OAuth client of your own is the way left.

## In a terminal

| Command | What it does |
| --- | --- |
| `contacts setup` | Sets up an account with Claude, in a terminal |
| `contacts sync [NAME…]` | Fetches every account's contacts now (or these accounts') |
| `contacts accounts` | The accounts and how many contacts each has here |
| `contacts enable`, `disable` | The sync every 30 minutes, on or off (your contacts and accounts stay) |
| `contacts vdirsyncer …` | vdirsyncer with Contacts' config, for a closer look |

Needs: vdirsyncer, an iCloud, Google or CardDAV account
