import QtQuick
import QtQuick.Layouts
import qs.kit

// The sidebar: the VMs, a running one with a dot in the theme's colour, and New VM at the foot. In a narrow window it
// takes the whole width while it shows (shell.qml's onePane), and picking a VM shows its page.
AppSidebar {
    id: root
    required property QtObject ctl
    property string current: ""          // the VM whose page shows
    signal picked(string name)
    signal newVm()
    title: "VM"

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
    Item { Layout.fillHeight: true }
    AppNavRow { c: root.c; glyph: "plus"; label: "New VM"; count: "⌘N"; onClicked: root.newVm() }
}
