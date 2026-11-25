import QtQuick
import Quickshell
import Quickshell.Io

// The window's side of lib/scan.py: the places for the sidebar, a place's last scan from the cache, and a scan with its
// progress. One scan at a time: a new one stops the one running. A closer look (graft) scans a folder of the tree on
// its own, for the detail the whole place's scan folded away (walk.py).
Item {
    id: root
    readonly property string helper: Quickshell.shellDir + "/../lib/scan.py"

    property var places: []                 // [{ name, path, glyph, disk: { size, free, used }, total?, scanned?, chosen? }]
    property bool busy: scanProc.running
    property string path: ""                // what is being scanned
    property bool graft: false              // a closer look, not the place's own scan
    property real expect: 0                 // the bytes it may come to (the last scan's), 0 if unknown
    property real files: 0
    property real bytes: 0
    property string folder: ""
    property string error: ""
    // The scans come as JSON text, for the window to parse: a JS object passed through a signal's var turns into a
    // map that is copied on every read, so the tree's folders would lose who they are (and the window's changes)
    signal loaded(string path, string json) // load()'s answer: the cached scan, or ""
    signal finished(string path, string json, bool graft)

    function refreshPlaces() { placesProc.running = true }
    function remember(path) { Quickshell.execDetached(["python3", helper, "remember", path]); placesTimer.restart() }
    Timer { id: placesTimer; interval: 300; onTriggered: root.refreshPlaces() }

    function load(path) {
        cachedProc.forScan = false
        cachedProc.path = path
        cachedProc.command = ["python3", helper, "cached", path]
        cachedProc.running = true
    }

    function scan(path, graft, expect) {
        if (scanProc.running) { scanProc.stopping = true; scanProc.running = false }
        root.path = path; root.graft = !!graft; root.expect = expect || 0
        files = 0; bytes = 0; folder = path; error = ""
        scanProc.stopping = false
        scanProc.command = ["python3", helper, "scan", path].concat(expect > 0 ? [String(Math.round(expect))] : [])
        scanProc.running = true
    }
    function cancel() { if (scanProc.running) { scanProc.stopping = true; scanProc.running = false } }

    Component.onCompleted: refreshPlaces()

    Process {
        id: placesProc
        command: ["python3", root.helper, "places"]
        stdout: StdioCollector {
            onStreamFinished: { try { root.places = JSON.parse(text) } catch (e) { console.warn("scan.py places: " + e) } }
        }
    }

    Process {
        id: cachedProc
        property string path: ""
        property bool forScan: false        // read after a scan: its result
        property string asked: ""           // the path the scan was asked for (the cache's is the real path)
        property bool graft: false
        stdout: StdioCollector {
            onStreamFinished: {
                const d = text.trim()
                if (cachedProc.forScan) {
                    if (d) root.finished(cachedProc.asked, d, cachedProc.graft)
                    else root.error = "The scan's result couldn't be read"
                    if (!cachedProc.graft) root.refreshPlaces()     // the place's size in the sidebar
                } else root.loaded(cachedProc.path, d)
            }
        }
    }

    Process {
        id: scanProc
        property bool stopping: false
        stdout: SplitParser {
            onRead: line => {
                let m
                try { m = JSON.parse(line) } catch (e) { return }
                if (m.p) { root.files = m.p[0]; root.bytes = m.p[1]; root.folder = m.p[2] }
                else if (m.done) {
                    cachedProc.forScan = true; cachedProc.graft = root.graft; cachedProc.asked = root.path; cachedProc.path = m.done
                    cachedProc.command = ["python3", root.helper, "cached", m.done]
                    cachedProc.running = true
                }
            }
        }
        stderr: StdioCollector { id: err }
        onExited: code => {
            if (code !== 0 && !stopping) root.error = err.text.trim().split("\n").pop() || "The scan stopped (" + code + ")"
        }
    }
}
