# LocalSend

Send files, photos and links between your phone and this computer with the free LocalSend app (iPhone and Android). No cable, no account and no cloud: everything stays on your own network, encrypted.

## From the phone

- The computer shows up in the phone's LocalSend under its name, without the LocalSend desktop app.
- Every send asks for a code: it shows in the middle of this screen, and the phone's LocalSend asks for it. Typing it there is the Accept: nothing is saved without it, so no one who can't see the screen can send to you. The code is new each time; after 3 wrong ones that phone waits a minute.
- Files go to Downloads. A text or a link shows in a notification, with a Copy button.

## To the phone

- Right-click files in Files › Send with LocalSend, or the Launcher: Tools › Send clipboard / Send files with LocalSend.
- Keep LocalSend open on the phone: it asks before it saves anything.
- The first send to a device asks if it's the right one. From then on it goes only to that device: one that takes its name on the network is asked about again, with a warning. Reinstalling LocalSend on the phone makes it a new device.
- To another computer that asks for a code (another Nightdrive, or LocalSend with Require PIN), you type the code it shows.

## In a terminal

| Command | What it does |
| --- | --- |
| `localsend send <file>…` | Sends files or folders to the phone |
| `localsend send-clipboard` | Sends the clipboard's text |
| `localsend devices` | Lists the devices on the network |
| `localsend forget` | Forgets the trusted devices: the next send to each asks again |

Homepage: https://localsend.org
Needs: the LocalSend app on the phone, both on the same network
