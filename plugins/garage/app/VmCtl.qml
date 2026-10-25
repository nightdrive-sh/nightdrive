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
    property bool busy: false
    property string error: ""

    function refresh() { if (!lister.running) lister.running = true }

    // A VM on its way up or down, by name: { what: "starting" | "stopping", since, acpi }, until the list shows it there,
    // so the page can say so meanwhile. A shutdown the guest ignores gives up after stopWait; acpi: it went to the power
    // button, as the guest has no agent (garage-ctl stop), which says why.
    readonly property int stopWait: 90000
    property var pending: ({})
    function setPending(name, what, acpi) {
        const p = Object.assign({}, pending)
        if (what) p[name] = { what: what, since: Date.now(), acpi: !!acpi }; else delete p[name]
        pending = p
    }
    function power(action, name) {
        const what = action === "start" ? "starting" : "stopping"
        setPending(name, what)
        run([action, name], out => { if (out.trim() === "acpi") setPending(name, what, true) }, () => setPending(name, ""))
    }
    function settle() {
        for (const name in pending) {
            const v = vms.find(x => x.name === name), p = pending[name]
            if (!v || v.running === (p.what === "starting")) setPending(name, "")
            else if (p.what === "stopping" && Date.now() - p.since > stopWait) {
                setPending(name, "")
                error = name + " didn't shut down" + (p.acpi ? " (no qemu-guest-agent in it, so it was its power button)" : "")
                      + ": Force off (⇧X) pulls the plug"
            }
        }
    }

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
        busy = true
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
            root.busy = false
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
