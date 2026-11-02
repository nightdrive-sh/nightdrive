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

How soon a fix is released, counted from the confirmation:

| Severity                                                                                       | Fix released          |
| ---------------------------------------------------------------------------------------------- | --------------------- |
| Critical: someone else runs code or reads secrets on your machine, or gains root, with no step of yours | Within 7 days, in a release of its own |
| High: the same, but it needs a step of yours, or it reaches only what your user can            | Within 30 days        |
| Medium and low                                                                                 | In the next release   |

A one-person project can miss these: if it does, you hear why and when instead.

## The EU's Cyber Resilience Act and NIS2

Nightdrive is free, open-source software, made and given away without payment, sales, paid support or data
collection. As we understand them, the Cyber Resilience Act (EU 2024/2847) doesn't apply to free software that isn't
supplied in the course of a commercial activity, and NIS2 (EU 2022/2555) concerns organisations in its sectors, not
software like this. Nightdrive therefore makes no CRA declaration of conformity. It still handles vulnerabilities as
above, which is what the Act asks of those it applies to. This is our reading, not legal advice.
