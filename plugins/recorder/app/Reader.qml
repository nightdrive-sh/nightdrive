import QtQuick
import Quickshell.Io

// A command whose JSON answer is read again and again (Store's status and list): again() runs it, or once more after
// the run going on, so a refresh asked for meanwhile isn't lost and two never run at once.
Process {
    id: r
    signal read(var data)
    signal failed(string text)
    property bool pending: false
    function again() { if (running) pending = true; else running = true }
    stdout: StdioCollector { id: out }
    stderr: StdioCollector { id: err }
    onExited: code => {
        if (code === 0) { try { r.read(JSON.parse(out.text)) } catch (e) { r.failed("Unreadable answer: " + e) } }
        else r.failed(err.text.trim() || "recorder failed")
        if (pending) { pending = false; running = true }
    }
}
