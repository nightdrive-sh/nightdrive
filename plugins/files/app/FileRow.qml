import QtQuick
import qs
import qs.kit
import "Format.js" as Format

// A file or folder in the list: its glyph, name, size and when it changed (in the trash: the folder it came from and
// when it went). Marked (Space) it shows a tick in the accent; cut (x), it is faded until pasted. A click picks it, a
// double click opens it; dragged, it goes out as text/uri-list with the other marked ones (the window's FileDrag), and
// a folder's row takes a drop itself.
AppRow {
    id: row
    required property var modelData
    required property int index
    required property var app
    readonly property var file: modelData
    readonly property bool isMarked: app.marks[file.path] === true

    implicitHeight: app.rowHeight
    selected: index === app.current
    active: app.listFocused
    opacity: app.clip.cutSet[file.path] ? 0.5 : 1
    color: drop.containsDrag ? c.hover : selected ? c.sel : marked || hovered ? c.hover : "transparent"
    border.color: drop.containsDrag ? c.primary : selected && active ? c.frame : "transparent"

    TapHandler {
        acceptedModifiers: Qt.NoModifier
        onTapped: { row.app.current = row.index; row.app.toList() }
        onDoubleTapped: row.app.openAt(row.index)
    }
    // ⌘-click marks or unmarks it, ⇧-click marks the rows from the picked one to it
    TapHandler {
        acceptedModifiers: Qt.ControlModifier
        onTapped: { row.app.current = row.index; row.app.toggleMarkAt(row.index); row.app.toList() }
    }
    TapHandler {
        acceptedModifiers: Qt.ShiftModifier
        onTapped: { row.app.markRange(row.app.current, row.index); row.app.current = row.index; row.app.toList() }
    }
    DragHandler {
        id: dragger
        target: null
        enabled: !row.app.trashShown
        onActiveChanged: active ? row.app.drag.start(row, row.app.dragPaths(row.file.path)) : row.app.drag.release(row)
    }
    DropArea {
        id: drop
        anchors.fill: parent
        enabled: row.file.dir && !row.app.trashShown
        keys: ["text/uri-list"]
        onDropped: e => row.app.acts.dropped(e, row.file.path, false)
    }

    Text {
        id: glyph
        anchors.left: parent.left; anchors.leftMargin: 14; anchors.verticalCenter: parent.verticalCenter
        width: 18
        text: Icons.g(row.isMarked ? "circle-check" : Format.glyph(row.file))
        font.family: Icons.family; font.pixelSize: row.app.compact ? 14 : 16
        color: row.isMarked ? row.c.accent : row.file.dir ? row.c.primary : row.c.dim
    }
    Text {
        textFormat: Text.PlainText
        anchors.left: glyph.right; anchors.leftMargin: 10
        anchors.right: second.left; anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        elide: Text.ElideMiddle
        text: row.file.name
        font.family: row.c.font; font.pixelSize: 13
        color: row.isMarked ? row.c.accent : row.selected ? row.c.title : row.c.text
    }
    // Size, or in the trash where it came from
    Text {
        id: second
        textFormat: Text.PlainText
        anchors.right: third.left; anchors.rightMargin: row.app.secondWidth ? 16 : 0
        anchors.verticalCenter: parent.verticalCenter
        width: row.app.secondWidth
        visible: width > 0
        horizontalAlignment: row.app.trashShown ? Text.AlignLeft : Text.AlignRight
        elide: Text.ElideMiddle
        text: row.app.trashShown ? row.app.tilde(Format.parent(row.file.origin)) : row.file.dir ? "" : Format.size(row.file.size)
        font.family: row.c.font; font.pixelSize: 12; color: row.c.faint
    }
    Text {
        id: third
        anchors.right: parent.right; anchors.rightMargin: row.app.thirdWidth ? 16 : 0
        anchors.verticalCenter: parent.verticalCenter
        width: row.app.thirdWidth
        visible: width > 0
        horizontalAlignment: Text.AlignRight
        text: Regional.relative(row.file.modified)
        font.family: row.c.font; font.pixelSize: 12; color: row.c.faint
    }
}
