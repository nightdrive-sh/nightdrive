import QtQuick
import QtQuick.Layouts
import qs
import qs.kit

// One VM's page: its name and state, what it has (memory, CPUs, disk, the ISO in its drive), the buttons, and its
// snapshots. Snapshots are taken, restored and deleted only while it is stopped (qemu-img works on the disk file then);
// a snapshot row's bin asks first (askConfirm), as a deleted snapshot is gone.
Item {
    id: root
    required property QtObject c
    required property QtObject ctl
    property var vm: null
    property int snap: -1           // the picked snapshot
    readonly property var snaps: vm ? vm.snapshots : []
    onVmChanged: if (snap >= snaps.length) snap = snaps.length - 1
    signal askName(string title, string initial, var done)
    signal askConfirm(string question, string detail, var done)

    function act(args) { root.ctl.run(args) }
    function deleteSnap(i) {
        if (!root.vm || root.vm.running || i < 0 || i >= root.snaps.length) return
        const name = root.vm.name, tag = root.snaps[i].tag
        root.askConfirm("Delete the snapshot " + tag + "?", name + "'s disk can no longer go back to it.",
                        () => root.act(["unsnap", name, tag]))
    }

    Text {
        visible: !root.vm
        anchors.centerIn: parent
        text: "No VMs yet: + New VM (⌘N)"
        color: root.c.faint; font.family: root.c.font; font.pixelSize: 13
    }

    ColumnLayout {
        visible: !!root.vm
        anchors.fill: parent
        anchors.margins: 32
        anchors.topMargin: 20
        spacing: 18

        RowLayout {
            Layout.preferredHeight: 22
            Text {
                text: root.vm ? root.vm.name : ""
                color: root.c.title; font.family: root.c.font; font.pixelSize: 15; font.weight: Font.Medium
            }
            Item { Layout.fillWidth: true }
            Text {
                text: root.vm && root.vm.running ? "●  running" : "○  stopped"
                color: root.vm && root.vm.running ? root.c.primary : root.c.dim
                font.family: root.c.font; font.pixelSize: 12
            }
        }

        Text {
            text: root.vm ? (root.vm.mem / 1024) + " GB memory · " + root.vm.cpus + " CPUs · " + root.vm.disk + " GB disk"
                            + (root.vm.iso ? "\nISO: " + root.vm.iso : "") : ""
            Layout.fillWidth: true
            wrapMode: Text.WrapAnywhere      // a long ISO path mustn't widen the page
            color: root.c.dim; font.family: root.c.font; font.pixelSize: 12; lineHeight: 1.3
        }

        Flow {
            Layout.fillWidth: true
            spacing: 8
            AppButton {
                c: root.c; glyph: "play"; label: "Start"; strong: true; keys: "s"; tip: "Start it, its display in a window"
                visible: root.vm && !root.vm.running
                onClicked: root.act(["start", root.vm.name])
            }
            AppButton {
                c: root.c; glyph: "monitor"; label: "Display"; keys: "d"; tip: "Bring its window forward"
                visible: root.vm && root.vm.running
                onClicked: root.act(["display", root.vm.name])
            }
            AppButton {
                c: root.c; glyph: "power"; label: "Shut down"; keys: "x"; tip: "Ask it to power off (ACPI)"
                visible: root.vm && root.vm.running
                onClicked: root.act(["stop", root.vm.name])
            }
            AppButton {
                c: root.c; glyph: "square"; label: "Force off"; tip: "Pull the plug"
                visible: root.vm && root.vm.running
                onClicked: root.act(["kill", root.vm.name])
            }
            AppButton {
                c: root.c; glyph: "disc"; label: "Eject ISO"; tip: "Boot from the disk from now on"
                visible: root.vm && !root.vm.running && root.vm.iso !== ""
                onClicked: root.act(["eject", root.vm.name])
            }
            AppButton {
                c: root.c; glyph: "trash-2"; label: "Delete VM"; tip: "Delete it and its disk"
                visible: root.vm && !root.vm.running
                onClicked: root.askName("Type the name to delete " + root.vm.name, "", n => { if (n === root.vm.name) root.act(["delete", n]) })
            }
        }

        Text {
            Layout.topMargin: 10
            text: "Snapshots"
            color: root.c.title; font.family: root.c.font; font.pixelSize: 13; font.weight: Font.Medium
        }

        ListView {
            id: list
            visible: root.snaps.length > 0
            Layout.fillWidth: true
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
                    opacity: root.vm && !root.vm.running ? 1 : 0
                    enabled: opacity > 0
                    onClicked: root.deleteSnap(row.index)
                }
            }
        }
        Text {
            visible: root.snaps.length === 0
            text: "None yet."
            color: root.c.faint; font.family: root.c.font; font.pixelSize: 12
        }

        Row {
            spacing: 8
            readonly property bool stopped: root.vm && !root.vm.running
            AppButton {
                c: root.c; glyph: "camera"; label: "Take snapshot"; tip: "Only while it is stopped"
                visible: parent.stopped
                onClicked: root.askName("Name the snapshot", Qt.formatDateTime(new Date(), "yyyy-MM-dd-hhmm"),
                                        n => { if (n) root.act(["snapshot", root.vm.name, n]) })
            }
            AppButton {
                c: root.c; glyph: "rotate-ccw"; label: "Restore"; tip: "The disk goes back to this snapshot"
                visible: parent.stopped && root.snap >= 0
                onClicked: root.act(["restore", root.vm.name, root.snaps[root.snap].tag])
            }
            Text {
                visible: root.vm && root.vm.running
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
