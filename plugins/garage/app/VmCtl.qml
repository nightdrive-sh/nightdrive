import QtQuick
import Quickshell
import Quickshell.Io

// The window's side of bin/garage-ctl: the list of VMs (refreshed every few seconds, so a VM shut down from inside shows as
// stopped) and one call at a time for the buttons. Each call's output comes back to its callback; a failure's text is
// kept in `error` for the page to show.
QtObject {
    id: root
    readonly property string ctl: Quickshell.shellDir + "/../bin/garage-ctl"
    property var vms: []
    property bool loaded: false     // the first list has come: until then no VMs doesn't mean there are none
    property string error: ""

    function refresh() { if (!lister.running) lister.running = true }

    // Each VM's state is garage-ctl's (lib/state.sh): stopped, booting, running or stopping (slow: for long, and the page
    // offers Force off). Between a click and the list showing it, pending stands for it, by name: { what: "booting" |
    // "stopping" | "stopped", since }, until the list has caught up, the call fails or pendingWait has passed.
    readonly property int pendingWait: 30000
    property var pending: ({})
    function setPending(name, what) {
        const p = Object.assign({}, pending)
        if (what) p[name] = { what: what, since: Date.now() }; else delete p[name]
        pending = p
    }
    function stateOf(v) {
        if (!v) return "stopped"
        const p = pending[v.name]
        return p ? p.what : v.state || (v.running ? "running" : "stopped")
    }
    function power(action, name) {
        setPending(name, action === "start" ? "booting" : action === "stop" ? "stopping" : "stopped")
        run([action, name], null, () => setPending(name, ""))
    }
    function settle() {
        for (const name in pending) {
            const v = vms.find(x => x.name === name), p = pending[name], st = v ? v.state : "stopped"
            const there = p.what === "booting" ? st !== "stopped"
                        : p.what === "stopping" ? st === "stopping" || st === "stopped"
                        : st === "stopped"
            if (there || Date.now() - p.since > pendingWait) setPending(name, "")
        }
        // A shutdown gone slow says why once, at the page's foot: the page's Force off is strong meanwhile
        const slow = {}
        for (const v of vms) if (v.slow) {
            slow[v.name] = true
            if (!slowSaid[v.name])
                error = v.name + " hasn't shut down" + (v.acpi ? " (no qemu-guest-agent in it, so it was its power button)" : "")
                      + ": Force off (⇧X) pulls the plug"
        }
        slowSaid = slow
    }
    property var slowSaid: ({})

    // After the host has slept, the running VMs' clocks are behind by as long: a tick much later than the last one says
    // so, and their guest agents set them (garage-ctl synctime: quiet without one)
    property real lastTick: 0
    function tick() {
        const now = Date.now()
        if (lastTick && now - lastTick > 30000)
            for (const v of vms) if (v.running) run(["synctime", v.name])
        lastTick = now
        refresh()
    }

    // run(["start", "fedora"], out => …, () => …): queued behind a call still running, since the buttons rarely overlap.
    // input goes to its stdin (a new VM's password, kept out of ps), which then closes
    property var queue: []
    function run(args, done, failed, input) {
        queue = queue.concat([{ args: args, done: done, failed: failed, input: input }])
        next()
    }
    function next() {
        if (caller.running || queue.length === 0) return
        const job = queue[0]
        queue = queue.slice(1)
        caller.done = job.done || null
        caller.failed = job.failed || null
        caller.command = [ctl].concat(job.args)
        caller.input = job.input === undefined ? null : job.input
        caller.stdinEnabled = caller.input !== null
        error = ""
        caller.running = true
    }

    property Process lister: Process {
        command: [root.ctl, "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.vms = JSON.parse(text); root.loaded = true; root.settle() } catch (e) { root.error = "garage-ctl list: " + text }
            }
        }
    }

    property Process caller: Process {
        property var done: null
        property var failed: null
        property var input: null
        onStarted: if (input !== null) { write(input); input = null; stdinEnabled = false }
        stdout: StdioCollector { id: out }
        stderr: StdioCollector { id: err }
        onExited: code => {
            if (code !== 0) {
                root.error = err.text.trim() || ("garage-ctl failed (" + code + ")")
                if (failed) failed()
            } else if (done) done(out.text)
            root.refresh()
            root.next()
        }
    }

    property Timer poll: Timer { interval: 3000; running: true; repeat: true; triggeredOnStart: true; onTriggered: root.tick() }
}
