import QtQuick
import Quickshell.Io

// The ready-made disk images (garage-ctl images): those for this host and how far each one's download has come, and the
// new VMs waiting for one. New VM on an image that isn't here yet starts its download (garage-ctl fetch) and leaves the VM
// here, in the window's memory, to be made (create-image) and started once the image is ready; the sidebar shows both.
// Closing the window forgets a waiting VM, but the download goes on by itself, and shows again when the window opens.
QtObject {
    id: root
    required property QtObject ctl
    property var list: []       // garage-ctl images: [{ id, name, about, size, minDisk, state, done, error }]
    property var waiting: []    // [{ name, id, mem, disk, cpus, user, pass }]
    signal made(string name)

    function image(id) { return list.find(i => i.id === id) || null }
    function refresh() { if (!lister.running) lister.running = true }
    function percent(i) { return i && i.size ? Math.floor(i.done / i.size * 100) : 0 }
    readonly property bool downloading: list.some(i => i.state === "downloading")

    // vm: { name, id, mem, disk, cpus, user, pass }. It waits only once fetch has run: fetch clears the last try's error,
    // which a poll before it would take for this one's
    function create(vm) {
        const i = image(vm.id)
        if (i && i.state === "ready") make(vm)
        else ctl.run(["fetch", vm.id], () => { waiting = waiting.concat([vm]); refresh() })
    }
    function make(vm) {
        ctl.run(["create-image", vm.name, vm.id, vm.mem, vm.disk, vm.cpus, vm.user], () => {
            ctl.power("start", vm.name)
            made(vm.name)
        }, null, vm.pass + "\n")
    }
    function settle() {
        const still = []
        for (const vm of waiting) {
            const i = image(vm.id)
            if (i && i.state === "ready") make(vm)
            else if (i && i.state === "failed") ctl.error = vm.name + " wasn't made: " + i.error
            else still.push(vm)
        }
        if (still.length !== waiting.length) waiting = still
    }

    property Process lister: Process {
        command: [root.ctl.ctl, "images"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.list = JSON.parse(text); root.settle() } catch (e) { root.ctl.error = "garage-ctl images: " + text }
            }
        }
    }

    // Often while something downloads or waits, for the sidebar's percent; once at the start, for a download the
    // window didn't start
    property Timer poll: Timer {
        interval: 1500; repeat: true; triggeredOnStart: true
        running: root.downloading || root.waiting.length > 0
        onTriggered: root.refresh()
    }
    Component.onCompleted: refresh()
}
