# Agent notes

The config is **live**: `link.sh` symlinks `config/*` into `~/.config`, and Quickshell and Hyprland reload on save. Keep every
save valid, then check:
- Hyprland: `hyprctl configerrors` should be empty.
- Quickshell: `qs log | tail` should show no QML errors.
- Scripts: `bash -n` for shell, `ast.parse` for Python.

Test over IPC (`qs ipc show`, e.g. `qs ipc call launcher openLevel settings`) and take screenshots with `grim`. `launcher rows`
returns the open level's title, footer and rows as JSON: compare it before and after a change to the launcher.
The user may be typing on this same desktop, and the launcher and menus take the keyboard: run `~/.local/bin/nightdrive
agent-warn "the launcher"` before opening one (once per burst of tests) and open it only after it returns (~5 s countdown
with sound). Use the full path: an agent's shell may not have `~/.local/bin` in its PATH, and if the command fails, don't
open anything.
Don't press Enter over IPC on rows that act on real things (Home Assistant devices, Power).
On a machine without Hyprland, or to leave the user's desktop alone, use the headless container: `nightdrive sandbox
check` (exit 1 with the findings) and `nightdrive sandbox shot NAME`, `ipc …` for the rest (docs/sandbox.md; no agent-warn there).

**Pitfalls**
- Menu icons are invisible private-use glyphs in strings. Don't retype those lines, and compare the glyph counts with HEAD.
  (The top bar uses icon names instead: `config/topbar/scripts/icon`.)
- `pkill -f foo` matches its own shell: use `'[f]oo'`.
- Hyprland's config is Lua: `hyprctl dispatch 'hl.dsp.…'`.
- Quickshell's reload on save keeps the old version of a component in its own file (e.g. `TouchScroll.qml`, listed in
  `qmldir`), and doesn't reload a plugin's menu at all: restart it to test a change there (`qs kill; setsid -f qs`).

**Branches**
- `main` is stable: stable-channel users get it with `nightdrive update`. Every change is made in `dev`, a fix to what
  users run too, and reaches `main` only in a release, once tested. Users pick their channel with `nightdrive channel`
  (stable or dev).
- Check the branch before committing (`git branch --show-current`): it is `dev`. No commits straight to `main` and no
  cherry-picks, so `main` is always an earlier point of `dev` and a release has nothing to conflict with.
- A release, and pushing, are the user's decisions: don't do either unasked. `nightdrive release [patch|minor|major]`
  makes one from `dev`: the plugins' versions (`plugins bump`, plugins/README.md › Versions), the notes as a new section
  of `CHANGELOG.md`, the website's docs check, then the commit, the tag `vX.Y.Z`, `main` moved to it, the push, the
  GitHub release and, once the website has rebuilt, its publishing (its `tools/publish.sh`). `--dry-run` shows what it
  would do.
- Release notes are for users, in plain words: what they can now do, what works better, what they need to do. Never
  the commit messages as such. Write them from the commits (`--dry-run` lists them), let the user read them, then
  `nightdrive release … --notes FILE --yes`. A release with a name (Afterglow) gets `--name NAME`: the heading
  `## 0.6.0 Afterglow – date` and the GitHub release "Nightdrive 0.6 Afterglow"; the tag and updates keep the number.
- A big piece of work that shouldn't hold up or swell the next release (a new app: Calendar, Contacts) gets a branch of
  its own off `dev`, in a worktree beside the live one: `git worktree add ~/dotfiles-<name> -b <name> dev`. `~/dotfiles`
  stays on `dev`, so the desktop doesn't change; an app runs from the worktree (`qs -p ~/dotfiles-<name>/plugins/<name>/app`)
  or in the sandbox (the worktree's own `bin/nightdrive sandbox` mounts it: `sandbox down` first if one runs). A request about what users already have (Mail, Deck, the desktop) goes to `~/dotfiles`, the new
  thing's to its worktree. The apps' kit (`config/quickshell/kit`) changes only in `dev`, merged into the branch from
  there (`git merge dev`, often). The branch is merged into `dev` once it is usable, and reaches users in the release after.
- A part of an app that works without Nightdrive (Deck's player and CLI) has a repo of its own in `~/Projects`; the
  Nightdrive window over it stays here, with the kit.
- When it suits what was released, the notes get a picture of it (a collage of a few redesigned menus, a new window):
  `docs/releases/<version>-<name>.jpg`, on a line of its own `![What it shows](docs/releases/…)`. The website's
  Changelog shows it, the GitHub release too (the script points it at the tag), `nightdrive update` leaves it out.

**Conventions**
- English comments that explain *why*.
- Code is written only by Claude, so files stay small for the context: one file does one thing, ~200–400 lines. Past ~600,
  split off what stands on its own (a component, a library, a level); past ~800 it must be split (generated files such as
  `Icons.qml` excepted). A new app or feature is planned in small files from the start.
- Colours come from `Theme.*` in QML, and the bar's from `TopBar.c()` (bar-style; source: `THEMES` in `hypr/scripts/theme`).
- Machine-specific values are named constants at the top of each file.
- Nothing personal goes in the repo. Private additions use the git-ignored *local* slots (README › Make it yours).

**Documentation**
- The README, `docs/*.md`, each plugin's `README.md` and the `SHORTCUTS.md` files are the documentation, and the website
  (nightdrive.sh: Documentation, Plugins) is built from them, not written separately. So a change users can see updates
  them in the same commit: a new feature, key, command or option gets its line there.
- Keep it short: its readers know computers, and a long README goes unread. Say what isn't self-evident (keys, commands,
  limits, what the user must do) and leave out what the UI already shows, but never what matters.
- A new `##` / `###` section in the README or a new file in `docs/` also needs a place in the website's contents
  (`data/docs.json` in the nightdrive-website repo). Its build (`tools/build.sh`) lists what has none and stops.
- A push to `main` rebuilds the website's pages by itself (`.github/workflows/website.yml`; the site's README explains
  it), but that build stops on such a missing place too: check `tools/build.sh --ref dev` there before a release.

**Recipes**
- *App* (one of Nightdrive's own, a window: Mail, Deck): a plugin folder whose `app/shell.qml` is a Quickshell config of
  its own, built from the apps' kit (`config/quickshell/kit/README.md`: sidebar, rows, buttons, panels, key sheet). A
  change to a kit part reaches every app: compare each app's screenshots before and after. Its command in `bin/` (one,
  named for the app) is built on `kit/app.sh`.
- *Plugin* (an optional feature: a bar icon and menu, keys, a service): a folder `plugins/<id>/` as `plugins/README.md`
  explains (copy its Disk example, or `plugins/localsend`), then `nightdrive plugin check <id>`. After changing its
  `module.jsonc` or adding a menu or launcher levels (`<Name>Levels.qml`), run `nightdrive plugins installed`; after
  changing its keys, `hyprctl reload`.
- *Ferry* is an app of its own (github.com/nightdrive-sh/ferry): its server, `ferry` command and window change in its
  repo, against its `docs/protocol.md`. `plugins/ferry` is only Nightdrive's side: the top bar module and menu, which
  use `ferry list --json` and the other commands, the hook Ferry runs when its box changes (`~/.config/ferry/hook`), and
  `install.sh`, which installs Ferry's latest release without its tray icon (`nightdrive update` runs it with
  `--update`). `FERRY_FROM=<a Ferry checkout's linux/>` installs one that isn't released.
- *Bar icon and menu* in the core (on every desktop): an entry in `topbar/modules.jsonc` (its place in the bar), a case
  in `topbar/scripts/status` (`emit ICON TEXT CLASS`), and `quickshell/<Name>Menu.qml` (copy an existing menu). Size it
  with `nightdrive topbar adjust`. Every menu follows the rules in `plugins/README.md` › The menu: `MenuHeader` first, rows
  `MenuRow`, section titles `MenuSection`, hint and error lines `MenuNote`, colours `Theme.*`.
- *Launcher level:* a page or group of pages goes in its own `quickshell/<Name>Levels.qml` (copy `BehaviourLevels.qml`:
  `levels`, `titles`, `parents`, `items`, `activate`, `footer`, `entered`; optional keys: `extCtrl`, `extDelete`, `extMove` there),
  listed in `qmldir` and in `exts` in `Launcher.qml`; the row that opens it goes in `rootItems`/`statics` there.
- *Keybinding:* `hypr/bindings.lua`, and the same entry in `hypr/SHORTCUTS.md` (the launcher reads that file). An app opens
  with Hyper + a letter (`"MOD3 + X"`, `Hyper X` in SHORTCUTS.md); desktop features use ⌘⇧ / ⌘⌥; ⌘ + a letter is the apps'.
- *Command:* a subcommand in the case at the bottom of `bin/nightdrive` (link.sh links it to `~/.local/bin`).
