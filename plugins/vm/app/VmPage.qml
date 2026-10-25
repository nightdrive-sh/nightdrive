import QtQuick
import QtQuick.Layouts
import qs
import qs.kit

// One VM's page: a header level with the sidebar's title (its name and state), the buttons for what it can do now, what
// it has (memory, CPUs, disk, the ISO in its drive, ssh while it runs), and its snapshots. Snapshots are taken, restored
// and deleted only while it is stopped (qemu-img works on the disk file then); a snapshot row's bin asks first
// (askConfirm), as a deleted snapshot is gone.
Item {
    id: root
    required property QtObject c
    required property QtObject ctl
    property var vm: null
    property bool onePane: false        // a narrow window: the header's arrow goes back to the list
    property int headerHeight: 62       // as AppSidebar's, so the name lines up with the app's
    property int snap: -1               // the picked snapshot
    readonly property var snaps: vm ? vm.snapshots : []
    onVmChanged: if (snap >= snaps.length) snap = snaps.length - 1
    signal askName(string title, string initial, var done)
    signal askConfirm(string question, string detail, var done)
    signal back()

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
    function deleteSnap(i) {
        if (!root.stopped || i < 0 || i >= root.snaps.length) return
        const name = root.vm.name, tag = root.snaps[i].tag
        root.askConfirm("Delete the snapshot " + tag + "?", name + "'s disk can no longer go back to it.",
                        () => root.act(["unsnap", name, tag]))
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
            spacing: 22

            // What it can do now: the likeliest first and strong
            Flow {
                Layout.fillWidth: true
                spacing: 8
                AppButton {
                    c: root.c; glyph: "play"; label: "Start"; strong: true; keys: "s"; tip: "Start it, its display in a window"
                    visible: root.stopped
                    onClicked: root.start()
                }
                AppButton {
                    c: root.c; glyph: "monitor"; label: "Display"; strong: !root.stopping; keys: "d"; tip: "Bring its window forward"
                    visible: root.running
                    onClicked: root.display()
                }
                AppButton {
                    c: root.c; glyph: "power"; label: "Shut down"; keys: "x"; tip: "Ask it to power off"
                    visible: root.running && !root.stopping
                    onClicked: root.shutDown()
                }
                AppButton {
                    c: root.c; glyph: "square"; label: "Force off"; strong: root.stopping; keys: "⇧X"; tip: "Pull the plug"
                    visible: root.running
                    onClicked: root.forceOff()
                }
                AppButton {
                    c: root.c; glyph: "trash-2"; label: "Delete VM"; tip: "Delete it and its disk"
                    visible: root.stopped
                    onClicked: root.askName("Type the name to delete " + root.vm.name, "", n => { if (n === root.vm.name) root.act(["delete", n]) })
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

            Text {
                Layout.topMargin: 6
                text: "Snapshots"
                color: root.c.title; font.family: root.c.font; font.pixelSize: 13; font.weight: Font.Medium
            }

            ListView {
                id: list
                visible: root.snaps.length > 0
                Layout.fillWidth: true
                Layout.topMargin: -12
                Layout.preferredHeight: Math.min(contentHeight, 260)
                clip: true
                model: root.snaps
                spacing: 2
                delegate: AppRow {
                    id: row
                    required property var modelData
                    required property int index
                    c: root.c
                    height: 32
                    selected: index === root.snap
                    TapHandler { onTapped: root.snap = row.index }
                    Text {
                        x: 14; anchors.verticalCenter: parent.verticalCenter
                        text: row.modelData.tag
                        color: row.selected ? root.c.title : root.c.text; font.family: root.c.font; font.pixelSize: 12
                    }
                    Text {
                        anchors.right: bin.left; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter
                        text: row.modelData.date
                        color: root.c.faint; font.family: root.c.font; font.pixelSize: 11
                    }
                    // Kept in its place while the VM runs (only hidden), so the dates don't shift
                    AppIconButton {
                        id: bin
                        anchors.right: parent.right; anchors.rightMargin: 4; anchors.verticalCenter: parent.verticalCenter
                        c: root.c; glyph: "trash-2"; glyphSize: 12; tip: "Delete this snapshot"; keys: "Del"; tipSide: "above"
                        opacity: root.stopped ? 1 : 0
                        enabled: opacity > 0
                        onClicked: root.deleteSnap(row.index)
                    }
                }
            }
            Text {
                visible: root.snaps.length === 0
                Layout.topMargin: -12
                text: "None yet."
                color: root.c.faint; font.family: root.c.font; font.pixelSize: 12
            }

            Row {
                spacing: 8
                AppButton {
                    c: root.c; glyph: "camera"; label: "Take snapshot"; tip: "Only while it is stopped"
                    visible: root.stopped
                    onClicked: root.askName("Name the snapshot", Qt.formatDateTime(new Date(), "yyyy-MM-dd-hhmm"),
                                            n => { if (n) root.act(["snapshot", root.vm.name, n]) })
                }
                AppButton {
                    c: root.c; glyph: "rotate-ccw"; label: "Restore"; tip: "The disk goes back to this snapshot"
                    visible: root.stopped && root.snap >= 0
                    onClicked: root.act(["restore", root.vm.name, root.snaps[root.snap].tag])
                }
                Text {
                    visible: !root.stopped
                    text: "Shut it down to take, restore or delete a snapshot."
                    color: root.c.faint; font.family: root.c.font; font.pixelSize: 11
                }
            }

            Text {
                visible: root.ctl.error !== ""
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                text: root.ctl.error
                color: root.c.danger; font.family: root.c.font; font.pixelSize: 12
            }

            Item { Layout.fillHeight: true }
        }
    }
}
