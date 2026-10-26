import QtQuick
import Quickshell
import Quickshell.Io
import qs

// Garage: the VMs and their state (bin/garage-ctl list, refreshed while the menu is open). A click on a stopped VM starts
// it, on a running one brings its display forward; a running VM's row ends in two icons, its display shown or hidden
// (garage-ctl hide: the VM runs on) and Shut down. Open Garage opens the window, for the rest (new VMs, snapshots,
// settings).
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
    // garage-ctl's error, if it fails, shows under the header. Its arguments as such, no shell between: a VM's name is a
    // folder's, which garage-ctl checks, but only once it runs
    function act(action, name) {
        if (action === "start" || action === "stop") setPending(name, action === "start" ? "starting" : "stopping")
        m.error = ""
        const job = runner.createObject(m, { command: [m.ctl, action, name] })
        job.exited.connect(code => {
            if (code !== 0) { m.error = job.stderr.text.trim() || (action + " failed"); m.setPending(name, "") }
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
    Component { id: runner; Process { stdout: StdioCollector {} stderr: StdioCollector {} } }

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
            delegate: Item {
                id: vm
                required property var modelData
                readonly property var p: m.pending[modelData.name] || null
                readonly property bool on: modelData.running && !p     // its icons show
                width: m.width
                height: row.height
                MenuRow {
                    id: row
                    width: parent.width
                    icon: vm.modelData.running ? "monitor-play" : "monitor"
                    label: vm.modelData.name
                    detail: vm.p || vm.modelData.running ? "" : "Stopped"
                    busy: vm.p !== null
                    active: vm.modelData.running
                    // what a click does: start it; a running one's is its display to the front, shown or hidden
                    hoverCheckIcon: vm.p || vm.modelData.running ? "" : "play"
                    onClicked: {
                        if (vm.p) return
                        if (vm.modelData.running) { m.act("display", vm.modelData.name); m.close() }
                        else m.act("start", vm.modelData.name)
                    }
                }
                // Over the row's right end, where its detail would be: each takes its own click
                Row {
                    visible: vm.on
                    anchors { right: parent.right; rightMargin: 4; verticalCenter: parent.verticalCenter }
                    spacing: 2
                    Repeater {
                        model: [
                            { glyph: vm.modelData.shown ? "monitor-off" : "app-window",
                              action: vm.modelData.shown ? "hide" : "display" },
                            { glyph: "power", action: "stop" }
                        ]
                        delegate: Rectangle {
                            required property var modelData
                            width: 26; height: 26; radius: 5
                            color: hit.containsMouse ? Theme.hover : "transparent"
                            Text {
                                anchors.centerIn: parent
                                text: Icons.g(parent.modelData.glyph)
                                color: hit.containsMouse ? Theme.text : Theme.dim
                                font { family: Icons.family; pixelSize: 15 }
                            }
                            MouseArea {
                                id: hit
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    m.act(parent.modelData.action, vm.modelData.name)
                                    if (parent.modelData.action === "display") m.close()
                                }
                            }
                        }
                    }
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
