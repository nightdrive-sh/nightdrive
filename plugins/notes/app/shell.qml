import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs
import qs.kit

// Notes, Nightdrive's window to read the Markdown notes in ~/Notes: the notes in the sidebar, newest first, the picked
// one beside it. It doesn't write: Apostrophe does (Open in Apostrophe), and Claude through the notes command
// (mcp.json). This file holds the window together: the narrow window's turns, the IPC and the keys (their sheet:
// KeyHelp.qml).
ShellRoot {
    FloatingWindow {
        id: win
        title: "Notes"
        implicitWidth: 900
        implicitHeight: 620
        color: c.bg
        onClosed: Qt.quit()

        AppLook { id: c }
        Store { id: store }
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
        function pick(id) { store.picked = id; listOpen = false; view.home() }

        IpcHandler {
            target: "notes"
            function refresh(): void { store.refresh() }
            function pick(id: string): void { win.pick(id); store.refresh() }
        }

        Shortcut { sequences: ["Ctrl+B", "Meta+B"]; onActivated: win.toggleSidebar() }
        Shortcut { sequence: "Ctrl+Q"; onActivated: Qt.quit() }

        RowLayout {
            anchors.fill: parent
            spacing: 0
            AppPointer { c: win.look }      // the pointer hides the keys' frame

            NoteList {
                visible: win.sidebarShown
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
                onBack: win.listOpen = true

                Keys.onPressed: e => {
                    const k = e.key, shift = e.modifiers & Qt.ShiftModifier
                    win.look.moved(e)              // Tab and the arrows show the keys' frame (AppPointer)
                    sheet.pressed(e)
                    if (e.accepted) return
                    if (k === Qt.Key_Down || k === Qt.Key_J) { store.step(1); view.home() }
                    else if (k === Qt.Key_Up || k === Qt.Key_K) { store.step(-1); view.home() }
                    else if (k === Qt.Key_Home && store.notes.length) win.pick(store.notes[0].id)
                    else if (k === Qt.Key_End && store.notes.length) win.pick(store.notes[store.notes.length - 1].id)
                    else if (k === Qt.Key_Space) view.scroll((shift ? -1 : 1) * (view.height - 120))
                    else if (k === Qt.Key_PageDown) view.scroll(view.height - 120)
                    else if (k === Qt.Key_PageUp) view.scroll(-(view.height - 120))
                    else if (win.onePane && win.listOpen && (k === Qt.Key_Return || k === Qt.Key_Enter)) win.listOpen = false
                    else if (k === Qt.Key_Return || k === Qt.Key_Enter || e.text === "e") store.edit()
                    else if (win.onePane && !win.listOpen && k === Qt.Key_Escape && store.notes.length) win.listOpen = true
                    else return
                    e.accepted = true
                }
            }
        }

        KeySheet { id: sheet; c: win.look; groups: keyHelp.groups }
    }
}
