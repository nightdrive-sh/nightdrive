# Files

Your files and folders in a window of Nightdrive's own, run from the keyboard: yazi's letters and the Mac's ⌘ keys side
by side, a preview of the picked file at the right and a big one on Space, and the desktop's clipboard and trash, which
Nautilus and other apps share. It opens folders for the whole desktop: Hyper F, a folder another app opens, and a
browser's "Show in folder".

## Using it

| Keys | |
| --- | --- |
| `?` | Files' keys |
| ↑ ↓ or `j` `k` | Move in the list |
| → ⏎ or `l` | Open: into a folder, a file in its app (a double click too; ⌘O) |
| ← ⌫ or `h` | Up a folder |
| `gg` `G` | First, last |
| ⌥← ⌥→ (⌃⌘← ⌃⌘→) | Back, forward |
| `~` `gh` `gd` | Home, home, Downloads |
| ⌘L | Go to a folder by its path |
| Space | The big preview: a picture, a PDF's first page, a video's frame or a text; ↑ ↓ go through the files, Space or Esc closes it |
| `i` | The preview at the right (a narrow window leaves it out) |
| `/` or ⌘F | Filter by name as you type: ⏎ back to the list with it kept, Esc shows all again |
| `f`, or Tab in the filter | Search all of home by name, and Tab back to this folder; ⌘F again or a click on the scope at the field's end does the same. Outside home (a USB stick) it searches the folder and every one below it. Each file shows the folder it is in, ← goes there |
| `.` | Hidden files (⌘⇧. too) |
| `s` `S` | Sort by name, time, size or type; the other way round (a click on a column's title too) |
| `v` | Mark the file and go on to the next; ⇧↑ ⇧↓ mark on the way, ⌘A marks all, ⌘-click and ⇧-click with the mouse, Esc unmarks |
| `y` `x` `p` or ⌘C ⌘X ⌘V | Copy, cut, paste here: the marked files, else the picked one |
| `d` or ⌘⌫ | To the trash |
| `r` or F2 | Rename (the name without its ending is picked) |
| `a` | A new file; a name ending in `/` makes a folder (⌘⇧N: a folder) |
| ⌘Z | Undo the last change (also Undo in the message at the top) |
| `b` or ⌘D | Bookmark the picked folder (with a file picked, the one you're in), or take it away |
| `Tab` | Keys between the sidebar and the list |
| ⌘N | A new window, in the same folder (a folder from another app goes to the one last used) |
| ⌘B ⌘R | Hide the sidebar, read the folder again |
| ⌘, | Settings (also the gear on the sidebar's title): Normal rows, taller and easy to click, or Compact |

- The sidebar has two groups of folders, then the disks and the trash. The first is Files' own, home's folders to start with (`~/.config/nightdrive/files/places.json`); the second, the bookmarks, are GTK's (`~/.config/gtk-3.0/bookmarks`), the same the apps' Open dialogs list: a quick place for a project's folders. Drag a folder to another place in its group or into the other one; its ✕ takes it out (with Undo). A USB stick shows when it is plugged in, mounts as you pick it and has an eject button.
- The clipboard is the desktop's: files copied here paste into a mail, a chat or a browser, and files copied in Nautilus paste here. A cut moves the files once pasted.
- Drag files out of the list into another app, or onto a folder in the list, the sidebar or the path at the top; files dragged in from another app are copied, and from Files itself moved. Dropped on Trash, they go there.
- A copy or move never writes over a file: a name already there gets " (2)". A long one shows how far it is, with Stop.
- The search of home is fd's, always up to date: what it leaves out stays out (hidden files unless `.` shows them, `.git`, and what a `.gitignore`, `.ignore` or `.fdignore` excludes), and so do other disks under the folder. It stops at 2000 files: type more to narrow it.
- The trash is the one Nautilus and `gio trash` use (a USB stick's stays on the stick). `d` moves to it at once (Undo brings it back), but asks first about home's own folders (Documents…), the sidebar's and home's hidden ones (`.config`…); home itself, the folders above it and the trash never go. In it, `u` puts the picked files back where they were, `d` deletes them for good after asking, and ⌘⇧⌫ or Empty empties it.

## In a terminal

    files                        # open Files, or bring it forward
    files ~/Projects             # a folder in it; a file shows in its folder, picked
    files enable                 # Files opens folders for the desktop (the installer runs it)
    files disable                # folders open in Nautilus again

Needs: nothing to set up (Python, GObject, wl-clipboard, poppler-utils and fd-find, which its installer adds)
