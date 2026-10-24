# Setting up Tailscale by hand

Welcome to Nightdrive shows these steps one at a time when you set things up without Claude (plugins/README.md › steps.md).

## Why we recommend Tailscale

Tailscale makes a private network of your own devices: this computer, your phone, your laptop, a home server. They
find each other wherever they are, at home or on the other side of the world, and nobody else can get in.

Tailscale is free for personal use.

## Log in to Tailscale

The button below opens Tailscale in your browser. No account yet? You can create an account on the same page. Follow
the instructions in the browser, then come back here: this step shows done once Tailscale is connected.

Run: Open the login page | ./login
Done when: tailscale status --json | jq -e '.BackendState | IN("Running", "Stopped")'

## If the login says "Permission denied"

Only if the login page didn't open: Tailscale needs to know once that you may control it. This command asks for your
password in a terminal, then the login works. Go back a step and press the button again.

```
sudo tailscale set --operator=$USER
```

## Your phone

Install the Tailscale app on your phone (App Store or Google Play) and sign in with the same account. Your phone and
this computer now see each other.

The icon in the top bar shows whether you're connected. Open the menu and see all your connected devices.

Done when: tailscale status --json | jq -e '[.Peer[]?] | length > 0'
