# Text

Nightdrive's editor for plain text: a `.txt`, `.csv`, `.json`, a config file or a script opens here from Files, a link
or `text FILE`, unless you chose another text editor in Launcher › Settings › Apps › Default apps (source code too,
until you choose a code editor there). Several files open side by side, listed on the left once there are two.

## Using it

| Keys | |
| --- | --- |
| Ctrl `?` | Text's keys (`?` alone is a character to type) |
| ⌘O | Open files (the desktop's Open window: Files' when `files picker on`) |
| ⌘N | New file: you pick where it goes first, then write |
| ⌘S | Save; changed elsewhere meanwhile: keep yours |
| ⌘⇧W | Close the file (asks if it isn't saved) |
| Ctrl Tab, ⇧Ctrl Tab | The next, the previous open file |
| ⌘F, then ⏎ ⇧⏎ | Find in the file, the next, the previous (⌘G ⇧⌘G too); Esc back to the text |
| ⌘B | Show or hide the list of open files |
| ⌘Q | Quit, asking first about files that aren't saved |

- It saves only on ⌘S, never by itself: a config file half written would be read at once by what watches it (Hyprland and the top bar reload on save).
- A file changed elsewhere (another editor, Claude, git) shows its new text at once. If you have unsaved changes in it, the bar says so: Keep mine writes yours over it, Take theirs drops yours.
- ⌘W closes the window without asking: what wasn't saved is kept, and the files open again with it, still unsaved, the next time Text opens.
- Saving keeps what the file is: a link stays a link (the file it points at is written), a script stays executable, and a file with Windows line ends keeps them.
- It edits UTF-8 text up to 8 MB; anything else (binary, another encoding) is refused with the reason, not opened half-read.

## Commands

| Command | |
| --- | --- |
| `text [FILE…]` | Open Text, with the files in it |
| `text install` | Text among the desktop's apps, and the text editor unless you chose one (`uninstall` takes it out) |
| `text restart`, `text quit`, `text log` | After a change to the app; quit at once (unsaved text is lost); its log |

Needs: python3-gobject (the Open and New windows)
