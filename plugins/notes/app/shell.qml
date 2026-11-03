import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs
import qs.kit

// Notes, Nightdrive's window for the Markdown notes in ~/Notes: the notes in the sidebar, newest first, the picked
// one beside it, to read or to write in (NoteEditor, Enter). Apostrophe still opens one (⇧Enter), and Claude writes
// through the notes command (mcp.json). This file holds the window together: the narrow window's turns, the IPC, the
// reading keys (their sheet: KeyHelp.qml) and quitting once what was written is saved.
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
        NoteActions { id: actions; command: store.command }
        KeyHelp { id: keyHelp }
        readonly property QtObject look: c

        // The list is read again every few seconds: Apostrophe, Files or a sync may add, rename or remove a note
        // meanwhile, and Quickshell has no folder watcher (the open note's own file is watched: Store.qml)
        Timer { interval: 5000; running: true; repeat: true; onTriggered: store.refresh() }

        // Narrow windows: below onePaneMax the list and the note take turns, as in Garage: Esc on the note shows the
        // list, a click or Enter on a note the note. ⌘B shows and hides the sidebar, in a wide window too.
        readonly property int onePaneMax: 620
        readonly property bool onePane: width < onePaneMax
        property var sidebarChoice: null            // ⌘B's, in a wide window
        property bool listOpen: false               // in one pane: the list shows instead of the note
        readonly property bool sidebarShown: onePane ? listOpen : sidebarChoice !== null ? sidebarChoice : true
        onOnePaneChanged: listOpen = false
        function toggleSidebar() { if (onePane) listOpen = !listOpen; else sidebarChoice = !sidebarShown }
        // Another note leaves the one being written, saved (not with a conflict to settle: NoteView.leave)
        function pick(id) { if (!view.leave()) return; store.picked = id; listOpen = false; view.home() }
        function step(d) { if (!view.leave()) return; store.step(d); view.home() }

        // New (n, ⌘N, `notes new [TITLE]`): its title asked for unless given, the note made by notes create and written
        // in at once. The note being written is left first, saved; one left empty on its own goes then (NoteEditor).
        function newNote(title) {
            if (!view.leave()) return
            if (namePanel.visible) namePanel.answer(false)     // `notes new TITLE` while the title was being asked
            if (title.trim()) makeNote(title)
            else namePanel.ask("Title of the new note", "", t => { if (t) win.makeNote(t) })
        }
        function makeNote(title) {
            store.create(title, note => { win.listOpen = false; view.home(); view.editNew(note) },
                message => toast.show(message, { danger: true }))
        }

        // Rename (F2, r) and Trash (Delete, ⌘⌫) act on the file, so they wait for what was written to be saved: the
        // editor is left first (with a conflict unsettled, not at all), and whenSaved runs them once no save is running
        property var afterSave: null
        function whenSaved(fn) { if (view.busy) afterSave = fn; else fn() }
        function failed(message) { toast.show(message, { danger: true }) }
        function renameNote() {
            if (!view.leave() || !store.note) return
            const id = store.note.id, title = store.note.title
            namePanel.ask("New title", title, t => {
                if (t && t !== title) win.whenSaved(() => actions.rename(id, t, r => {
                    store.follow(r.id)
                    if (r.renamed) toast.show("Renamed to " + r.title, { action: "Undo", run: () => win.unrename(r) })
                }, win.failed))
            })
        }
        function unrename(r) { actions.unrename(r, back => store.follow(back.id), win.failed) }
        // No question first: the trash keeps it, and the toast's Undo (⌘Z) puts it back
        function trashNote() {
            if (!view.leave() || !store.note) return
            const id = store.note.id
            win.whenSaved(() => actions.trash(id, r => {
                store.forget(id)
                toast.show("Moved " + r.title + " to the trash", { action: "Undo", run: () =>
                    actions.restore(r.names, () => store.follow(id), win.failed) })
            }, win.failed))
        }

        // What was written is saved before Notes goes: the last keys' save, and any still running
        property bool quitting: false
        function quit() { view.flush(true); quitting = true; if (!view.busy) Qt.quit() }
        Connections {
            target: view
            function onBusyChanged() {
                if (view.busy) return
                if (win.quitting) Qt.quit()
                const fn = win.afterSave
                win.afterSave = null
                if (fn) fn()
            }
        }
        // A save that never answers (notes.py stuck): gone after a moment all the same; --md5 keeps a cut one out
        Timer { running: win.quitting; interval: 5000; onTriggered: Qt.quit() }

        IpcHandler {
            target: "notes"
            function refresh(): void { store.refresh() }
            function pick(id: string): void { win.pick(id); store.refresh() }
            function newNote(title: string): void { win.newNote(title) }
        }

        Shortcut { sequences: ["Ctrl+B", "Meta+B"]; onActivated: win.toggleSidebar() }
        Shortcut { sequence: "Ctrl+Q"; onActivated: win.quit() }
        Shortcut { sequences: ["Ctrl+N", "Meta+N"]; enabled: !namePanel.visible; onActivated: win.newNote("") }
        Shortcut { sequence: "F2"; enabled: !namePanel.visible; onActivated: win.renameNote() }

        RowLayout {
            id: content
            anchors.fill: parent
            spacing: 0
            AppPointer { c: win.look }      // the pointer hides the keys' frame

            NoteList {
                id: list
                visible: win.sidebarShown
                showNew: win.onePane
                onNewNote: win.newNote("")
                Layout.preferredWidth: win.onePane ? -1 : 280
                Layout.fillWidth: win.onePane
                c: win.look
                store: store
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
                focus: true
                onBack: if (view.leave()) win.listOpen = true
                onNewNote: win.newNote("")
                onRename: win.renameNote()
                onTrash: win.trashNote()
                onMessage: (text, danger) => toast.show(text, { danger: danger })

                Keys.onPressed: e => {
                    const k = e.key, shift = e.modifiers & Qt.ShiftModifier
                    win.look.moved(e)              // Tab and the arrows show the keys' frame (AppPointer)
                    sheet.pressed(e)
                    // Writing: the editor has the keys, and what it lets through (an arrow at the text's end) isn't a reading key
                    if (e.accepted || view.editing) return
                    if (k === Qt.Key_Down || k === Qt.Key_J) win.step(1)
                    else if (k === Qt.Key_Up || k === Qt.Key_K) win.step(-1)
                    else if (k === Qt.Key_Home && store.notes.length) win.pick(store.notes[0].id)
                    else if (k === Qt.Key_End && store.notes.length) win.pick(store.notes[store.notes.length - 1].id)
                    else if (e.text === "n") win.newNote("")
                    else if (e.text === "r") win.renameNote()
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

        KeySheet { id: sheet; c: win.look; groups: keyHelp.groups }
        AppToast { id: toast; c: win.look }
    }
}
