import QtQuick
import qs
import qs.kit
import "Format.js" as Format

// A file or folder in one of the columns (FolderColumn, ColumnView): its glyph, its name cut to the column's width,
// and › after a folder, as Finder has it. In the window's own column it is FileRow's row: picked, marked and cut as
// there, a click picks it and a double click opens it. In another column, the folder on the way is lit faintly, and a
// click goes to that column's folder with the row picked (the window's go), so it becomes the window's own column.
// Dragged, it goes out with the other marked files (the window's FileDrag); a folder's row takes a drop itself.
AppRow {
    id: row
    required property var modelData
    required property int index
    required property var app
    required property var column              // its FolderColumn: own, path, pick
    readonly property var file: modelData
    readonly property bool own: column.own
    readonly property bool isMarked: own && app.marks[file.path] === true

    implicitHeight: app.rowHeight
    selected: own && index === app.current
    marked: !own && index === column.pick     // the folder on the way, while the keys are in a column to its right
    active: own && app.listFocused
    opacity: app.clip.cutSet[file.path] ? 0.5 : 1
    checked: isMarked
    color: drop.containsDrag ? c.hover : checked ? (selected ? c.checkedPicked : c.checked) : selected ? c.sel : marked || hovered ? c.hover : "transparent"
    border.color: drop.containsDrag ? c.primary : selected && active ? c.frame : "transparent"

    // A row another column shows becomes the window's own once clicked: the column it was in may be gone by the second
    // click of a double one (the columns after it go), so the window's tapped() tells a double click by the path
    TapHandler {
        acceptedModifiers: Qt.NoModifier
        onTapped: {
            const a = row.app, p = row.file.path
            if (row.own) a.current = row.index
            else a.go(row.column.path, p)
            a.toList()
            if (a.columnTapped(p)) { const i = a.rows.findIndex(r => r.path === p); if (i >= 0) a.openAt(i) }
        }
        onPressedChanged: if (pressed && !row.app.trashShown) row.app.drag.prepare(row.file, row.dragPaths().length)
    }
    // Ctrl-click and ⇧-click mark, as in the list: only in the window's own column, where the marks are
    TapHandler {
        acceptedModifiers: Qt.KeyboardModifierMask
        enabled: row.own
        onTapped: {
            const m = point.modifiers
            const cmd = (m & (Qt.ControlModifier | Qt.MetaModifier)) !== 0
            if (m & Qt.ShiftModifier) row.app.markTo(row.index, cmd)
            else if (m & Qt.ControlModifier) { row.app.current = row.index; row.app.toggleMarkAt(row.index) }
            else return
            row.app.toList()
        }
    }
    // Out of another column it is the one file: the marks are the window's own column's
    function dragPaths() { return own ? app.dragPaths(file.path) : [file.path] }
    DragHandler {
        target: null
        enabled: !row.app.trashShown
        onActiveChanged: active ? row.app.drag.start(row, row.dragPaths()) : row.app.drag.release(row)
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
        anchors.left: parent.left; anchors.leftMargin: 10; anchors.verticalCenter: parent.verticalCenter
        width: 18
        text: Icons.g(row.isMarked ? "circle-check" : Format.glyph(row.file))
        font.family: Icons.family; font.pixelSize: row.app.compact ? 14 : 16
        color: row.isMarked ? row.c.accent : row.file.dir ? row.c.primary : row.c.dim
    }
    // The name keeps to the room between the glyph and the chevron: a long one is cut in the middle, never over the next
    // column
    Text {
        textFormat: Text.PlainText
        anchors.left: glyph.right; anchors.leftMargin: 8
        anchors.right: chevron.left; anchors.rightMargin: 6
        anchors.verticalCenter: parent.verticalCenter
        elide: Text.ElideMiddle
        text: row.file.name
        font.family: row.c.font; font.pixelSize: 13
        color: row.isMarked ? row.c.accent : row.selected || row.marked ? row.c.title : row.c.text
    }
    Text {
        id: chevron
        anchors.right: parent.right; anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        width: 12
        text: row.file.dir ? Icons.g("chevron-right") : ""
        font.family: Icons.family; font.pixelSize: 12
        color: row.c.faint
    }
}
