import QtQuick
import QtQuick.Layouts
import qs.kit

// Files' sidebar: Places' three parts as PlaceRows (drops, ✕, eject and dragging are theirs): Files' own group, a gap,
// the bookmarks, the disks and the trash. While a folder is dragged, a group with nothing in it shows a slot to drop it
// in, so a folder can always go to the other group. The keys reach it with Tab (↑ ↓ j k move, ⏎ l → go there), and the
// row the window is in shows picked.
AppSidebar {
    id: root
    required property var app             // the window: places, path, trashShown, sideIndex, pane, placeDrag…
    title: "Files"
    spacing: 2

    // At the title's right, while the pointer is on its line: Settings' gear, as Mail's (⌘, opens them too)
    titleItems: [
        AppIconButton {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.titleHovered
            implicitWidth: 22
            c: root.c
            glyph: "settings"; glyphColor: root.c.faint
            tip: "Settings"; keys: "⌘,"; tipAlign: "right"
            onClicked: root.app.showSettings = true
        }
    ]

    readonly property var places: app.places
    readonly property int bookmarksAt: places.pinnedRows.length
    readonly property int othersAt: bookmarksAt + places.bookmarkRows.length

    component Slot: Rectangle {
        id: slot
        property string group
        property bool gap: false
        Layout.fillWidth: true
        Layout.leftMargin: 12; Layout.rightMargin: 12
        Layout.topMargin: gap ? 14 : 0
        implicitHeight: 34; radius: 8
        color: drop.containsDrag ? root.c.hover : "transparent"
        border.color: drop.containsDrag ? root.c.accent : root.c.divider
        Text {
            anchors.centerIn: parent
            text: slot.group === "places" ? "Drop here to keep it at the top" : "Drop here to bookmark it"
            color: root.c.faint; font.family: root.c.font; font.pixelSize: 12
        }
        DropArea {
            id: drop
            anchors.fill: parent
            keys: ["files-place"]
            onDropped: root.app.acts.movePlace(root.app.placeDrag, slot.group, "")
        }
    }

    Repeater {
        model: root.places.pinnedRows
        delegate: PlaceRow { required property int index; globalIndex: index; c: root.c; app: root.app }
    }
    Slot { group: "places"; visible: root.app.placeDrag !== "" && root.places.pinnedRows.length === 0 }
    Repeater {
        model: root.places.bookmarkRows
        delegate: PlaceRow { required property int index; globalIndex: root.bookmarksAt + index; c: root.c; app: root.app }
    }
    Slot { group: "bookmarks"; gap: true; visible: root.app.placeDrag !== "" && root.places.bookmarkRows.length === 0 }
    Repeater {
        model: root.places.otherRows
        delegate: PlaceRow { required property int index; globalIndex: root.othersAt + index; c: root.c; app: root.app }
    }
    Item { Layout.fillHeight: true }
}
