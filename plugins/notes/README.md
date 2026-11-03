# Notes

Your notes as Markdown files in `~/Notes`, in a window to read and write them: your folders and #tags on the left, the notes in the one you pick newest first, the note you pick beside them. Claude can find, read and write them too. They are plain files, so any editor, Files and a sync folder work with them as they are.

## Using it

| Keys | |
| --- | --- |
| `?` | Notes' keys |
| ↑ ↓ or `j` `k` | Move in the list (`Home` `End`: the newest, the oldest) |
| `/` or ⌘F | Search: the notes whose title or text has every word, the first line with them under each; the words are marked in the note. `Enter` or ↓ to the notes found, `Esc` back to every note |
| `n` or ⌘N | New note: it opens to write in, its title first after `# ` (New in the header too) |
| F2 or `r` | Rename: the note's heading and its file name follow the new title |
| `m` | Move the note to a folder: type to find one, or a new name to make it (or drag the note onto a folder) |
| `f` | The folders and tags: ↑ ↓ pick one, `Enter` back to the notes, `Delete` removes an empty folder |
| `Delete` or ⌘⌫ | Move the note to the trash; Undo (⌘Z) in the notice puts it back |
| `Enter` or `e` | Write in the note, here in the window (`Esc`: back to reading) |
| ⇧Enter | Open the note in Apostrophe |
| ⌘S | Save now: it saves by itself a moment after you stop typing, and when you leave the note |
| `Space` ⇧Space | Scroll the note |
| ⌘B | Hide or show the sidebars (while writing: bold) |

- A note is any `.md` file in `~/Notes`, in subfolders too; hidden files and folders are left out. Its title is its first heading (`# …`), else its file name.
- Folders are the real folders in `~/Notes`. Picking one shows its notes and those in its subfolders, and New writes there; the folder button by the title makes one inside it. Below 960 px the folders hide: `f` or the button by the list's title shows them.
- A tag is `#` and a word in the text (`#idea`, `#work/plans`; not a heading, a number such as `#2016`, code or a link). Picking one shows the notes that have it (`#work` takes in `#work/plans` too); a tag clicked in a note does the same.
- You write the Markdown as it is in the file; reading shows it formatted. While writing, `Enter` on a list item starts the next one (`- `, the next number, an empty `[ ]`), and on an empty item ends the list; `Tab` and ⇧Tab nest an item under the one above and take it back. ⌘B and ⌘I make the selection bold (`**`) and italic (`_`), or no longer; ⌘K makes it a link, to a copied address if there is one. ⌘Z undoes each of these as one step.
- Reading, a click on a task box (`- [ ]`) ticks or unticks it, saved at once.
- A note's file is named after its title (`~/Notes/Title.md`). A new one is `Untitled.md` until you leave it; then, and whenever you change the heading of a note whose file name was its title, the file follows the heading. A file you named otherwise keeps its name. A new note left with nothing written in it is deleted.
- ⇧Enter opens the note in Apostrophe (Install › Recommended), or without it in what opens Markdown here.
- What another app saves meanwhile (Apostrophe, Claude) shows at once. If it changes the note while you have unsaved text in it, Notes doesn't write over it: Keep mine (⌘S) or Keep theirs. Closed before you pick, what you wrote goes into a new note, "Title (not saved)".

## With Claude

In Settings › Claude › Access, the Notes row lets Claude list (also by folder or tag), search and read your notes, and, with reads and changes, write a new note (in a folder too), add to the end of one, rename one, move one to another folder and move one to the trash. Each change shows a notification with Undo; nothing is deleted for good.

## In a terminal

| Command | What it does |
| --- | --- |
| `notes` | Open the window |
| `notes list`, `notes search WORDS` | The notes, newest first (`--folder F`, `--tag T`); the ones that have every word (`--json`) |
| `notes folders` | The folders and tags, with how many notes each (`--json`) |
| `notes move NOTE FOLDER` | The note into the folder (`""` for the top), made if it isn't there |
| `notes mkdir FOLDER`, `notes rmdir FOLDER` | A new folder (`Work/Plans`); an empty one taken away |
| `notes find [WORDS]` | The window on its search, for WORDS or to type them in |
| `notes new [TITLE]` | The window on a new note to write in (without TITLE, its title is the first thing you write) |
| `notes read NOTE`, `notes show NOTE`, `notes edit NOTE` | A note's text; the note in the window; in Apostrophe. NOTE is its file name (`Work/Plan.md`) or its title |
| `echo TEXT \| notes create TITLE` | A new note, named after its title (`--folder F`: in that folder) |
| `echo TEXT \| notes append NOTE` | The text added to the end of a note |
| `echo TEXT \| notes write NOTE` | The note's whole text replaced, as the window saves (`--expect MD5`: only while it is still that text) |
| `notes rename NOTE TITLE` | A new title: the note's heading (`# …`, added when it has none) and its file name, in the same folder |
| `notes trash NOTE` | The note to the trash, where Files puts it back |

`NOTES_DIR` points the command and the window at another folder.

Keys: Hyper N
