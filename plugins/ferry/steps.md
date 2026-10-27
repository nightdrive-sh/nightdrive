# Setting up Ferry by hand

Welcome to Nightdrive shows these steps one at a time when you set things up without Claude (plugins/README.md › steps.md).

## Why Ferry

Ferry is a mailbox between this computer and your phone: leave photos, files, text or a link at one end, and pick them
up at the other. It goes over Tailscale, so it works from anywhere, and the phone needs no app: Ferry's page, added to
the Home Screen, is enough.

## Tailscale first

Ferry reaches your phone through Tailscale. Set up Tailscale first (it's the row above this one in Welcome), and sign
in to the Tailscale app on your phone with the same account.

Done when: tailscale status --json | jq -e '.BackendState == "Running"'

## HTTPS certificates

The phone opens Ferry's page over HTTPS, so your tailnet needs its HTTPS certificates. Open Tailscale's DNS page, turn
on HTTPS Certificates at the bottom, then put Ferry on your tailnet. Only your own devices can open it.

Open: Tailscale's DNS settings | https://login.tailscale.com/admin/dns
Run: Put Ferry on your tailnet | ~/.local/bin/ferry enable
Done when: ~/.local/bin/ferry list --json | jq -e '.setup == null'

## If it says Tailscale needs permission

Only if the step before didn't turn Done: Tailscale needs to know once that you may publish Ferry. This command asks
for your password in a terminal. Then go back a step and press the button again.

```
sudo tailscale set --operator=$USER
```

## Your phone

Open Ferry and pick Add Device. Scan the QR code with the phone's camera and open the page. Add it to the Home Screen
(on an iPhone: Share › Add to Home Screen), open Ferry from there and tap Turn on notifications.

From now on, the inbox icon in the top bar has what your phone sends, and files dropped on it go to the phone.

Run: Open Ferry | ~/.local/bin/ferry app
Done when: ~/.local/bin/ferry list --json | jq -e '.push > 0'
