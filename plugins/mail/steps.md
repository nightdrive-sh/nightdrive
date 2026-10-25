# Setting up Mail by hand

Welcome to Nightdrive shows these steps one at a time when you set things up without Claude (plugins/README.md › steps.md).

## Why we recommend Mail

Mail is Nightdrive's own email app, with a few unique features like Claude writes (⌘⇧C). Setting up Mail takes a few
steps, because Mail uses two trusted tools: mbsync and notmuch. mbsync fetches your mail and notmuch indexes your emails
for fast viewing and searching.

## An app password

To connect to your email, depending on your email provider, you'll need an account password or an app password. For
example, Gmail and iCloud require an "app password".

If you don't know which one to use, refer to your email provider's documentation.

Get your password (or app password) ready, you'll need it in the next step.

Open: Google's app passwords | https://myaccount.google.com/apppasswords
Open: Apple account | https://account.apple.com

## Your account

Mail needs to know where to fetch email. Check your email provider's documentation.

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

If the file was already there (another account), it opens as it is: add these lines at its end. Gmail and iCloud name
their folders differently from Mail: Mail's README shows the lines they need.

Open: Mail's README | README.md
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
until it's done. If it stops with an error, Mail's README has the details, and the error usually names what's wrong (a
server name, the password).

Open: Mail's README | README.md

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
