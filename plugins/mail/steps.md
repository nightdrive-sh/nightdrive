# Setting up Mail by hand

Welcome to Nightdrive shows these steps one at a time when you set things up without Claude (plugins/README.md › steps.md).

Help: README.md#setting-up-an-account

## Why Mail

Mail is Nightdrive's own email app: a quiet window with your folders, your messages and the one you're reading.
New mail comes as a notification you can answer right from it, and your mail is kept on this computer, so it opens at
once and works offline.

It takes a few steps, because Mail uses two trusted tools underneath: mbsync fetches your mail, and notmuch finds
anything in it in a moment. You tell each of them about your account once, in a small text file. These steps write the
files for you; you only check them.

## An app password

Gmail and iCloud don't let mail apps use your normal password: they want an *app password*, a separate one just for
Mail. Runbox and many others take your normal password: then skip this step.

**Gmail:** 2-Step Verification has to be on in your Google account. Open App passwords, name it Mail, and copy the 16
letters Google shows, without the spaces.

**iCloud:** at account.apple.com › Sign-In and Security › App-Specific Passwords, add one named Mail. Its servers are
imap.mail.me.com and smtp.mail.me.com:587.

Keep the password at hand: a later step asks for it.

Open: Google's app passwords | https://myaccount.google.com/apppasswords
Open: Apple account | https://account.apple.com

## Your account

Mail needs to know whose mail to fetch, and from where. Your provider's help pages name their servers ("IMAP" and
"SMTP"). A short name tells this account apart from others you may add later.

Ask: email | Your email address | you@example.com
Ask: name | Your name, as people see it | Your Name
Ask: imap | Your provider's IMAP server | imap.gmail.com
Ask: smtp | Its SMTP server and port | smtp.gmail.com:465
Ask: account | A short name for this account | personal

## Put your password in the keyring

Mail never keeps your password in a file. This command asks for it (the app password, if you made one) and keeps it in
your login keyring, which opens when you log in.

```
secret-tool store --label="Mail: {email}" service {imap} user {email}
```

Done when: secret-tool lookup service {imap} user {email}

## Tell mbsync where your mail is

mbsync fetches your mail into a folder on this computer. Its settings are one file: the button writes it with your
account in it and opens it in the text editor. Check it, save it and close the editor.

If the file was already there (another account), it opens as it is: add these lines at its end. Gmail, iCloud and
Outlook name their folders differently from Mail: the help beside this step (h) shows the lines they need.

Edit: ~/.config/isyncrc
Done when: grep -q "^IMAPAccount {account}$" ~/.config/isyncrc

```
IMAPAccount {account}
Host {imap}
Port 993
TLSType IMAPS
User {email}
PassCmd "secret-tool lookup service {imap} user {email}"

IMAPStore {account}-remote
Account {account}

MaildirStore {account}-local
Path ~/Mail/{account}/
Inbox ~/Mail/{account}/INBOX
SubFolders Verbatim

Channel {account}
Far :{account}-remote:
Near :{account}-local:
Patterns *
Create Both
Expunge Both
SyncState *
```

## Tell notmuch who you are

notmuch keeps the index that makes search fast, and knows which messages are yours. The button writes its settings and
opens them; check your name and address, save and close.

Edit: ~/.config/notmuch/default/config
Done when: test -s ~/.config/notmuch/default/config

```
[database]
path=Mail
[user]
name={name}
primary_email={email}
[new]
tags=unread;inbox;
ignore=.mbsyncstate;.uidvalidity;.mbsyncstate.journal;.mbsyncstate.new;.mbsyncstate.lock
[search]
exclude_tags=deleted;spam;
[maildir]
synchronize_flags=true
```

## Fetch your mail

This fetches your mail for the first time and indexes it. With a big mailbox it takes a while: leave the terminal open
until it's done. If it stops with an error, the help beside this step (h) has the details, and the error usually names
what's wrong (a server name, the password).

```
mkdir -p ~/Mail/{account} && mbsync -a && notmuch new
```

Done when: test -d ~/Mail/{account}/INBOX/cur

## Tell Mail how to send

Mail sends through your provider's SMTP server, and keeps a copy of what you send in your Sent folder. The button
writes Mail's own settings and opens them: check the Sent and Drafts folders' names (look in ~/Mail/{account}: Gmail's
are different), save and close. The signature is yours to change.

Edit: ~/.config/nightmail/account.conf
Done when: test -s ~/.config/nightmail/account.conf

```
[account {account}]
name = {name}
address = {email}
smtp = {smtp}
user = {email}
password-cmd = secret-tool lookup service {imap} user {email}
sent = {account}/Sent
drafts = {account}/Drafts
signature = {name}
```

## Turn Mail on

This adds Mail to your apps, gives it its notifications, and keeps your mail coming: new mail in the inbox arrives at
once, the rest every 5 minutes. Then open Mail and send yourself a message to try it.

```
nightmail enable && nightmail restart
```

Run: Open Mail | nightmail
