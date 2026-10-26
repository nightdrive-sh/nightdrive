# Security

Nightdrive handles passwords (Mail, the keyring, the lock screen, polkit), SSH, the firewall and more, so a
security problem in it matters. Thank you for reporting one.

## Supported versions

| Version                                         | Supported                           |
| ----------------------------------------------- | ----------------------------------- |
| The latest release (`main`, the stable channel) | Yes                                 |
| `dev` (the dev channel)                         | Yes                                 |
| Older releases                                  | No: update with `nightdrive update` |

Fixes are made in `dev` and reach the stable channel in the next release, sooner if the problem is serious.

## Reporting a vulnerability

Please don't open a public issue or discussion for a vulnerability.

- **On GitHub:** this repository's **Security** tab › **Report a vulnerability**. Only the maintainer sees the report.
- **By email**, if you can't use GitHub: security@nightdrive.sh.

Tell what you found, how to reproduce it and what it lets someone do. The version (`nightdrive version`) helps.

## What happens next

- You get a reply within a week.
- Once the problem is confirmed, it is fixed and released, and you hear when.
- The fix is announced in the release notes, with your name if you'd like.
