import QtQuick
import Quickshell
import Quickshell.Io

// The window's side of bin/vm-ctl: the list of VMs (refreshed every few seconds, so a VM shut down from inside shows as
// stopped) and one call at a time for the buttons. Each call's output comes back to its callback; a failure's text is
// kept in `error` for the page to show.
QtObject {
    id: root
    readonly property string ctl: Quickshell.shellDir + "/../bin/vm-ctl"
    property var vms: []
    property bool busy: false
    property string error: ""

    function refresh() { if (!lister.running) lister.running = true }

    // run(["start", "fedora"], out => …): queued behind a call still running, since the buttons rarely overlap
    property var queue: []
    function run(args, done) {
        queue = queue.concat([{ args: args, done: done }])
        next()
    }
    function next() {
        if (caller.running || queue.length === 0) return
        const job = queue[0]
        queue = queue.slice(1)
        caller.done = job.done || null
        caller.command = [ctl].concat(job.args)
        busy = true
        error = ""
        caller.running = true
    }

    property Process lister: Process {
        command: [root.ctl, "list"]
        stdout: StdioCollector {
            onStreamFinished: { try { root.vms = JSON.parse(text) } catch (e) { root.error = "vm-ctl list: " + text } }
        }
    }

    property Process caller: Process {
        property var done: null
        stdout: StdioCollector { id: out }
        stderr: StdioCollector { id: err }
        onExited: code => {
            root.busy = false
            if (code !== 0) root.error = err.text.trim() || ("vm-ctl failed (" + code + ")")
            else if (done) done(out.text)
            root.refresh()
            root.next()
        }
    }

    property Timer poll: Timer { interval: 3000; running: true; repeat: true; triggeredOnStart: true; onTriggered: root.refresh() }
}
