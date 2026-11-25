import QtQuick
import QtQuick.Layouts
import qs.kit
import "Fmt.js" as Fmt

// The sidebar: the places to look at (Home, the system disk, mounted disks, the folders you chose) with the size of
// their last scan, then Choose a folder and, at the foot, Clean up with what it can free.
AppSidebar {
    id: root
    property var places: []
    property string current: ""          // the place on show
    property real cleanable: 0           // Clean up's total, 0 until it is known
    signal picked(int index)
    signal choose()
    signal cleanUp()
    title: "Disk Usage"

    Repeater {
        model: root.places
        delegate: AppNavRow {
            required property var modelData
            required property int index
            // The folders you chose under a gap, apart from the places that are always there
            Layout.topMargin: modelData.chosen && (index === 0 || !root.places[index - 1].chosen) ? 14 : 0
            c: root.c
            glyph: modelData.glyph
            label: modelData.name
            count: modelData.total !== undefined ? Fmt.bytes(modelData.total) : ""
            selected: modelData.path === root.current
            onClicked: root.picked(index)
        }
    }
    AppNavRow { c: root.c; glyph: "folder-search"; label: "Choose a folder…"; onClicked: root.choose() }
    Item { Layout.fillHeight: true }
    AppNavRow {
        c: root.c
        glyph: "brush-cleaning"
        label: "Clean up"
        count: root.cleanable > 0 ? Fmt.bytes(root.cleanable) : ""
        countColor: root.c.primary
        onClicked: root.cleanUp()
    }
}
