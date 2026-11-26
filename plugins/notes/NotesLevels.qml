import QtQuick
import Quickshell
import qs

// Notes' part of the launcher (plugin-parts lists it while the plugin is on): the root search finds notes by title,
// folder or #tag (rootRows), and Enter opens one in Notes' window; "New note" opens the window on a new one to write in.
// `notes list --json` (lib/notes.py) gives them, read on every open of the launcher. Settings › Launcher › Include notes
// turns the notes off (New note stays: it is a command, not your text).
// Launcher.qml asks it like its own level files (levels, titles, parents, items, activate, footer, entered); it has no
// levels of its own, as a note's place is its window.
Item {
    id: m
    property var launcher: null               // Launcher.qml sets it once the file is loaded

    readonly property string cmdPath: Qt.resolvedUrl("bin/notes").toString().replace(/^file:\/\//, "")
    property var notes: []                    // [{ id, title, folder, tags }]

    readonly property var levels: []
    readonly property var titles: ({})
    readonly property var parents: ({})

    function opened() { listProc.running = true }
    function entered(level) {}
    function footer(level, query) { return "" }
    function items(level, q) { return [] }
    function shiftActivate(it) {}

    // Found by searching only: a note's title is matched first, its folder and tags after it. A note in a folder says
    // so on its row, as the same title may be in two folders.
    function rootRows() {
        const rows = [{ item: { kind: "notenew", name: "New note", glyph: "notebook-pen", from: "Notes",
                                footer: "Enter: a new note in Notes, its title first" },
                        text: "New note", extra: "notes write create add memo" }]
        if (launcher.prefs.notes === false) return rows
        return rows.concat(notes.map(n => ({
            item: { kind: "note", name: n.title, glyph: "file-text", from: "Notes", id: n.id,
                    summary: n.folder || undefined, footer: "Enter: open in Notes" },
            text: n.title,
            extra: [n.folder].concat((n.tags || []).map(t => "#" + t)).join(" ")
        })))
    }

    function activate(it) {
        if (it.kind === "note") { launcher.open = false; Quickshell.execDetached([cmdPath, "show", it.id]); return true }
        if (it.kind === "notenew") { launcher.open = false; Quickshell.execDetached([cmdPath, "new"]); return true }
        return false
    }

    Sh {
        id: listProc
        command: [m.cmdPath, "list", "--json", "--limit", "0"]
        onResult: text => {
            try { m.notes = (JSON.parse(text).notes || []).map(n => ({ id: n.id, title: n.title, folder: n.folder, tags: n.tags })) }
            catch (e) { m.notes = [] }
        }
    }
}
