import QtQuick
import QtQuick.Layouts
import qs.kit

// Files' sidebar: Places' entries as the kit's rows, a gap before the bookmarks, the disks and the trash. A folder's row
// takes a drop (files dragged onto it are moved or copied there, as onto a folder in the list); a disk that can be
// unmounted has an eject button under the pointer; one not mounted yet mounts as it is picked. The keys reach it with
// Tab (↑ ↓ j k move, ⏎ l → go there), and the row the window is in shows picked.
AppSidebar {
    id: root
    required property var app             // the window: places, path, trashShown, sideIndex, pane, open…
    title: "Files"
    spacing: 2

    Repeater {
        model: root.app.places.entries
        delegate: AppNavRow {
            id: row
            required property var modelData
            required property int index
            Layout.topMargin: modelData.gap ? 14 : 0
            c: root.c
            glyph: modelData.glyph
            label: modelData.name
            count: modelData.kind === "trash" && modelData.count ? String(modelData.count) : ""
            selected: root.app.pane === "side" ? index === root.app.sideIndex
                    : modelData.kind === "trash" ? root.app.trashShown : !root.app.trashShown && modelData.path === root.app.path
            active: root.app.pane === "side"
            dropTarget: drop.containsDrag
            onClicked: { root.app.sideIndex = index; root.app.goEntry(modelData); root.app.toList() }

            DropArea {
                id: drop
                anchors.fill: parent
                enabled: row.modelData.path !== "" || row.modelData.kind === "trash"
                keys: ["text/uri-list"]
                onDropped: e => { root.app.acts.dropped(e, row.modelData.kind === "trash" ? "" : row.modelData.path, row.modelData.kind === "trash") }
            }
            AppIconButton {
                visible: row.modelData.unmount === true && (row.hovered || hovered)
                anchors.right: parent.right; anchors.rightMargin: 6; anchors.verticalCenter: parent.verticalCenter
                c: root.c; glyph: "eject"; tip: "Unmount"; tipAlign: "right"
                onClicked: root.app.acts.unmount(row.modelData)
            }
        }
    }
    Item { Layout.fillHeight: true }
}
