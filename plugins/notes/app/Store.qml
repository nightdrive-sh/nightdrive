import QtQuick
import Quickshell
import Quickshell.Io

// The notes as `notes list` gives them (lib/notes.py, newest first), and the open one's text, read from its file. The
// list is read again every few seconds (shell.qml's timer) and at once when the notes command changed something (its
// `ipc refresh`); the open note's file is watched, so a save in Apostrophe shows at once.
Item {
    id: store
    property var notes: []
    property bool loaded: false
    property string folder: "~/Notes"
    property string error: ""
    property string picked: ""                 // the open note's id
    readonly property int index: notes.findIndex(n => n.id === picked)
    readonly property var note: index >= 0 ? notes[index] : null
    property string text: ""                   // the open note's Markdown, as its file has it now
    readonly property string root: Quickshell.env("NOTES_DIR") || Quickshell.env("HOME") + "/Notes"   // as lib/store.py's
    // The plugin's own command, by its path: the compositor's PATH may not have ~/.local/bin
    readonly property string command: Quickshell.shellDir + "/../bin/notes"
    function edit() { if (note) Quickshell.execDetached([command, "edit", note.id]) }

    function refresh() { if (!lister.running) lister.running = true; else again = true }
    property bool again: false
    property string raw: ""                    // the last list's JSON as it came
    function step(d) { const n = notes.length; if (n) picked = notes[Math.max(0, Math.min(n - 1, index + d))].id }

    Process {
        id: lister
        command: [store.command, "list", "--json", "--limit", "0"]
        stdout: StdioCollector {
            onStreamFinished: {
                // The same list again (the window's timer) changes nothing, so the rows and their scroll stay
                if (text === store.raw) return
                store.raw = text
                try {
                    const r = JSON.parse(text)
                    store.notes = r.notes
                    store.folder = r.folder
                    store.error = ""
                } catch (e) {
                    store.error = "The notes couldn't be read: " + e
                }
                store.loaded = true
                // The open note gone (trashed): the newest shows instead
                if (store.index < 0 && store.notes.length) store.picked = store.notes[0].id
            }
        }
        stderr: StdioCollector { onStreamFinished: if (text.trim()) store.error = text.trim() }
        onExited: if (store.again) { store.again = false; running = true }
    }

    FileView {
        id: file
        path: store.note ? store.root + "/" + store.note.id : ""
        watchChanges: true
        printErrors: false
        onPathChanged: store.text = ""
        onLoaded: store.text = text()
        onFileChanged: { reload(); store.refresh() }   // its title, date and place in the list may change too
    }

    Component.onCompleted: refresh()
}
