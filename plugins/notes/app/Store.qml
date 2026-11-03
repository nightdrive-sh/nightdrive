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
    property string textId: ""                 // whose text that is: "" until the picked note's file has been read
    readonly property string root: Quickshell.env("NOTES_DIR") || Quickshell.env("HOME") + "/Notes"   // as lib/store.py's
    // The plugin's own command, by its path: the compositor's PATH may not have ~/.local/bin
    readonly property string command: Quickshell.shellDir + "/../bin/notes"
    function edit() { if (note) Quickshell.execDetached([command, "edit", note.id]) }

    function refresh() { if (!lister.running) lister.running = true; else again = true }
    property bool again: false
    property string raw: ""                    // the last list's JSON as it came
    // A note just made (New: notes create's answer, its text included) shows at once, before the list is read again;
    // drop() takes it out again when it was left empty, back to the note shown before it
    property string before: ""
    function add(note) {
        before = picked
        notes = [note].concat(notes.filter(n => n.id !== note.id))
        picked = note.id
        raw = ""
        refresh()
    }
    function drop(id) {
        notes = notes.filter(n => n.id !== id)
        if (picked === id) picked = notes.some(n => n.id === before) ? before : notes.length ? notes[0].id : ""
        raw = ""
    }

    // New: `notes create --json TITLE`, its stdin empty; then gets the new note, failed notes.py's words
    function create(title, then, failed) {
        if (creator.running) return
        creator.then = then
        creator.failed = failed
        creator.command = [command, "create", "--json", title]
        creator.running = true
    }
    Process {
        id: creator
        property var then: null
        property var failed: null
        stdinEnabled: true
        onStarted: stdinEnabled = false             // an empty stdin: the note is its title alone
        stdout: StdioCollector { id: created }
        stderr: StdioCollector { id: createErr }
        onExited: code => {
            let note = null
            if (code === 0) try { note = JSON.parse(created.text) } catch (e) {}
            if (note) { store.add(note); creator.then(note) }
            else creator.failed(createErr.text.trim().split("\n").pop() || "The note couldn't be made.")
            stdinEnabled = true
        }
    }

    // Trashed here: out of the list at once, the note below it (else above) shown instead
    function forget(id) {
        const i = notes.findIndex(n => n.id === id)
        if (i < 0) return
        notes = notes.filter(n => n.id !== id)
        if (picked === id) picked = notes.length ? notes[Math.min(i, notes.length - 1)].id : ""
        raw = ""
        refresh()
    }
    // Renamed or put back here: shown as soon as the list has it (the next read, at once)
    function follow(id) { picked = id; raw = ""; refresh() }

    function step(d) { const n = notes.length; if (n) picked = notes[Math.max(0, Math.min(n - 1, index + d))].id }

    Process {
        id: lister
        command: [store.command, "list", "--json", "--limit", "0"]
        stdout: StdioCollector {
            onStreamFinished: {
                // A read begun before a change here (a note made or dropped) is out of date: the next one is coming
                if (store.again) return
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
        onPathChanged: { store.textId = ""; store.text = "" }
        onLoaded: { store.text = text(); store.textId = store.picked }
        onFileChanged: { reload(); store.refresh() }   // its title, date and place in the list may change too
    }

    Component.onCompleted: refresh()
}
