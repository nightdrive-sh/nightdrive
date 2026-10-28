import QtQuick
import Quickshell
import Quickshell.Io
import qs

// Garage: the VMs and their state (bin/garage-ctl list, refreshed while the menu is open; the states are lib/state.sh's).
// A click on a stopped VM starts it, on a running or booting one brings its display forward; a running VM's row ends in
// two icons, its display shown or hidden (garage-ctl hide: the VM runs on) and Shut down. One booting up or shutting down
// says so beside pulsing dots, and a shutdown that doesn't happen (slow) gets Force off. Open Garage opens the window,
// for the rest (new VMs, snapshots, settings).
Column {
    id: m
    width: parent ? parent.width : 320
    spacing: 8
    signal close()

    readonly property string ctl: decodeURIComponent(Qt.resolvedUrl("bin/garage-ctl").toString().replace(/^file:\/\//, ""))
    readonly property string garage: decodeURIComponent(Qt.resolvedUrl("bin/garage").toString().replace(/^file:\/\//, ""))
    readonly property int pendingWait: 30000   // ms: a click the list hasn't caught up with by then stops counting
    property var vms: []
    property bool loaded: false
    property string error: ""
    // Between a click and the list showing it, by name: { what: "booting" | "stopping", since } (as the window's VmCtl)
    property var pending: ({})
    readonly property int running: vms.filter(v => v.running).length
    function stateOf(v) {
        const p = pending[v.name]
        return p ? p.what : v.state || (v.running ? "running" : "stopped")
    }

    function refresh() { if (!lister.running) lister.running = true }
    function setPending(name, what) {
        const p = Object.assign({}, pending)
        if (what) p[name] = { what: what, since: Date.now() }; else delete p[name]
        pending = p
    }
    function settle() {
        for (const name in pending) {
            const v = vms.find(x => x.name === name), p = pending[name], st = v ? v.state : "stopped"
            const there = p.what === "booting" ? st !== "stopped" : st === "stopping" || st === "stopped"
            if (there || Date.now() - p.since > pendingWait) setPending(name, "")
        }
    }
    // garage-ctl's error, if it fails, shows under the header. Its arguments as such, no shell between: a VM's name is a
    // folder's, which garage-ctl checks, but only once it runs
    function act(action, name) {
        if (action === "start" || action === "stop") setPending(name, action === "start" ? "booting" : "stopping")
        m.error = ""
        const job = runner.createObject(m, { command: [m.ctl, action, name] })
        job.exited.connect(code => {
            if (code !== 0) { m.error = job.stderr.text.trim() || (action + " failed"); m.setPending(name, "") }
            m.refresh()
            job.destroy()
        })
        job.running = true
    }

    // An icon that takes its own click, over a row's right end
    component MenuGlyph: Rectangle {
        property string glyph
        signal clicked()
        width: 26; height: 26; radius: 5
        color: hit.containsMouse ? Theme.hover : "transparent"
        Text {
            anchors.centerIn: parent
            text: Icons.g(parent.glyph)
            color: hit.containsMouse ? Theme.text : Theme.dim
            font { family: Icons.family; pixelSize: 15 }
        }
        MouseArea {
            id: hit
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: parent.clicked()
        }
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
                readonly property string st: m.stateOf(modelData)
                readonly property bool on: st === "running"                    // its icons show
                readonly property bool slow: st === "stopping" && !!modelData.slow && !m.pending[modelData.name]
                readonly property bool busy: (st === "booting" || st === "stopping") && !slow
                width: m.width
                height: row.height
                MenuRow {
                    id: row
                    width: parent.width
                    icon: vm.st !== "stopped" ? "monitor-play" : "monitor"
                    label: vm.modelData.name
                    detail: vm.st === "stopped" ? "Stopped" : ""
                    active: vm.st !== "stopped"
                    // what a click does: start it; a running or booting one's is its display to the front
                    hoverCheckIcon: vm.st === "stopped" ? "play" : ""
                    onClicked: {
                        if (vm.st === "stopped") m.act("start", vm.modelData.name)
                        else if (vm.st !== "stopping" && vm.modelData.running) { m.act("display", vm.modelData.name); m.close() }
                    }
                }
                // Booting up or shutting down: the word and pulsing dots where the icons would be; Force off once it is slow
                Row {
                    visible: vm.busy || vm.slow
                    anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                    spacing: 8
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: vm.slow ? "Not shutting down" : vm.st === "booting" ? "Booting up…" : "Shutting down…"
                        color: Theme.dim
                        font { family: Theme.font; pixelSize: 11 }
                    }
                    BusyDots { visible: vm.busy; anchors.verticalCenter: parent.verticalCenter }
                    MenuGlyph {
                        visible: vm.slow
                        glyph: "square"
                        onClicked: m.act("kill", vm.modelData.name)
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
                        delegate: MenuGlyph {
                            required property var modelData
                            glyph: modelData.glyph
                            onClicked: {
                                m.act(modelData.action, vm.modelData.name)
                                if (modelData.action === "display") m.close()
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
