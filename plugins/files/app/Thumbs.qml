import QtQuick
import Quickshell
import Quickshell.Io

// The grid's thumbnails: lib/thumbs.py finds or draws them in the freedesktop cache (~/.cache/thumbnails, shared with
// Nautilus and the others) and prints each as it is ready; got maps a file's path to its thumbnail's. Asked for the
// rows on show whenever they change (a moment later, so a folder read in parts or j held down asks once), only for
// the files not had yet; a new folder stops the last one's run. Pictures, PDFs and videos only: thumbs.py passes over
// the rest.
Item {
    id: root
    required property string helperDir   // plugins/files/lib
    property var rows: []
    property bool on: false              // the grid is on show: nothing is drawn for the list
    property string size: "large"         // thumbs.py's: large (256 px) or x-large (512)
    property var got: ({})                // path → thumbnail path, for size
    property var pending: ({})

    onRowsChanged: if (on) later.restart()
    onOnChanged: if (on) later.restart()
    onSizeChanged: { got = ({}); pending = ({}); if (on) later.restart() }

    Timer { id: later; interval: 150; onTriggered: root.ask() }
    function ask() {
        const want = rows.filter(r => !r.dir && got[r.path] === undefined).map(r => r.path)
        if (runner.running) runner.running = false
        if (!want.length) return
        runner.command = ["python3", helperDir + "/thumbs.py", size].concat(want)
        runner.running = true
    }

    // Lines come fast from the cache: the map changes a few times a second, not once per file, as each change redraws
    // every tile that reads it
    Timer { id: flush; interval: 100; onTriggered: root.apply() }
    function apply() {
        const g = Object.assign({}, got)
        for (const p in pending) g[p] = pending[p]
        pending = ({})
        got = g
    }
    Process {
        id: runner
        stdout: SplitParser {
            onRead: line => {
                let d
                try { d = JSON.parse(line) } catch (e) { return }
                root.pending[d.path] = d.thumb
                if (!flush.running) flush.start()
            }
        }
        onExited: root.apply()
    }
}
