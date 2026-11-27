# Releasing

For the session that makes a release. A release, and pushing, are the user's decisions: don't do either unasked
(AGENTS.md › Branches).

- `nightdrive release [patch|minor|major]` makes one from `dev`: the plugins' versions (`plugins bump`,
  plugins/README.md › Versions), the notes as a new section of `CHANGELOG.md`, the website's docs check, a warning when
  Deck or Ferry has a newer release than the one pinned (`DECK_REF` in `plugins/deck/install.sh`, `plugins/ferry/pin`;
  `config/hypr/scripts/release-pins`), then the commit, the tag `vX.Y.Z`, `main` moved to it, the push, the GitHub
  release and, once the website has rebuilt, its publishing (its `tools/publish.sh`). `--dry-run` shows what it would do.
- Release notes are for users, in plain words: what they can now do, what works better, what they need to do. Never
  the commit messages as such. Write them from the commits (`--dry-run` lists them), let the user read them, also as
  the website's Changelog page (`nightdrive release … --notes FILE --preview`, or with `--dry-run`: built in throwaway
  clones of dotfiles and the website's checkout, served on 127.0.0.1 for 20 minutes and opened in the browser), then
  `nightdrive release … --notes FILE --yes`. A release with a name (Afterglow) gets `--name NAME`: the heading
  `## 0.6.0 Afterglow – date` and the GitHub release "Nightdrive 0.6 Afterglow"; the tag and updates keep the number.
- When it suits what was released, the notes get a picture of it (a collage of a few redesigned menus, a new window):
  `docs/releases/<version>-<name>.jpg`, on a line of its own `![What it shows](docs/releases/…)`. The website's
  Changelog shows it, the GitHub release too (the script points it at the tag), `nightdrive update` leaves it out.
- Before a release, check the website's build against `dev` (`tools/build.sh --ref dev` in its checkout): a README
  section or `docs/` file with no place in its contents stops the build (AGENTS.md › Documentation).
