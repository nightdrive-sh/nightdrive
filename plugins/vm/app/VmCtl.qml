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
    property bool loaded: false     // the first list has come: until then no VMs doesn't mean there are none
    property bool busy: false
    property string error: ""

    function refresh() { if (!lister.running) lister.running = true }

    // A VM on its way up or down, by name: { what: "starting" | "stopping", since }, until the list shows it there, so the
    // page can say so meanwhile. A shutdown the guest ignores (ACPI, with KDE logged in) gives up after stopWait.
    readonly property int stopWait: 90000
    property var pending: ({})
    function setPending(name, what) {
        const p = Object.assign({}, pending)
        if (what) p[name] = { what: what, since: Date.now() }; else delete p[name]
        pending = p
    }
    function power(action, name) {
        setPending(name, action === "start" ? "starting" : "stopping")
        run([action, name], null, () => setPending(name, ""))
    }
    function settle() {
        for (const name in pending) {
            const v = vms.find(x => x.name === name), p = pending[name]
            if (!v || v.running === (p.what === "starting")) setPending(name, "")
            else if (p.what === "stopping" && Date.now() - p.since > stopWait) {
                setPending(name, "")
                error = name + " didn't shut down: Force off (⇧X) pulls the plug"
            }
        }
    }

    // run(["start", "fedora"], out => …, () => …): queued behind a call still running, since the buttons rarely overlap
    property var queue: []
    function run(args, done, failed) {
        queue = queue.concat([{ args: args, done: done, failed: failed }])
        next()
    }
    function next() {
        if (caller.running || queue.length === 0) return
        const job = queue[0]
        queue = queue.slice(1)
        caller.done = job.done || null
        caller.failed = job.failed || null
        caller.command = [ctl].concat(job.args)
        busy = true
        error = ""
        caller.running = true
    }

    property Process lister: Process {
        command: [root.ctl, "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.vms = JSON.parse(text); root.loaded = true; root.settle() } catch (e) { root.error = "vm-ctl list: " + text }
            }
        }
    }

    property Process caller: Process {
        property var done: null
        property var failed: null
        stdout: StdioCollector { id: out }
        stderr: StdioCollector { id: err }
        onExited: code => {
            root.busy = false
            if (code !== 0) {
                root.error = err.text.trim() || ("vm-ctl failed (" + code + ")")
                if (failed) failed()
            } else if (done) done(out.text)
            root.refresh()
            root.next()
        }
    }

    property Timer poll: Timer { interval: 3000; running: true; repeat: true; triggeredOnStart: true; onTriggered: root.refresh() }
}
