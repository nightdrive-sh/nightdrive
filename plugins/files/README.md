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
| ⏎ on a program | Asks first, every time: Run, Run in Terminal (⌘⏎) or Cancel. A program (an ELF, an AppImage, a script with `#!` and its execute bit) runs in its own folder and stays when Files closes. One that came without its execute bit, as a download does, offers Make Executable and Run. A file no app opens says so, with Open with… and, where one is known, the app to install (LibreOffice Calc for an .xlsx): an archive's app (Nautilus for a zip) never takes a document that is a zip inside |
| `O` | Open with: the apps for the file's type, its default first, in a menu at the file; type to find any other app. ⏎ opens the file (or the marked ones) in it, ⌘⏎ also makes it the default for every file of the type |
| ← ⌫ or `h` | Up a folder |
| `gg` `G` | First, last |
| ⌥← ⌥→ (⌃⌘← ⌃⌘→) | Back, forward |
| `~` `gh` `gd` | Home, home, Downloads |
| ⌘L | Go to a folder by its path |
| Space | The big preview, over the whole screen Files is on: a picture (never larger than its own size; the wheel zooms in where the pointer is, a drag moves it, a double click fits it again), a PDF's first page, a video's frame or a text, and a sound plays at once (`p` pauses, ← → 5 s back or on, a click or drag on its bar goes there); ↑ ↓ go through the files, Space, Esc or a click beside it closes it, and the sound stops with it |
| `i` | The preview at the right (a narrow window leaves it out); a sound has a player there, its play button plays it |
| `I` or ⌘I | Info on the picked file or folder: its kind, size (a folder's is counted for up to 2 s), where it is, when it changed, its owner and group, and who may read, write and run it. A file of your own has an Executable switch (Space), as `chmod +x` gives, with Undo; the rest of the permissions are only shown |
| `/` or ⌘F | Filter by name as you type: ⏎ back to the list with it kept, Esc shows all again |
| `f`, or Tab in the filter | Search all of home by name, and Tab back to this folder; ⌘F again or a click on the scope at the field's end does the same. Outside home (a USB stick) it searches the folder and every one below it. Each file shows the folder it is in, ← goes there |
| `t` | Thumbnails in a grid, then columns, then the list again (also the button in the header). Each folder keeps its list or grid; a new one is a list. In the grid `h` `j` `k` `l` and the arrows move in all four ways, ⏎ opens and ⌫ goes up |
| `t` `t` from the list: columns | As yazi has them: the folder above, this one, and the picked folder's files or the file's preview. How many folders above show depends only on the window's width (none in a narrow one, up to three in a wide one), so nothing moves as you go. ← → or `h` `l` from column to column; the keys act in the middle one. They stay in the window until `t` (not kept for the next one); a search's results and the trash show as the list. A double click opens a row in any column. An archive looked into shows its folders as columns too |
| `+` `-` | Larger or smaller thumbnails in the grid (96, 128 or 192 px), the same in every folder |
| `.` | Hidden files (⌘⇧. too) |
| `s` `S` | Sort by name, time, size or type; the other way round (a click on a column's title too) |
| `v` | Mark the file and go on to the next; ⇧↑ ⇧↓ mark on the way, ⌘A marks all, Esc unmarks. With the mouse Ctrl-click (the Control key: ⌘-click moves the window) marks one, ⇧-click the files from the one last clicked or picked to it (in place of the marks before), ⌘⇧-click adds them; in a filter or a search only the files shown |
| `y` `x` `p` or ⌘C ⌘X ⌘V | Copy, cut, paste here: the marked files, else the picked one. A copy pastes as the files in a file browser, as their paths (one a line) in a terminal or a text field, and as attachments in Mail |
| `d`, Delete or ⌘⌫ | To the trash, after asking: the question names the files (a few, then how many more); ⏎ moves them, Esc or any letter typed keeps them |
| `r` or F2 | Rename (the name without its ending is picked) |
| `a` | A new file; a name ending in `/` makes a folder (⌘⇧N: a folder) |
| `c` | Compress the marked files, else the picked one, into an archive here: its name and format (zip, tar.gz, tar.xz, tar; ↑ ↓ change it) |
| `m` | Mail the marked files, else the picked one: a new message in Mail with them attached (or the message being written takes them). Folders can't go: compress them first |
| `e` or ⏎ | Extract the picked archive (zip, tar, tar.gz, tar.bz2, tar.xz) beside it |
| ⌘Z | Undo the last change (also Undo in the message at the top) |
| `b` or ⌘D | Bookmark the picked folder (with a file picked, the one you're in), or take it away |
| `Tab` | Keys between the sidebar and the list |
| ⌘N | A new window, in the same folder |
| `T` | A terminal in the folder on show (the one chosen in Settings › Apps › Default apps); in an archive, the folder it is in |
| ⌘B ⌘R | Hide the sidebar, read the folder again |
| ⌘, | Settings (also the gear on the sidebar's title): Normal rows, taller and easy to click, or Compact |

- The sidebar has two groups of folders, then the disks and the trash. The first is Files' own, home's folders to start with (`~/.config/nightdrive/files/places.json`); the second, the bookmarks, are GTK's (`~/.config/gtk-3.0/bookmarks`), the same the apps' Open dialogs list: a quick place for a project's folders. Drag a folder to another place in its group or into the other one; its ✕ takes it out (with Undo). A USB stick shows when it is plugged in, mounts as you pick it and has an eject button. Network drives (the Network Drives plugin) come after the disks with a cloud: eject disconnects one, and one not connected connects as you pick it.
- The clipboard is the desktop's: files copied here paste into a mail, a chat or a browser, and files copied in Nautilus paste here. A cut moves the files once pasted.
- Drag files out of the list into another app, or onto a folder in the list, the sidebar or the path at the top; files dragged in from another app are copied, and from Files itself moved. Dropped on Trash, they go there.
- A copy or move never writes over a file: a name already there gets " (2)". A long one shows how far it is, with Stop.
- An archive with one thing at its top extracts as that file or folder, one with several into a folder of the archive's name. Paths that would land outside it (`..`, `/etc/…`) and links pointing out are left out, and the message says how many. Nothing is written over: a name taken gets " (2)". Both show how far they are, with Stop, and Undo trashes what they made. The same rules hold for what `y` and `p` take out of an archive looked into.
- An archive opened from another app (a browser's Open, `xdg-open`, `gio open`) extracts the same way, in a new Files window with Undo: Files is the default of zip and tar types while it is installed (`files extract FILE`). A default you chose for them stays; `files disable` takes Files' away.
- Looking into an archive unpacks nothing: a zip lists at once, a compressed tar is read from start to end the first time (a big one shows how far), and its listing is kept in `~/.cache/nightdrive/files/archives`, so the next look is at once. A file previewed is taken out on its own into a temporary place that goes when you leave the archive.
- The search of home is fd's, always up to date: what it leaves out stays out (hidden files unless `.` shows them, `.git`, and what a `.gitignore`, `.ignore` or `.fdignore` excludes), and so do other disks under the folder. It stops at 2000 files: type more to narrow it.
- The grid's thumbnails (pictures, a PDF's first page, a video's frame) are kept where Nautilus and the other apps keep theirs (`~/.cache/thumbnails`), so each is drawn once and shared with them. Video frames need ffmpeg.
- The trash is the one Nautilus and `gio trash` use (a USB stick's stays on the stick). `d` asks before anything goes to it, a drop on Trash too (Undo brings it back), and says so when home's own folders (Documents…), the sidebar's or home's hidden ones (`.config`…) are among them; home itself, the folders above it and the trash never go. In it, `u` puts the picked files back where they were, `d` deletes them for good after asking, and ⌘⇧⌫ or Empty empties it.

## Open and Save

Files can be the apps' Open and Save window, in place of GTK's: `files picker on` (`off` gives GTK's back, `status`
says which, `remove` takes Files out of the portal). It is Files as it is, keys, sidebar and preview, with a bar at the foot: Save's name (picked without its
ending; a name that is there asks before replacing it, a folder's name goes into it), the app's file types (⌘T, or the
button; a new type changes the name's ending), Cancel (Esc) and the app's button (⏎). Open takes the marked files, else
the picked one, or a folder when the app asks for one. It floats over the app that asked and keeps the keyboard until
it closes (the launcher and the bar's menus still take it).

- Apps that ask the desktop's portal get it: Brave and Chromium, Flatpak apps. While it is on, apps started from then on ask it too: GTK 4 (zenity: Nightdrive's own pickers, Ferry) through `GDK_DEBUG=portals`, GTK 3 and Firefox through `GTK_USE_PORTAL=1`; apps already open keep GTK's until they start again, the launcher's until a new login. Qt apps and LibreOffice draw their own.
- When Files' window doesn't come up in 5 s, or closes without an answer, GTK's opens with the same request, so a save never hangs.
- The first `on`, and `remove`, start the desktop's portal (xdg-desktop-portal) again, which cuts what is open on it: screen sharing stops, and Lan Mouse gives the mouse and keyboard back. They list those apps first and ask (`--yes` to go ahead without a terminal). `off` and `on` after that are instant: when off, Files' backend hands each request to GTK's window.
- No root needed: it is a folder of the user's (`~/.local/share/nightdrive/portals`), named to xdg-desktop-portal by a drop-in of its unit. `remove` takes them away. `lib/portal-try` tries it first on a portal of its own, leaving the desktop's as it is.

## In a terminal

    files                        # a new window, home
    files ~/Projects             # a folder in a new window; a file shows in its folder, picked
    files enable                 # Files opens folders for the desktop (the installer runs it)
    files disable                # folders open in Nautilus again, under its own name
    files picker on              # Files as the apps' Open and Save window (off: GTK's again; remove; status [--json])

Needs: nothing to set up (Python, GObject, GdkPixbuf, wl-clipboard, poppler-utils and fd-find, which its installer adds)
