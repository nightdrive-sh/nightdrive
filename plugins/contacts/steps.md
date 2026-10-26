# Setting up Contacts by hand

Welcome to Nightdrive shows these steps one at a time when you set things up without Claude (plugins/README.md › steps.md).

## Why we recommend Contacts

Contacts is Nightdrive's own address book. It keeps your iCloud or Google contacts on this computer and in sync both
ways, so they open at once and are there offline too. Mail completes addresses from them, and the launcher finds people
by name or number.

It signs in to your account with an app password, as mail apps do. The next steps make one and tell Contacts about
your account. You can add another account later the same way.

## An app password

Make an app password for Contacts in your account's settings:

- iCloud: Sign-In and Security › App-Specific Passwords.
- Google: App passwords. It needs 2-Step Verification, and a Google Workspace account needs its admin to allow app
  passwords.

Keep it at hand: you'll need it in a moment. If Nightdrive Mail already reads the same account with an app password,
you can use the same password here.

Open: Apple account | https://account.apple.com
Open: Google's app passwords | https://myaccount.google.com/apppasswords

## Your account

Ask: type | Where your contacts are: icloud or google | icloud
Ask: email | Your account's email address | you@icloud.com
Ask: account | A short name for this account (a-z, 0-9) | icloud

Another CardDAV server (Fastmail, Nextcloud…) works too: Contacts' README shows its lines.

Open: Contacts' README | README.md

## Put your password in the keyring

Contacts never keeps your password in a file. This command asks for it (the app password) and keeps it in your login
keyring, which opens when you log in.

```
secret-tool store --label="Contacts: {email}" service contacts user {email}
```

Done when: secret-tool lookup service contacts user {email} >/dev/null

## Tell Contacts about the account

The button writes Contacts' accounts file with your account in it and opens it in the text editor. Check it, save it
and close the editor.

If the file was already there (another account), it opens as it is: add these lines at its end.

Edit: ~/.config/contacts/accounts.conf
Done when: grep -q "^\[account {account}\]" ~/.config/contacts/accounts.conf

```
[account {account}]
type = {type}
address = {email}
password-cmd = secret-tool lookup service contacts user {email}
```

## Fetch your contacts

This fetches your contacts for the first time and tells how many came. If it stops with an error, it usually names
what's wrong: the address, or the password.

```
contacts sync && contacts accounts
```

Done when: test -n "$(ls -A ~/.local/share/contacts/{account} 2>/dev/null)"

## Open Contacts

That's it: Contacts syncs every 30 minutes from now on, and at once when you add or change a contact. ⌘, in Contacts
shows your accounts, and adds another one.

Run: Open Contacts | bin/contacts
