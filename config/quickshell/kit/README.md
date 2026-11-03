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
| `AppSidebar` | The sidebar: the app's name (`AppTitle`) level with the view's header, a column of rows, a line on its right; `titleItems` at the title's right (`titleHovered`: Mail's gear shows only then) |
| `AppAccountBar` | The accounts at the sidebar's foot under a line: each one's label and count, a click picks one (`picked`); one account is its label alone |
| `AppTitle` | The app's name with the wordmark's block cursor: "Mail█" |
| `AppNavRow` | A row of the sidebar: glyph, name, count; `selected`, `dropTarget`, `active` (the keyboard is in the sidebar) |
| `AppPointer` | In the window's RowLayout: the pointer moving hides the keys' frame (`c.keyboard`: the app's key handlers call `c.moved(e)`, which only Tab and the arrows turn on) and brings back the hover colour any key put away (`c.pointerAway`: `AppRow`, `AppNavRow`) |
| `AppRow` | A list row's ground, for a `ListView` delegate: `selected`, `marked` (the keyboard's place, list not focused), `active` (the keys are here: a frame) |
| `AppButton` | A framed button with a glyph and a label (Play, New list); `strong`, `on`, a tip with its key (`tipAlign`) |
| `AppIconButton` | A glyph-only button (Back, Settings) with a tip (`tipSide`, `tipAlign`) |
| `AppSegments` | One of a few that go together as one framed switch (Week \| Month): `options` `[{ label, glyph, tip, keys }]`, `current`, `picked(i)`; the fill slides to the picked part, `compact` shows the glyphs |
| `AppSearchField` | The search glyph and a field; Return, ↓ and Esc come out as signals |
| `AppPanel` | A card over the dimmed window (settings, a question, a first start); a click outside comes out as a signal. Never taller than the window: its content scrolls, and its last row of `AppPanelButton`s stays in sight under it |
| `AppPanelButton` | A panel's answer (Create, Cancel): its keys in the theme colour, then the word; `strong` for the one Return gives |
| `AppConfirm` | A yes-or-no `AppPanel` before what can't be undone: `question`, `detail`, `action`; Return yes, Esc no |
| `AppPrompt` | An `AppPanel` that asks for a name: `ask(title, initial, then)`, the text picked; `then` gets it trimmed |
| `AppField` | A labelled text field in a frame for the panels, with a `hint` ("GB"); typing into a read-only one comes out as `refused` |
| `AppTextArea` | A labelled text of a few lines in a frame (a task's note): ⏎ a new line, Ctrl+⏎ `save`, Tab the next field |
| `AppChips` | One of a few as chips in a row (the list a task goes in): `options` `[{ id, name, color? }]`, `picked`; ← → move it |
| `AppCheck` | A box to tick and its word (Important): `on`, Space or a click turns it (`toggled`), ⏎ `accepted` |
| `AppNote` | What went wrong, at the foot of the page, in the danger colour, until ✕; two lines at most |
| `AppToast` | What just happened, in a rounded card at the top of the window: `show(text, { sticky, danger, duration, action, run })`, gone after 4 s (a failure 8 s, one with an action such as Undo 7 s), sticky until the next; a click dismisses it, `act()` runs the action for a key (⌘Z) |
| `AppKeyAction` | A key in a box and a word to click: "⏎ Set up with Claude" |
| `Tip` | A button's tip: what it does and its key |
| `Spinner` | A turning glyph while something runs in the background (Mail's fetch), shown at least a moment; a tip says what runs |
| `KeyCap` | Keys as caps: "⌘N  c" is [⌘][N] [c] (`or`: a "/" between the alternatives); `tint` colours them |
| `Key` | One key cap, Raycast's way: a square a little lighter than its ground, a name (esc, HYPER) wider. The launcher uses it too (`import qs.kit as Kit`) |
| `KeySheet` | The window's keys, on ? and Ctrl+? |
| `Regional` | Dates and times the user's way (Settings › Region, `regions.json`): `format(dateOrIso, "short" \| "day" \| "medium" \| "long" \| "time" \| "month")` (3.11.2026, Tue 3 November 2026; 11/3/2026 in the US), `time("14:30")`, `range(a, b)` ("2 – 8 Nov 2026"), `parse(text, baseIso)` and `parseTime(text)` back to "YYYY-MM-DD" and "HH:MM" ("" when unreadable), `weekStart`, `weekdays`, `h24`, `example`. Names stay English. A singleton over `Dates.js`, whose pure functions take the region as an argument |

The app's command (`nightmail`, `deck-window`) sources `kit/app.sh` through the same link, after setting `QS_DIR`,
`APP_TITLE` (the window's title) and `APP_IPC` (its IpcHandler's target): it starts the window or brings it forward,
waits for it to answer over IPC (`open_ready`, `ipc …`), and `app_command` does what every app's command does: open (the
default), restart, quit, log and settings. The app's own commands come first in its case.

The parts hold the look; what the app shows in them, and what its keys do, stay in the app. When an app needs a part to
do a little more, give the part a property with the old behaviour as its default, so the other apps don't change.

A change here reaches every app at once: check each one (`nightdrive sandbox`, then compare screenshots before and after).
Quickshell keeps the old version of a part in its own file until the app restarts.
