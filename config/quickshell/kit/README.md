# The apps' kit

The parts Nightdrive's own apps (Mail, Deck, and the ones to come) are built from, so they look and work alike: a sidebar
with the app's name, rows that are picked the same way, the same buttons, tips and key sheet. Each app is a Quickshell
config of its own (`plugins/<app>/app/shell.qml`, run with `qs -p`), and links this folder into it:

    ln -s ../../../config/quickshell/kit plugins/<app>/app/kit

and imports it with `import qs.kit`. The kit's parts use `Theme` and `Icons` through `import qs`, so the app links those
two into its own folder as well (`Theme.qml`, `Icons.qml`), and whatever else of the desktop's it uses (`TouchScroll.qml`).

Every part takes the app's look as `c`: make one `AppLook { id: c }` in the window, and pass it on (`c: win.look`, with
`readonly property QtObject look: c` on the window, for parts in files of their own that don't see the window's ids).

| Part | What it is |
|---|---|
| `AppLook` | The colours: the desktop's theme, with the terminal's background behind the window and a few shades from it |
| `AppSidebar` | The sidebar: the app's name (`AppTitle`) level with the view's header, a column of rows, a line on its right |
| `AppTitle` | The app's name with the wordmark's block cursor: "Mail█" |
| `AppNavRow` | A row of the sidebar: glyph, name, count; `selected`, `dropTarget` |
| `AppRow` | A list row's ground, for a `ListView` delegate: `selected`, `marked` (the keyboard's place, list not focused) |
| `AppButton` | A framed button with a glyph and a label (Play, New list); `strong`, `on`, a tip with its key (`tipAlign`) |
| `AppIconButton` | A glyph-only button (Back, Settings) with a tip (`tipSide`, `tipAlign`) |
| `AppSearchField` | The search glyph and a field; Return, ↓ and Esc come out as signals |
| `AppPanel` | A card over the dimmed window (settings, a question, a first start); a click outside comes out as a signal |
| `AppKeyAction` | A key in a box and a word to click: "⏎ Set up with Claude" |
| `Tip` | A button's tip: what it does and its key |
| `KeyCap` | Keys in boxes: "⌘N  c" |
| `KeySheet` | The window's keys, on ? and Ctrl+? |

The app's command (`nightmail`, `deck-window`) sources `kit/app.sh` through the same link, after setting `QS_DIR`,
`APP_TITLE` (the window's title) and `APP_IPC` (its IpcHandler's target): it starts the window or brings it forward,
waits for it to answer over IPC (`open_ready`, `ipc …`), and `app_command` does what every app's command does: open (the
default), restart, quit, log and settings. The app's own commands come first in its case.

The parts hold the look; what the app shows in them, and what its keys do, stay in the app. When an app needs a part to
do a little more, give the part a property with the old behaviour as its default, so the other apps don't change.

A change here reaches every app at once: check each one (`nightdrive sandbox`, then compare screenshots before and after).
Quickshell keeps the old version of a part in its own file until the app restarts.
