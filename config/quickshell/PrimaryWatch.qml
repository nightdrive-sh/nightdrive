pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

// When the primary selection (the selected text) last changed, and in which window: a selection stays on offer long after
// it's gone from the screen, so Claude writes (ClaudeWrite.qml) and Send to Claude (SendClaudeLevels.qml) count only
// one made in the last minute, in the window their key was pressed in. The text itself isn't kept.
// ClaudeWrite binds to it, so the watch starts with the shell, not on the first key press.
Singleton {
    id: p
    readonly property int freshMs: 60000   // a selection older than this is an old one
    property real at: 0
    property string addr: ""               // Hyprland's address without 0x

    // A selection made in the last minute in this window (an address with or without 0x)
    function fresh(windowAddr) { return Date.now() - at < freshMs && addr === String(windowAddr || "").replace(/^0x/, "") }

    // Every change of the primary selection, as a line. The text is read only so the app isn't left writing into a
    // closed pipe, and goes nowhere
    Process {
        id: watch
        property real started: 0
        command: ["wl-paste", "--primary", "--watch", "sh", "-c", "cat >/dev/null; echo"]
        running: true
        onStarted: started = Date.now()
        onExited: rewatch.start()
        stdout: SplitParser {
            onRead: {
                // wl-paste reports the selection that's already there when it starts: that one is old
                if (Date.now() - watch.started < 1000) return
                p.at = Date.now()
                p.addr = Hyprland.activeToplevel ? String(Hyprland.activeToplevel.address).replace(/^0x/, "") : ""
            }
        }
    }
    Timer { id: rewatch; interval: 5000; onTriggered: watch.running = true }
}
