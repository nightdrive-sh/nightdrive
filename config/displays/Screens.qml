import QtQuick
import Quickshell
import Quickshell.Io

// The screens and their arrangement, as hypr/scripts/arrange gives them (--json), and the changes, which it saves and
// applies (Hyprland reloads) and answers with the new arrangement. One change at a time: one asked for while another
// runs waits, and only the last such waits (a drag dropped twice quickly ends where it was dropped last).
Item {
    id: root
    property var screens: []          // [{ id, key, name, kind, w, h, x, y, on, note, away, main }]
    property bool loaded: false
    property string error: ""
    readonly property bool busy: proc.running
    readonly property var desk: screens.filter(s => !s.away)
    readonly property var away: screens.filter(s => s.away)
    property var waiting: null
    signal changed()                  // a change came back applied

    readonly property string cmd: Quickshell.env("HOME") + "/.config/hypr/scripts/arrange"

    function byId(id) { return screens.find(s => s.id === id) || null }
    function refresh() { if (!proc.running) run([]) }
    function move(id, x, y) { run(["move", id, String(Math.round(x)), String(Math.round(y))]) }
    function step(id, side) { run(["step", id, side]) }
    function putAway(id) { run(["away", id]) }
    function bringBack(id) { run(["side", id, "right"]) }
    function makeMain(id) { run(["main", id]) }

    function run(args) {
        if (proc.running) { if (args.length) waiting = args; return }
        proc.isChange = args.length > 0
        proc.command = [cmd, "--json", ...args]
        proc.running = true
    }

    Process {
        id: proc
        property bool isChange: false
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.screens = JSON.parse(text).screens
                    root.loaded = true
                    if (proc.isChange) { root.error = ""; root.changed() }
                } catch (e) {}
            }
        }
        stderr: StdioCollector { onStreamFinished: if (text.trim() !== "") root.error = text.trim().replace(/^arrange: /, "") }
        onRunningChanged: if (!running && root.waiting) { const a = root.waiting; root.waiting = null; root.run(a) }
    }

    // A screen that comes or goes (a lid, a device connecting) shows by itself
    Timer { interval: 3000; repeat: true; running: true; onTriggered: root.refresh() }
    Component.onCompleted: refresh()
}
