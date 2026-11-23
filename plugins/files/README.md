# Files

Your files and folders in a window of Nightdrive's own, run from the keyboard: yazi's letters and the Mac's ⌘ keys side
by side, a preview of the picked file at the right and a big one on Space, and the desktop's clipboard and trash, which
Nautilus and other apps share. It opens folders for the whole desktop: Hyper F, a folder another app opens, and a
browser's "Show in folder", each in a new window on the workspace you are on (several share one cut and the settings). Nautilus stays installed beside it as Files (Nautilus): out of the Launcher's Apps list,
found by a search for "files" or "nautilus" after Files.

## Using it

| Keys | |
| --- | --- |
| `?` | Files' keys |
| ↑ ↓ or `j` `k` | Move in the list |
| → ⏎ or `l` `o` | Open: into a folder, a file in its app (a double click too; ⌘O); on an archive ⏎ and `o` extract it (⌘O opens it), → and `l` look into it |
| → or `l` on an archive | Into it as a read-only folder (zip, tar, tar.gz, tar.xz…): its folders, the preview and Space work, ← goes back out. `y` there and `p` in a folder take out only what was marked, else the picked one; what would change it (trash, rename, paste, compress) says it can't |
| ⏎ on a program | Asks first, every time: Run, Run in Terminal (⌘⏎) or Cancel. A program (an ELF, an AppImage, a script with `#!` and its execute bit) runs in its own folder and stays when Files closes. One that came without its execute bit, as a download does, offers Make Executable and Run. A file no app opens says so, with Open with… |
| `O` | Open with: the apps for the file's type, its default first, in a menu at the file; type to find any other app. ⏎ opens the file (or the marked ones) in it, ⌘⏎ also makes it the default for every file of the type |
| ← ⌫ or `h` | Up a folder |
| `gg` `G` | First, last |
| ⌥← ⌥→ (⌃⌘← ⌃⌘→) | Back, forward |
| `~` `gh` `gd` | Home, home, Downloads |
| ⌘L | Go to a folder by its path |
| Space | The big preview, over the whole screen Files is on: a picture (never larger than its own size; the wheel zooms in where the pointer is, a drag moves it, a double click fits it again), a PDF's first page, a video's frame or a text, and a sound plays at once (`p` pauses, ← → 5 s back or on, a click or drag on its bar goes there); ↑ ↓ go through the files, Space, Esc or a click beside it closes it, and the sound stops with it |
| `i` | The preview at the right (a narrow window leaves it out); a sound has a player there, its play button plays it |
| `/` or ⌘F | Filter by name as you type: ⏎ back to the list with it kept, Esc shows all again |
| `f`, or Tab in the filter | Search all of home by name, and Tab back to this folder; ⌘F again or a click on the scope at the field's end does the same. Outside home (a USB stick) it searches the folder and every one below it. Each file shows the folder it is in, ← goes there |
| `t` | Thumbnails in a grid, then columns, then the list again (also the button in the header). Each folder keeps its list or grid; a new one is a list. In the grid `h` `j` `k` `l` and the arrows move in all four ways, ⏎ opens and ⌫ goes up |
| `t` `t` from the list: columns | The folders from home down side by side, the picked folder's files or the file's preview last, as in Finder and yazi: ← → or `h` `l` from column to column, the keys act in the lit one. A narrow window shows the last columns, a scroll left the rest. They stay in the window until `t` (not kept for the next one); a search's results, the trash and an archive show as the list |
| `+` `-` | Larger or smaller thumbnails in the grid (96, 128 or 192 px), the same in every folder |
| `.` | Hidden files (⌘⇧. too) |
| `s` `S` | Sort by name, time, size or type; the other way round (a click on a column's title too) |
| `v` | Mark the file and go on to the next; ⇧↑ ⇧↓ mark on the way, ⌘A marks all, Esc unmarks. With the mouse Ctrl-click (the Control key: ⌘-click moves the window) marks one, ⇧-click the files from the one last clicked or picked to it (in place of the marks before), ⌘⇧-click adds them; in a filter or a search only the files shown |
| `y` `x` `p` or ⌘C ⌘X ⌘V | Copy, cut, paste here: the marked files, else the picked one. A copy pastes as the files in a file browser, as their paths (one a line) in a terminal or a text field, and as attachments in Mail |
| `d` or ⌘⌫ | To the trash |
| `r` or F2 | Rename (the name without its ending is picked) |
| `a` | A new file; a name ending in `/` makes a folder (⌘⇧N: a folder) |
| `c` | Compress the marked files, else the picked one, into an archive here: its name and format (zip, tar.gz, tar.xz, tar; ↑ ↓ change it) |
| `m` | Mail the marked files, else the picked one: a new message in Mail with them attached (or the message being written takes them). Folders can't go: compress them first |
| `e` or ⏎ | Extract the picked archive (zip, tar, tar.gz, tar.bz2, tar.xz) beside it |
| ⌘Z | Undo the last change (also Undo in the message at the top) |
| `b` or ⌘D | Bookmark the picked folder (with a file picked, the one you're in), or take it away |
| `Tab` | Keys between the sidebar and the list |
| ⌘N | A new window, in the same folder |
| ⌘B ⌘R | Hide the sidebar, read the folder again |
| ⌘, | Settings (also the gear on the sidebar's title): Normal rows, taller and easy to click, or Compact |

- The sidebar has two groups of folders, then the disks and the trash. The first is Files' own, home's folders to start with (`~/.config/nightdrive/files/places.json`); the second, the bookmarks, are GTK's (`~/.config/gtk-3.0/bookmarks`), the same the apps' Open dialogs list: a quick place for a project's folders. Drag a folder to another place in its group or into the other one; its ✕ takes it out (with Undo). A USB stick shows when it is plugged in, mounts as you pick it and has an eject button.
- The clipboard is the desktop's: files copied here paste into a mail, a chat or a browser, and files copied in Nautilus paste here. A cut moves the files once pasted.
- Drag files out of the list into another app, or onto a folder in the list, the sidebar or the path at the top; files dragged in from another app are copied, and from Files itself moved. Dropped on Trash, they go there.
- A copy or move never writes over a file: a name already there gets " (2)". A long one shows how far it is, with Stop.
- An archive with one thing at its top extracts as that file or folder, one with several into a folder of the archive's name. Paths that would land outside it (`..`, `/etc/…`) and links pointing out are left out, and the message says how many. Nothing is written over: a name taken gets " (2)". Both show how far they are, with Stop, and Undo trashes what they made. The same rules hold for what `y` and `p` take out of an archive looked into.
- Looking into an archive unpacks nothing: a zip lists at once, a compressed tar is read from start to end the first time (a big one shows how far), and its listing is kept in `~/.cache/nightdrive/files/archives`, so the next look is at once. A file previewed is taken out on its own into a temporary place that goes when you leave the archive.
- The search of home is fd's, always up to date: what it leaves out stays out (hidden files unless `.` shows them, `.git`, and what a `.gitignore`, `.ignore` or `.fdignore` excludes), and so do other disks under the folder. It stops at 2000 files: type more to narrow it.
- The grid's thumbnails (pictures, a PDF's first page, a video's frame) are kept where Nautilus and the other apps keep theirs (`~/.cache/thumbnails`), so each is drawn once and shared with them. Video frames need ffmpeg.
- The trash is the one Nautilus and `gio trash` use (a USB stick's stays on the stick). `d` moves to it at once (Undo brings it back), but asks first about home's own folders (Documents…), the sidebar's and home's hidden ones (`.config`…); home itself, the folders above it and the trash never go. In it, `u` puts the picked files back where they were, `d` deletes them for good after asking, and ⌘⇧⌫ or Empty empties it.

## In a terminal

    files                        # a new window, home
    files ~/Projects             # a folder in a new window; a file shows in its folder, picked
    files enable                 # Files opens folders for the desktop (the installer runs it)
    files disable                # folders open in Nautilus again, under its own name

Needs: nothing to set up (Python, GObject, GdkPixbuf, wl-clipboard, poppler-utils and fd-find, which its installer adds)
