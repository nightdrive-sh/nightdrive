# Tailscale

A private network between your own devices: reach your home server, NAS or Home Assistant from anywhere, as if you were at home.

![Tailscale's menu in the top bar](tailscale.jpg)

- The icon in the top bar shows whether you're connected. A right click turns Tailscale on or off.
- Its menu lists this computer and your other devices: a click copies a device's address.
- The launcher has it too: Settings › Tailscale.

## Setting up

Log in once after installing: Welcome to Nightdrive (launcher › System › *Set up Nightdrive*) does it with Claude, who explains it as it goes, or without Claude a step at a time. By hand: launcher › Settings › Tailscale › *Log in*, or *Log in* in its top bar menu, opens the login
page in the browser (a right click on the icon does too). The installer makes you Tailscale's operator, so this and the
top bar's on/off need no password. Installed before that (the switch says *Permission denied*)? Run
once:

```
sudo tailscale set --operator=$USER
```

Homepage: https://tailscale.com
Needs: a Tailscale account (free for personal use)
