import QtQuick
import Quickshell.Io
import "Format.js" as Format

// The search of all of home, or outside it of the folder on show and below (the filter's other scope: Tab, ⌘F again,
// or f in the list; FilesWindow.searchRoot): lib/search.py runs
// fd and prints the rows in batches as they are found, and rows is what the list shows instead of the folder's, in the
// list's own order. A new word restarts it a moment after the last key; a folder left or the filter closed stops it.
Item {
    id: root
    required property var app
    property string folder: ""
    property string words: ""
    property bool hidden: false
    property bool on: false                  // the filter's scope is "and below"
    property var rows: []
    property bool running: false
    property bool capped: false              // search.py stopped at its LIMIT: more words would narrow it
    property bool missing: false             // no fd on this machine
    signal rebuilt()

    readonly property string helper: app.helper.replace(/cli\.py$/, "search.py")
    readonly property bool active: on && words.trim() !== ""

    onActiveChanged: restart()
    onWordsChanged: if (on) restart()
    onFolderChanged: if (on) restart()
    onHiddenChanged: if (on) restart()
    function restart() {
        proc.running = false
        found = []; rows = []; capped = false; missing = false; running = active
        if (active) later.restart(); else { later.stop(); rebuilt() }
    }
    // A key or two more is likely: one search for the lot (fd itself is quick)
    Timer { id: later; interval: 180; onTriggered: { proc.command = root.command(); proc.running = true } }
    function command() {
        const c = ["python3", "-I", helper, folder, words.trim()]
        return hidden ? c.concat(["--hidden"]) : c
    }

    // Found rows land in found as they come (their time as a Date, as Folder's rows have it); the list's order is applied a few times a second, not per batch
    property var found: []
    Timer { id: settle; interval: 120; onTriggered: root.order() }
    function order() { rows = Format.order(found, app.sortBy, app.reversed); rebuilt() }
    Connections {
        target: root.app
        function onSortByChanged() { if (root.active) root.order() }
        function onReversedChanged() { if (root.active) root.order() }
    }

    Process {
        id: proc
        stdout: SplitParser {
            onRead: line => {
                let d
                try { d = JSON.parse(line) } catch (e) { return }
                if (d.rows) { root.found = root.found.concat(d.rows.map(r => Object.assign(r, { modified: new Date(r.modified) }))); if (!settle.running) settle.start() }
                else if (d.missing) { root.missing = true; root.running = false; root.rebuilt() }
                else if (d.done) { root.capped = d.capped; root.running = false; settle.stop(); root.order() }
            }
        }
        onExited: if (root.running && !later.running) { root.running = false; root.order() }
    }
}
