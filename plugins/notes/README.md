# Notes

Your notes as Markdown files in `~/Notes`, in a window to read and write them: the newest first in the sidebar, the one you pick beside them. Claude can find, read and write them too. They are plain files, so any editor, Files and a sync folder work with them as they are.

## Using it

| Keys | |
| --- | --- |
| `?` | Notes' keys |
| ↑ ↓ or `j` `k` | Move in the list (`Home` `End`: the newest, the oldest) |
| `Enter` or `e` | Write in the note, here in the window (`Esc`: back to reading) |
| ⇧Enter | Open the note in Apostrophe |
| ⌘S | Save now: it saves by itself a moment after you stop typing, and when you leave the note |
| `Space` ⇧Space | Scroll the note |
| ⌘B | Hide or show the sidebar |

- A note is any `.md` file in `~/Notes`, in subfolders too; hidden files and folders are left out. Its title is its first heading (`# …`), else its file name.
- You write the Markdown as it is in the file; reading shows it formatted.
- ⇧Enter opens the note in Apostrophe (Install › Recommended), or without it in what opens Markdown here.
- What another app saves meanwhile (Apostrophe, Claude) shows at once. If it changes the note while you have unsaved text in it, Notes doesn't write over it: Keep mine (⌘S) or Keep theirs. Closed before you pick, what you wrote goes into a new note, "Title (not saved)".

## With Claude

In Settings › Claude › Access, the Notes row lets Claude list, search and read your notes, and, with reads and changes, write a new note, add to the end of one and move one to the trash. Each change shows a notification with Undo; nothing is deleted for good.

## In a terminal

| Command | What it does |
| --- | --- |
| `notes` | Open the window |
| `notes list`, `notes search WORDS` | The notes, newest first; the ones that have every word (`--json`) |
| `notes read NOTE`, `notes show NOTE`, `notes edit NOTE` | A note's text; the note in the window; in Apostrophe. NOTE is its file name (`Work/Plan.md`) or its title |
| `echo TEXT \| notes create TITLE` | A new note, named after its title |
| `echo TEXT \| notes append NOTE` | The text added to the end of a note |
| `echo TEXT \| notes write NOTE` | The note's whole text replaced, as the window saves (`--expect MD5`: only while it is still that text) |
| `notes trash NOTE` | The note to the trash, where Files puts it back |

`NOTES_DIR` points the command and the window at another folder.

Keys: Hyper N
