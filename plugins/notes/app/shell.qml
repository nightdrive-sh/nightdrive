import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs
import qs.kit

// Notes, Nightdrive's window for the Markdown notes in ~/Notes: the folders and tags (NavSidebar), the notes in the one
// picked, newest first (NoteList), and the open one, to read or to write in (NoteEditor, Enter). Apostrophe still opens
// one (⇧Enter), and Claude writes through the notes command (mcp.json). This file holds the window together: the narrow
// window's turns, the IPC, the reading keys (their sheet: KeyHelp.qml) and quitting once what was written is saved.
ShellRoot {
    FloatingWindow {
        id: win
        title: "Notes"
        implicitWidth: 900
        implicitHeight: 620
        color: c.bg
        onClosed: win.quit()

        AppLook { id: c }
        Store { id: store }
        NoteSearch {
            id: search
            command: store.command
            onFoundChanged: store.found = found
            // The note shown is one it found: the first, unless the one shown already is
            onArrived: if (found.length && store.index < 0) win.pick(found[0].id)
        }
        // The notes changed (a save, Claude, another app): the search's answer may have too
        Connections { target: store; function onRawChanged() { if (search.active && store.raw) search.run() } }
        NoteActions { id: actions; command: store.command }
        NoteDrag { id: drag; c: win.look; sidebar: nav; onDropped: (id, folder) => win.moveNote(id, folder) }
        KeyHelp { id: keyHelp }
        readonly property QtObject look: c

        // The list is read again every few seconds: Apostrophe, Files or a sync may add, rename or remove a note
        // meanwhile, and Quickshell has no folder watcher (the open note's own file is watched: Store.qml)
        Timer { interval: 5000; running: true; repeat: true; onTriggered: store.refresh() }

        // Narrow windows, as Mail's: below navMin the folders and tags hide (f or the list's button shows them), and
        // below onePaneMax the list and the note take turns, as in Garage: Esc on the note shows the list, a click or
        // Enter on a note the note; there f shows the folders in the list's place. ⌘B shows and hides the sidebars.
        readonly property int navMin: 960
        readonly property int onePaneMax: 620
        readonly property bool onePane: width < onePaneMax
        property var sidebarChoice: null            // ⌘B's, in a wide window
        property var navChoice: null                // f's, over what the width says
        property bool listOpen: false               // in one pane: the list shows instead of the note
        property bool navOpen: false                // in one pane, with the list open: the folders show instead of it
        readonly property bool sidebarShown: onePane ? listOpen && !navOpen : sidebarChoice !== null ? sidebarChoice : true
        readonly property bool navShown: onePane ? listOpen && navOpen
            : sidebarShown && (navChoice !== null ? navChoice : width >= navMin)
        onOnePaneChanged: { listOpen = false; navOpen = false }
        function toggleSidebar() { if (onePane) { listOpen = !listOpen; navOpen = false } else sidebarChoice = !sidebarShown }
        // f: the folders and tags shown and the keys in them (NavSidebar's), or back to the notes; hidden again on the
        // way back only if f showed them
        property bool navForKeys: false
        function toFolders() {
            if (nav.activeFocus) return fromFolders()
            if (!view.leave()) return
            navForKeys = !navShown
            if (onePane) { listOpen = true; navOpen = true }
            else if (navForKeys) { sidebarChoice = true; navChoice = true }
            nav.forceActiveFocus()
        }
        function fromFolders() {
            if (onePane) navOpen = false
            else if (navForKeys) navChoice = null
            navForKeys = false
            view.forceActiveFocus()
        }
        // Another note leaves the one being written, saved (not with a conflict to settle: NoteView.leave)
        function pick(id) { if (!view.leave()) return; store.picked = id; listOpen = false; navOpen = false; view.home() }
        function step(d) { if (!view.leave()) return; store.step(d); view.home() }

        // Search (/, ⌘F): the field in the sidebar, shown first if it was hidden; the note being written left, saved.
        // ⏎ or ↓ there goes to the notes found (the keys move in them), Esc ends the search: every note again.
        function find() {
            if (!view.leave()) return
            if (onePane) listOpen = true; else sidebarChoice = true
            list.field.forceActiveFocus()
        }
        function searchDone(clear) {
            if (clear) { list.field.text = ""; search.query = "" }
            if (onePane && !clear && store.note) listOpen = false
            view.forceActiveFocus()
        }

        // New (n, ⌘N, `notes new [TITLE]`): no question first. Without a title the note is "Untitled.md" with "# " in
        // it and the cursor after it, so its title is the first thing written, and its file is named after it once it
        // is left (refile). The note being written is left first, saved; one left empty on its own goes then
        // (NoteEditor).
        function newNote(title) {
            if (!view.leave()) return
            if (namePanel.visible) namePanel.answer(false)     // a rename being asked
            store.create(title.trim(), note => { win.listOpen = false; view.home(); view.editNew(note) }, win.failed)
        }

        // Rename (F2, r), Trash (Delete, ⌘⌫) and refile act on the file, so they wait for what was written to be saved:
        // the editor is left first (with a conflict unsettled, not at all), and whenSaved runs them in turn, each once
        // no save and no change before it is running
        property var queue: []
        function whenSaved(fn) { queue.push(fn); next() }
        function next() {
            if (view.busy || actions.running) return
            const fn = queue.shift()
            if (fn) { fn(); next() }
            else if (quitting) Qt.quit()
        }
        function failed(message) { toast.show(message, { danger: true }) }
        // A note left in the editor: its file named after its title now, if it was named after the one it had
        // (a new note's "Untitled.md" too). Shown under its new id if it is still the one shown.
        function refile(id, was) {
            whenSaved(() => actions.refile(id, was, r => {
                if (!r.renamed) return
                if (store.picked === r.old_id) store.follow(r.id)
                else store.refresh()
            }, win.failed))
        }
        // Rename and Trash leave the editor without refile: the file is renamed or gone next anyway
        function renameNote() {
            if (!view.leave(false) || !store.note) return
            const id = store.note.id, title = store.note.title
            namePanel.ask("New title", title, t => {
                if (t && t !== title) win.whenSaved(() => actions.rename(id, t, r => {
                    store.follow(r.id)
                    if (r.renamed) toast.show("Renamed to " + r.title, { action: "Undo", run: () => win.unrename(r) })
                }, win.failed))
            })
        }
        // Move (m, a drag onto a folder): the note into the folder ("" the top; one not there yet is made). Moved out of
        // the folder or tag shown, the open one gives way to the note below it, as when trashed; Undo moves it back.
        function moveNote(id, folder) {
            if (id === store.picked && !view.leave(false)) return
            win.whenSaved(() => actions.move(id, folder, r => {
                if (!r.moved) return
                if (store.under(store.scopeFolder, r.folder) && store.picked === id) store.follow(r.id)
                else if (store.picked === id) store.forget(id)
                else store.refresh()
                toast.show("Moved " + r.title + " to " + (r.folder || "Notes"), { action: "Undo", run: () =>
                    actions.unmove(r, back => store.follow(back.id), win.failed) })
            }, win.failed))
        }
        function askMove() {
            if (!view.leave(false) || !store.note) return
            const id = store.note.id
            movePanel.ask(store.note, folder => win.moveNote(id, folder))
        }
        // New folder (+ by the sidebar's title): in the folder picked, shown at once
        function newFolder() {
            const inside = store.scopeTag ? "" : store.scopeFolder
            namePanel.ask(inside ? "New folder in " + inside : "New folder", "", name => {
                if (name) actions.mkdir(inside ? inside + "/" + name : name, r => {
                    store.pickFolder(r.path); store.raw = ""; store.refresh()
                }, win.failed)
            })
        }
        // An empty one only (notes rmdir refuses the rest); Undo makes it again
        function removeFolder(path) {
            actions.rmdir(path, r => {
                store.pickFolder(path.includes("/") ? path.slice(0, path.lastIndexOf("/")) : "")
                store.raw = ""; store.refresh()
                toast.show("Removed the folder " + path, { action: "Undo", run: () =>
                    actions.mkdir(path, () => { store.pickFolder(path); store.raw = ""; store.refresh() }, win.failed) })
            }, win.failed)
        }
        function pickTag(tag) { store.pickTag(tag); if (onePane) { listOpen = true; navOpen = false } }

        function unrename(r) { actions.unrename(r, back => store.follow(back.id), win.failed) }
        // No question first: the trash keeps it, and the toast's Undo (⌘Z) puts it back
        function trashNote() {
            if (!view.leave(false) || !store.note) return
            const id = store.note.id
            win.whenSaved(() => actions.trash(id, r => {
                store.forget(id)
                toast.show("Moved " + r.title + " to the trash", { action: "Undo", run: () =>
                    actions.restore(r.names, () => store.follow(id), win.failed) })
            }, win.failed))
        }

        // What was written is saved before Notes goes: the note left as Esc leaves it (saved, refiled, or gone if
        // a new one is empty), or with a conflict unsettled, its text kept aside (NoteEditor.flush); then what is
        // still running or waiting (next)
        property bool quitting: false
        function quit() { quitting = true; if (!view.leave()) view.flush(true); next() }
        Connections { target: view; function onBusyChanged() { win.next() } }
        Connections { target: actions; function onRunningChanged() { win.next() } }
        // A save that never answers (notes.py stuck): gone after a moment all the same; --md5 keeps a cut one out
        Timer { running: win.quitting; interval: 5000; onTriggered: Qt.quit() }

        IpcHandler {
            target: "notes"
            function refresh(): void { store.refresh() }
            function pick(id: string): void { win.pick(id); store.refresh() }
            function newNote(title: string): void { win.newNote(title) }
            // `notes find [WORDS]`: the search, its words given or to type
            function find(words: string): void { win.find(); list.field.text = words; search.query = words }
        }

        // While writing, ⌘B is bold (EditorHelp.qml)
        Shortcut { sequences: ["Ctrl+B", "Meta+B"]; enabled: !view.editing; onActivated: win.toggleSidebar() }
        Shortcut { sequence: "Ctrl+Q"; onActivated: win.quit() }
        Shortcut { sequences: ["Ctrl+N", "Meta+N"]; enabled: !namePanel.visible && !movePanel.visible; onActivated: win.newNote("") }
        Shortcut { sequence: "F2"; enabled: !namePanel.visible && !movePanel.visible; onActivated: win.renameNote() }
        Shortcut { sequences: ["Ctrl+F", "Meta+F"]; enabled: !namePanel.visible && !movePanel.visible; onActivated: win.find() }

        RowLayout {
            id: content
            anchors.fill: parent
            spacing: 0
            AppPointer { c: win.look }      // the pointer hides the keys' frame

            NavSidebar {
                id: nav
                visible: win.navShown
                Layout.preferredWidth: win.onePane ? -1 : win.width < 1100 ? 180 : 210
                Layout.fillWidth: win.onePane
                z: 1                        // a folder's tip lies over the list
                c: win.look
                store: store
                active: activeFocus
                onNewFolder: win.newFolder()
                onRemoveFolder: path => win.removeFolder(path)
                onDone: win.fromFolders()
                onChosen: if (win.onePane) win.navOpen = false
            }
            NoteList {
                id: list
                visible: win.sidebarShown
                showNew: win.onePane
                navShown: win.navShown
                drag: drag
                onShowNav: win.toFolders()
                onNewNote: win.newNote("")
                Layout.preferredWidth: win.onePane ? -1 : win.navShown && win.width < 1100 ? 250 : 280
                Layout.fillWidth: win.onePane
                c: win.look
                store: store
                search: search
                onSearchDone: clear => win.searchDone(clear)
                active: view.activeFocus
                onPicked: id => win.pick(id)
            }
            // While the list shows in one pane the note is there at no width: it keeps the keyboard, so the arrows still
            // move between the notes, as in Garage
            NoteView {
                id: view
                Layout.preferredWidth: win.onePane && win.listOpen ? 0 : -1
                Layout.fillWidth: !(win.onePane && win.listOpen)
                Layout.fillHeight: true
                clip: true
                c: win.look
                store: store
                onePane: win.onePane
                marks: search.words
                focus: true
                onBack: if (view.leave()) { win.listOpen = true; win.navOpen = false }
                onNewNote: win.newNote("")
                onRename: win.renameNote()
                onTrash: win.trashNote()
                onWroteIn: (id, was) => win.refile(id, was)
                onTagPicked: tag => win.pickTag(tag)
                onMessage: (text, danger) => toast.show(text, { danger: danger })

                Keys.onPressed: e => {
                    const k = e.key, shift = e.modifiers & Qt.ShiftModifier
                    win.look.moved(e)              // Tab and the arrows show the keys' frame (AppPointer)
                    sheet.pressed(e)
                    // Writing: the editor has the keys, and what it lets through (an arrow at the text's end) isn't a reading key
                    if (e.accepted || view.editing) return
                    if (k === Qt.Key_Down || k === Qt.Key_J) win.step(1)
                    else if (k === Qt.Key_Up || k === Qt.Key_K) win.step(-1)
                    else if (k === Qt.Key_Home && store.shown.length) win.pick(store.shown[0].id)
                    else if (k === Qt.Key_End && store.shown.length) win.pick(store.shown[store.shown.length - 1].id)
                    else if (e.text === "/") win.find()
                    else if (e.text === "n") win.newNote("")
                    else if (e.text === "r") win.renameNote()
                    else if (e.text === "m") win.askMove()
                    else if (e.text === "f") win.toFolders()
                    else if (k === Qt.Key_Delete || (k === Qt.Key_Backspace && (e.modifiers & (Qt.ControlModifier | Qt.MetaModifier))))
                        win.trashNote()
                    else if (k === Qt.Key_Z && (e.modifiers & (Qt.ControlModifier | Qt.MetaModifier)) && toast.act()) {}
                    else if (k === Qt.Key_Space) view.scroll((shift ? -1 : 1) * (view.height - 120))
                    else if (k === Qt.Key_PageDown) view.scroll(view.height - 120)
                    else if (k === Qt.Key_PageUp) view.scroll(-(view.height - 120))
                    else if (win.onePane && win.listOpen && (k === Qt.Key_Return || k === Qt.Key_Enter)) win.listOpen = false
                    else if ((k === Qt.Key_Return || k === Qt.Key_Enter) && shift) store.edit()
                    else if (k === Qt.Key_Return || k === Qt.Key_Enter || e.text === "e") view.edit()
                    else if (win.onePane && !win.listOpen && k === Qt.Key_Escape && store.notes.length) win.listOpen = true
                    else if (k === Qt.Key_Escape && search.active) win.searchDone(true)
                    else return
                    e.accepted = true
                }
            }
        }

        AppPrompt {
            id: namePanel
            behind: content
            c: win.look
            cardWidth: Math.min(440, win.width - 32)      // a narrow window: the card inside it
            onClosed: if (!view.editing) view.forceActiveFocus()
        }

        MovePanel {
            id: movePanel
            behind: content
            c: win.look
            store: store
            cardWidth: Math.min(440, win.width - 32)
            onClosed: if (!view.editing) view.forceActiveFocus()
        }

        KeySheet { id: sheet; c: win.look; groups: keyHelp.groups }
        AppToast { id: toast; c: win.look }
    }
}
