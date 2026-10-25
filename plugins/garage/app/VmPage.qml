import QtQuick
import QtQuick.Layouts
import qs
import qs.kit

// One VM's page: a header level with the sidebar's title (its name and state), the buttons for what it can do now, what
// it has (memory, CPUs, disk, the ISO in its drive, ssh while it runs), and its snapshots (SnapshotList.qml). The
// questions it asks go to the window's panels (askName, askConfirm).
Item {
    id: root
    required property QtObject c
    required property QtObject ctl
    property var vm: null
    property bool onePane: false        // a narrow window: the header's arrow goes back to the list
    property int headerHeight: 62       // as AppSidebar's, so the name lines up with the app's
    property int bottomInset: 0         // room kept at the foot (shell.qml's error line)
    signal askName(string title, string initial, var done)
    signal askConfirm(string question, string detail, string action, string glyph, var done)
    signal back()
    signal settings()

    // Its state, with what the window has asked of it and the list doesn't show yet (VmCtl's pending)
    readonly property var pend: vm ? ctl.pending[vm.name] : undefined
    readonly property bool running: !!vm && vm.running
    readonly property bool stopping: running && !!pend && pend.what === "stopping"
    readonly property bool starting: !running && !!pend && pend.what === "starting"
    readonly property bool stopped: !!vm && !running && !starting

    // What the buttons and the keys do (shell.qml's s, d, x, ⇧X)
    function act(args) { root.ctl.run(args) }
    function start() { if (root.stopped) root.ctl.power("start", root.vm.name) }
    function display() { if (root.running) root.act(["display", root.vm.name]) }
    function shutDown() { if (root.running && !root.stopping) root.ctl.power("stop", root.vm.name) }
    function forceOff() { if (root.running) root.ctl.power("kill", root.vm.name) }
    function takeSnapshot() { snapshots.take() }
    function focusSnapshots() { snapshots.focusList() }
    // After a panel: the keys go back where they were, the snapshot list or the page
    function refocus() {
        if (snapshots.returnHere) { snapshots.returnHere = false; snapshots.focusList() } else root.forceActiveFocus()
    }
    // ⌘⌫: in the snapshot list the snapshot, as Del there; else the VM
    function deleteKey() { if (snapshots.focused) snapshots.removeCurrent(); else deleteVm() }
    function deleteVm() {
        if (!root.stopped) return
        const name = root.vm.name
        root.askName("Type " + name + " to delete it, its disk and its snapshots", "", n => { if (n === name) root.act(["delete", name]) })
    }

    ColumnLayout {
        visible: !!root.vm
        anchors.fill: parent
        spacing: 0

        // The header: the way back in one pane, the name, and its state on the right
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: root.headerHeight
            Layout.leftMargin: 28
            Layout.rightMargin: 28
            spacing: 10
            AppIconButton {
                visible: root.onePane
                Layout.leftMargin: -16
                implicitWidth: 40; implicitHeight: 40; radius: 8
                c: root.c; glyph: "arrow-left"; glyphSize: 17; tip: "VMs"; keys: "Esc"
                onClicked: root.back()
            }
            Text {
                Layout.fillWidth: true
                elide: Text.ElideRight
                text: root.vm ? root.vm.name : ""
                color: root.c.title; font.family: root.c.font; font.pixelSize: 15; font.weight: Font.DemiBold
            }
            Text {
                text: root.stopping ? "◌  Shutting down…" : root.starting ? "◌  Starting…"
                    : root.running ? "●  Running" : "○  Stopped"
                color: root.running && !root.stopping ? root.c.primary : root.c.dim
                font.family: root.c.font; font.pixelSize: 12
            }
        }
        Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: root.c.divider }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.margins: 28
            Layout.topMargin: 22
            Layout.bottomMargin: 28 + root.bottomInset
            spacing: 22

            // What it can do now: the likeliest first and strong. Over what follows, which would draw over their tips, and
            // the tips start at the buttons' left edge, as they sit at the page's left (the page clips)
            Flow {
                Layout.fillWidth: true
                z: 1
                spacing: 8
                AppButton {
                    c: root.c; glyph: "play"; label: "Start"; strong: true; keys: "s"; tip: "Start it in a window"; tipAlign: "left"
                    visible: root.stopped
                    onClicked: root.start()
                }
                AppButton {
                    c: root.c; glyph: "monitor"; label: "Display"; strong: !root.stopping; keys: "d"; tip: "Bring its window forward"; tipAlign: "left"
                    visible: root.running
                    onClicked: root.display()
                }
                AppButton {
                    c: root.c; glyph: "power"; label: "Shut down"; keys: "x"; tip: "Ask it to power off"; tipAlign: "left"
                    visible: root.running && !root.stopping
                    onClicked: root.shutDown()
                }
                AppButton {
                    c: root.c; glyph: "square"; label: "Force off"; strong: root.stopping; keys: "⇧X"; tip: "Pull the plug"; tipAlign: "left"
                    visible: root.running
                    onClicked: root.forceOff()
                }
                AppButton {
                    c: root.c; glyph: "settings"; label: "Settings"; keys: "⌘,"; tip: "Memory, CPUs, disk, ISO"; tipAlign: "left"
                    onClicked: root.settings()
                }
            }

            // What it has, a label and its value a line each
            Column {
                Layout.fillWidth: true
                spacing: 8
                Repeater {
                    model: !root.vm ? [] : [
                        { k: "Memory", v: (root.vm.mem / 1024) + " GB" },
                        { k: "CPUs", v: String(root.vm.cpus) },
                        { k: "Disk", v: root.vm.disk + " GB" + (root.vm.used !== undefined ? "  ·  " + root.vm.used + " GB in use" : "") },
                        { k: "ISO", v: root.vm.iso ? root.vm.iso.split("/").pop() : "", eject: true },
                        { k: "SSH", v: root.running && root.vm.ssh ? "ssh -p " + root.vm.ssh + " localhost" : "" }
                    ].filter(r => r.v !== "")
                    delegate: Row {
                        id: info
                        required property var modelData
                        spacing: 0
                        height: 22
                        Text {
                            width: 96; anchors.verticalCenter: parent.verticalCenter
                            text: info.modelData.k
                            color: root.c.faint; font.family: root.c.font; font.pixelSize: 12
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            width: Math.min(implicitWidth, root.width - 56 - 96 - 34)
                            elide: Text.ElideMiddle
                            rightPadding: info.modelData.eject ? 6 : 0
                            text: info.modelData.v
                            color: root.c.text; font.family: root.c.font; font.pixelSize: 12
                        }
                        // The ISO comes out while it is stopped, so it boots from its disk from then on
                        AppIconButton {
                            visible: !!info.modelData.eject && root.stopped
                            anchors.verticalCenter: parent.verticalCenter
                            c: root.c; glyph: "eject"; glyphSize: 12; tip: "Eject: boot from the disk from now on"
                            onClicked: root.act(["eject", root.vm.name])
                        }
                    }
                }
            }

            SnapshotList {
                id: snapshots
                Layout.topMargin: 6
                Layout.fillWidth: true
                c: root.c
                ctl: root.ctl
                vm: root.vm
                stopped: root.stopped
                onAskName: (title, initial, done) => root.askName(title, initial, done)
                onAskConfirm: (question, detail, action, glyph, done) => root.askConfirm(question, detail, action, glyph, done)
                onLeave: root.forceActiveFocus()
            }
            Item { Layout.fillHeight: true }
        }
    }
}
