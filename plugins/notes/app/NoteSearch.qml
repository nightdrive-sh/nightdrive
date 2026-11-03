import QtQuick
import Quickshell.Io

// The window's search (/, ⌘F): the notes that have every word, in the title or the text, by `notes search` (lib/notes.py),
// the same path as Claude's notes_search, so the window and Claude find the same notes. found is its answer, newest
// first, each with the lines where the words are (lines); null while there is no search, and the list shows every note.
// Run again as the words change (a moment after the last key) and when the notes do (shell.qml), one search at a time.
Item {
    id: root
    required property string command          // the plugin's bin/notes, by its path
    property string query: ""
    property var found: null
    property string error: ""
    readonly property bool active: query.trim() !== ""
    // The words, lower case, for marking them in the note (Markdown.mark): as notes.py splits them
    readonly property var words: active ? query.toLowerCase().split(/\s+/).filter(w => w) : []
    signal arrived()                          // a new answer in found

    readonly property int typingDelay: 150    // ms after the last key: a search per word, not per letter

    function run() {
        if (!active) { found = null; error = ""; return }
        if (proc.running) { again = true; return }
        proc.asked = query
        // Every match (--limit 0): the list is the window's to scroll. The words as one argument: notes.py splits them
        proc.command = [command, "search", "--json", "--limit", "0", query.trim()]
        proc.running = true
    }
    property bool again: false
    onQueryChanged: delay.restart()
    Timer { id: delay; interval: root.typingDelay; onTriggered: root.run() }

    Process {
        id: proc
        property string asked: ""
        stdout: StdioCollector { id: out }
        stderr: StdioCollector { id: err }
        onExited: code => {
            // Words changed (or cleared) meanwhile: this answer is for words no longer asked
            if (root.again || proc.asked !== root.query) { root.again = false; root.run(); return }
            try {
                root.found = JSON.parse(out.text).notes
                root.error = ""
            } catch (e) {
                root.found = []
                root.error = err.text.trim().split("\n").pop() || "The search didn't work (notes log has more)."
            }
            root.arrived()
        }
    }
}
