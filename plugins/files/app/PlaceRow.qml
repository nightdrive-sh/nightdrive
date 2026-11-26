import QtQuick
import QtQuick.Layouts
import qs.kit

// One row of Files' sidebar (Sidebar): a place, a bookmark, a disk or the trash, as the kit's AppNavRow.
// - Files dropped on a folder's row are moved or copied there, as onto a folder in the list; on Trash, trashed.
// - Under the pointer, a disk that can be unmounted has an eject button, and a place or a bookmark a ✕ that takes it
//   out of the sidebar (Undo puts it back). No right-click menu: Files has none.
// - A place or a bookmark drags (a copy of the row follows the pointer) onto another one: dropped on its upper half it
//   goes before it, on the lower half after it, in that one's group. A line shows where.
AppNavRow {
    id: row
    required property var modelData
    required property int globalIndex     // in Places.entries, which the keys walk through
    required property var app
    readonly property bool movable: modelData.kind === "place" || modelData.kind === "bookmark"
    Layout.topMargin: modelData.gap ? 14 : 0
    z: moving.active ? 5 : 0
    glyph: modelData.glyph
    label: modelData.name
    count: modelData.kind === "trash" && modelData.count ? String(modelData.count) : ""
    selected: app.pane === "side" ? globalIndex === app.sideIndex
            : modelData.kind === "trash" ? app.trashShown : !app.trashShown && modelData.path === app.path
    active: app.pane === "side"
    dropTarget: files.containsDrag
    onClicked: { app.sideIndex = globalIndex; app.goEntry(modelData); app.toList() }

    DropArea {
        id: files
        anchors.fill: parent
        enabled: row.modelData.path !== "" || row.modelData.kind === "trash"
        keys: ["text/uri-list"]
        onDropped: e => { row.app.acts.dropped(e, row.modelData.kind === "trash" ? "" : row.modelData.path, row.modelData.kind === "trash") }
    }

    // A sidebar folder dropped here: before this row (upper half) or after it
    DropArea {
        id: places
        anchors.fill: parent
        enabled: row.movable
        keys: ["files-place"]
        readonly property bool upper: drag.y < height / 2
        onDropped: e => row.placeHere(e.y < height / 2)
    }
    Rectangle {
        visible: places.containsDrag && row.app.placeDrag !== row.modelData.path
        x: 8; width: parent.width - 16; height: 2; radius: 1
        y: places.upper ? -2 : parent.height
        color: row.c.accent
    }
    function placeHere(upper) {
        const moved = app.placeDrag
        if (!moved || moved === modelData.path) return
        const own = modelData.kind === "place"
        const group = own ? app.places.pinnedRows : app.places.bookmarkRows
        const next = group[group.findIndex(e => e.path === modelData.path) + 1]
        const before = upper ? modelData.path : next ? next.path : ""
        if (before === moved) return             // already there
        app.acts.movePlace(moved, own ? "places" : "bookmarks", before)
    }

    // What follows the pointer while the row is dragged; the row itself stays
    Rectangle {
        id: ghost
        visible: moving.active
        width: row.width; height: row.height; radius: 8
        color: row.c.sel; opacity: 0.9
        border.color: row.c.frame
        Drag.keys: ["files-place"]
        Drag.hotSpot.x: width / 2; Drag.hotSpot.y: height / 2
        Text {
            anchors.left: parent.left; anchors.leftMargin: 40; anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: row.modelData.name; color: row.c.title; font.family: row.c.font; font.pixelSize: 13
        }
    }
    DragHandler {
        id: moving
        enabled: row.movable
        target: ghost
        xAxis.enabled: false
        onActiveChanged: {
            if (active) { row.app.placeDrag = row.modelData.path; ghost.Drag.start() }
            else { ghost.Drag.drop(); ghost.y = 0; row.app.placeDrag = "" }
        }
    }

    AppIconButton {
        visible: row.movable && !moving.active && (row.hovered || hovered)
        anchors.right: parent.right; anchors.rightMargin: 6; anchors.verticalCenter: parent.verticalCenter
        implicitWidth: 20; implicitHeight: 20; glyphSize: 11   // small, so a click meant for the row seldom lands on it
        c: row.c; glyph: "x"; tip: "Remove from the sidebar"; tipAlign: "right"
        onClicked: row.app.acts.removePlace(row.modelData)
    }
    AppIconButton {
        visible: row.modelData.unmount === true && (row.hovered || hovered)
        anchors.right: parent.right; anchors.rightMargin: 6; anchors.verticalCenter: parent.verticalCenter
        c: row.c; glyph: "eject"; tip: "Unmount"; tipAlign: "right"
        onClicked: row.app.acts.unmount(row.modelData)
    }
}
