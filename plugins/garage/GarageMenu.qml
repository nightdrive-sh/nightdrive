import QtQuick
import Quickshell
import qs

// Garage: the VMs and their state (bin/garage-ctl list, refreshed while the menu is open). A click on a stopped VM starts
// it, on a running one brings its display forward; a running VM has a Shut down row under it. Open Garage opens the
// window, for the rest (new VMs, snapshots, settings).
Column {
    id: m
    width: parent ? parent.width : 320
    spacing: 8
    signal close()

    readonly property string ctl: decodeURIComponent(Qt.resolvedUrl("bin/garage-ctl").toString().replace(/^file:\/\//, ""))
    readonly property string garage: decodeURIComponent(Qt.resolvedUrl("bin/garage").toString().replace(/^file:\/\//, ""))
    readonly property int pendingWait: 90000   // ms: a start or shutdown that hasn't shown by then stops saying so
    property var vms: []
    property bool loaded: false
    property string error: ""
    // A VM on its way up or down, by name: { what: "starting" | "stopping", since }, until the list shows it there
    property var pending: ({})
    readonly property int running: vms.filter(v => v.running).length

    function refresh() { if (!lister.running) lister.running = true }
    function setPending(name, what) {
        const p = Object.assign({}, pending)
        if (what) p[name] = { what: what, since: Date.now() }; else delete p[name]
        pending = p
    }
    function settle() {
        for (const name in pending) {
            const v = vms.find(x => x.name === name), p = pending[name]
            if (!v || v.running === (p.what === "starting") || Date.now() - p.since > pendingWait) setPending(name, "")
        }
    }
    // garage-ctl's error, if it fails, shows under the header (names are [A-Za-z0-9._-], safe in the script as such)
    function act(action, name) {
        if (action === "start" || action === "stop") setPending(name, action === "start" ? "starting" : "stopping")
        m.error = ""
        const job = runner.createObject(m, { script: "'" + m.ctl + "' " + action + " " + name })
        job.result.connect(text => {
            if (job.exitCode !== 0) { m.error = text.trim() || (action + " failed"); m.setPending(name, "") }
            m.refresh()
            job.destroy()
        })
        job.running = true
    }

    Component.onCompleted: refresh()
    Timer { interval: 3000; repeat: true; running: true; onTriggered: m.refresh() }

    Sh {
        id: lister
        command: [m.ctl, "list"]
        onResult: text => {
            try { m.vms = JSON.parse(text); m.loaded = true; m.settle() } catch (e) { m.error = "garage-ctl list: " + text }
        }
    }
    Component { id: runner; Sh {} }

    MenuHeader {
        width: parent.width
        title: "Garage"
        subtitle: m.running ? m.running + " running" : ""
    }

    MenuNote {
        width: parent.width
        variant: m.error !== "" ? "danger" : "dim"
        text: m.error !== "" ? m.error
            : !m.loaded ? "Loading…"
            : m.vms.length === 0 ? "No virtual machines yet: Open Garage and press ⌘N to make one." : ""
    }

    MenuSection { width: parent.width; title: "Virtual machines"; visible: m.vms.length > 0 }

    Column {
        width: parent.width
        spacing: 2
        Repeater {
            model: m.vms
            delegate: Column {
                id: vm
                required property var modelData
                readonly property var p: m.pending[modelData.name] || null
                width: m.width
                spacing: 2
                MenuRow {
                    width: parent.width
                    icon: vm.modelData.running ? "monitor-play" : "monitor"
                    label: vm.modelData.name
                    detail: vm.p ? "" : vm.modelData.running ? "Running" : "Stopped"
                    busy: vm.p !== null
                    active: vm.modelData.running
                    // what a click does: start it, or its display to the front
                    hoverCheckIcon: vm.p ? "" : vm.modelData.running ? "app-window" : "play"
                    onClicked: {
                        if (vm.p) return
                        if (vm.modelData.running) { m.act("display", vm.modelData.name); m.close() }
                        else m.act("start", vm.modelData.name)
                    }
                }
                // Indented under its VM, so with several VMs it's clear which one goes
                MenuRow {
                    x: 24
                    width: parent.width - 24
                    visible: vm.modelData.running && !vm.p
                    icon: "power"
                    label: "Shut down"
                    onClicked: m.act("stop", vm.modelData.name)
                }
            }
        }
    }

    MenuButton {
        width: parent.width
        gap: 10   // no divider above it: the room sets it apart
        icon: "external-link"
        label: "Open Garage"
        onClicked: { Quickshell.execDetached([m.garage]); m.close() }
    }
}
