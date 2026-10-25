import QtQuick
import QtQuick.Layouts
import qs.kit

// The sidebar: the VMs, a running one with a dot in the theme's colour, then a disk image on its way ("Fedora 44 Minimal
// 43 %") and the new VMs waiting for it, and New machine at the foot. In a narrow window it
// takes the whole width while it shows (shell.qml's onePane), and picking a VM shows its page.
AppSidebar {
    id: root
    required property QtObject ctl
    required property QtObject images
    property string current: ""          // the VM whose page shows
    signal picked(string name)
    signal newVm()
    title: "Garage"

    Repeater {
        model: root.ctl.vms
        delegate: AppNavRow {
            required property var modelData
            c: root.c
            glyph: "monitor"
            label: modelData.name
            count: modelData.running ? "●" : ""
            countColor: root.c.primary
            selected: root.current === modelData.name
            onClicked: root.picked(modelData.name)
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
