import QtQuick
import QtQuick.Layouts
import qs.kit

// The sidebar: the VMs, a running one with a dot in the theme's colour (fading in and out while it boots or shuts
// down; a paused one says so instead), then a disk image on its way ("Fedora 44 Minimal 43 %") and the new VMs waiting for it, and New machine at
// the foot. In a narrow window it takes the whole width while it shows (shell.qml's onePane), and picking a VM shows
// its page.
AppSidebar {
    id: root
    required property QtObject ctl
    required property QtObject images
    property string current: ""          // the VM whose page shows
    property bool active: false          // the arrows move between the VMs (the page has the keys, not the snapshots)
    signal picked(string name)
    signal newVm()
    title: "Garage"

    Repeater {
        model: root.ctl.vms
        delegate: AppNavRow {
            id: vmRow
            required property var modelData
            readonly property string vmState: root.ctl.stateOf(modelData)
            readonly property bool busy: vmState === "booting" || vmState === "stopping" && !modelData.slow
            c: root.c
            glyph: "monitor"
            label: modelData.name
            count: vmState === "paused" ? "paused" : vmState !== "stopped" ? "●" : ""
            countColor: vmState === "paused" ? root.c.faint : root.c.primary
            selected: root.current === modelData.name
            active: root.active
            onClicked: root.picked(modelData.name)
            // Booting up or shutting down: the dot fades in and out, as the page's header does (StateLine.qml)
            SequentialAnimation on countColor {
                running: vmRow.busy
                loops: Animation.Infinite
                ColorAnimation { to: root.c.faint; duration: 600; easing.type: Easing.InOutQuad }
                ColorAnimation { to: root.c.primary; duration: 600; easing.type: Easing.InOutQuad }
                onRunningChanged: if (!running) vmRow.countColor = Qt.binding(() => vmRow.vmState === "paused" ? root.c.faint : root.c.primary)
            }
        }
    }
    Repeater {
        model: root.images.list.filter(i => i.state === "downloading")
        delegate: AppNavRow {
            required property var modelData
            c: root.c
            glyph: "download"
            label: modelData.name
            count: root.images.percent(modelData) + " %"
        }
    }
    Repeater {
        model: root.images.waiting
        delegate: AppNavRow {
            required property var modelData
            c: root.c
            glyph: "monitor"
            label: modelData.name
            count: "waits"
        }
    }
    Item { Layout.fillHeight: true }
    AppNavRow { c: root.c; glyph: "plus"; label: "New machine"; count: "⌘N"; onClicked: root.newVm() }
}
