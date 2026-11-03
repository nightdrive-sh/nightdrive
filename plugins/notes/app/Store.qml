import QtQuick
import Quickshell
import Quickshell.Io

// The notes as `notes list` gives them (lib/notes.py, newest first), with the folders and tags (lib/folders.py), and the
// open one's text, read from its file. The list is read again every few seconds (shell.qml's timer) and at once when the
// notes command changed something (its `ipc refresh`); the open note's file is watched, so a save in Apostrophe shows at
// once. The folder or tag picked in the sidebar (NavSidebar.qml) narrows what shows: a folder with what is under it, a
// tag with the tags nested in it, as `notes list --folder/--tag` has them.
Item {
    id: store
    property var notes: []
    property var folders: []                   // { path, name, depth, own, count }, empty ones too
    property var tags: []                      // { name, count }
    // The sidebar's pick: one folder ("" the top, with everything) or one tag, never both
    property string scopeFolder: ""
    property string scopeTag: ""
    readonly property string scopeName: scopeTag ? "#" + scopeTag : scopeFolder ? scopeFolder.split("/").pop() : "All notes"
    function under(folder, sub) { return !folder || sub === folder || sub.startsWith(folder + "/") }
    function tagged(n, tag) {
        const want = tag.toLowerCase()
        return (n.tags || []).some(t => t.toLowerCase() === want || t.toLowerCase().startsWith(want + "/"))
    }
    function inScope(n) { return under(scopeFolder, n.folder || "") && (!scopeTag || tagged(n, scopeTag)) }
    // Picking one shows its newest note, unless the one open is in it; an empty folder shows none
    function pickFolder(f) { scopeTag = ""; scopeFolder = f; keepInScope() }
    function pickTag(t) { scopeFolder = ""; scopeTag = t; keepInScope() }
    function keepInScope() { if (index < 0) picked = shown.length ? shown[0].id : "" }
    property bool loaded: false
    property string folder: "~/Notes"
    property string error: ""
    property string picked: ""                 // the open note's id
    // A search's notes (NoteSearch.found), null without one: the list shows them instead, and the keys move in them
    property var found: null
    readonly property var shown: (found !== null ? found : notes).filter(inScope)
    readonly property int index: shown.findIndex(n => n.id === picked)     // in shown: -1 when a search left it out
    readonly property var note: notes.find(n => n.id === picked) || null
    property string text: ""                   // the open note's Markdown, as its file has it now
    property string textId: ""                 // whose text that is: "" until the picked note's file has been read
    readonly property string root: Quickshell.env("NOTES_DIR") || Quickshell.env("HOME") + "/Notes"   // as lib/store.py's
    // The plugin's own command, by its path: the compositor's PATH may not have ~/.local/bin
    readonly property string command: Quickshell.shellDir + "/../bin/notes"
    // The open note's file read again, as it is (a save that failed changed nothing for the watch to see)
    function reread() { file.reload() }
    function edit() { if (note) Quickshell.execDetached([command, "edit", note.id]) }

    function refresh() { if (!lister.running) lister.running = true; else again = true }
    property bool again: false
    property string raw: ""                    // the last list's JSON as it came
    // A note just made (New: notes create's answer, its text included) shows at once, before the list is read again;
    // drop() takes it out again when it was left empty, back to the note shown before it
    property string before: ""
    function add(note) {
        before = picked
        if (scopeTag) pickFolder(note.folder || "")      // in a tag the new note (without it yet) wouldn't show
        notes = [note].concat(notes.filter(n => n.id !== note.id))
        if (found !== null) found = [note].concat(found)      // shown while a search is on too, as the note written in
        picked = note.id
        raw = ""
        refresh()
    }
    function drop(id) {
        notes = notes.filter(n => n.id !== id)
        if (found !== null) found = found.filter(n => n.id !== id)
        if (picked === id) picked = notes.some(n => n.id === before) ? before : notes.length ? notes[0].id : ""
        raw = ""
    }

    // New: `notes create --json TITLE`, its stdin empty, or without a title `--untitled` ("Untitled.md", its text "# ",
    // the title written in it), in the folder picked; then gets the new note, failed notes.py's words. A tag picked
    // isn't written in for the user: the note shows all the same while it is being written (add), and leaves the
    // list if it doesn't get the tag.
    function create(title, then, failed) {
        if (creator.running) return
        creator.then = then
        creator.failed = failed
        creator.command = [command, "create", "--json", "--folder", scopeFolder, title || "--untitled"]
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
        const i = shown.findIndex(n => n.id === id)
        notes = notes.filter(n => n.id !== id)
        if (found !== null) found = found.filter(n => n.id !== id)
        // Not one outside the folder or tag shown: a folder left empty shows no note
        if (picked === id) picked = i >= 0 && shown.length ? shown[Math.min(i, shown.length - 1)].id
            : notes.length && !scopeFolder && !scopeTag ? notes[0].id : ""
        raw = ""
        refresh()
    }
    // Renamed or put back here: shown as soon as the list has it (the next read, at once)
    function follow(id) { picked = id; raw = ""; refresh() }

    function step(d) { const n = shown.length; if (n) picked = shown[Math.max(0, Math.min(n - 1, index + d))].id }

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
                    store.folders = r.folders
                    store.tags = r.tags
                    store.folder = r.folder
                    // A folder gone (Files) or a tag no note has any more: back to every note
                    if (store.scopeFolder && !r.folders.some(f => f.path === store.scopeFolder)) store.scopeFolder = ""
                    if (store.scopeTag && !r.tags.some(t => t.name.toLowerCase() === store.scopeTag.toLowerCase()))
                        store.scopeTag = ""
                    store.error = ""
                } catch (e) {
                    store.error = "The notes couldn't be read: " + e
                }
                store.loaded = true
                // The open note gone (trashed): the newest of those shown instead (none in an empty folder)
                if (!store.note && store.shown.length) store.picked = store.shown[0].id
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
