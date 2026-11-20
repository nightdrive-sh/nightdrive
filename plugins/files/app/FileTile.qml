import QtQuick
import qs
import "Format.js" as Format

// A file or folder in the grid (FileGrid): its thumbnail (Thumbs: a picture, a PDF's first page, a video's frame), or
// its glyph large while there is none, and its name under it in two lines at most. The same hands as a list's row
// (FileRow): a click picks it, a double click opens it, ⌘-click and ⇧-click mark, a drag takes it out with the other
// marked ones, and a folder's tile takes a drop. Marked it has the list's bar colour and a tick at its corner; cut, it is faded.
Rectangle {
    id: tile
    required property var modelData
    required property int index
    required property QtObject c
    required property var app
    readonly property var file: modelData
    readonly property bool isMarked: app.marks[file.path] === true
    readonly property bool selected: index === app.current
    readonly property bool hovered: hover.hovered && !c.pointerAway
    readonly property int pic: app.tile           // the thumbnail's square
    readonly property string thumb: app.thumbs.got[file.path] || ""

    // The grid's cell, less a gap all round
    width: GridView.view ? GridView.view.cellWidth - 6 : pic + 16
    height: GridView.view ? GridView.view.cellHeight - 6 : pic + 50
    radius: 8
    opacity: app.clip.cutSet[file.path] ? 0.5 : 1
    // Marked: the list's bar colour (AppRow's checked), stronger for the picked one
    color: drop.containsDrag ? c.hover : isMarked ? (selected ? c.checkedPicked : c.checked) : selected ? c.sel : hovered ? c.hover : "transparent"
    border.color: drop.containsDrag ? c.primary : selected && app.listFocused ? c.frame : "transparent"
    border.width: selected && app.listFocused ? 2 : 1

    HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
    TapHandler {
        acceptedModifiers: Qt.NoModifier
        onTapped: { tile.app.current = tile.index; tile.app.toList() }
        onDoubleTapped: tile.app.openAt(tile.index)
        // The drag's picture, taken now: it isn't ready in time once the drag starts (FileDrag)
        onPressedChanged: if (pressed && !tile.app.trashShown) tile.app.drag.prepare(tile.file, tile.app.dragPaths(tile.file.path).length)
    }
    // ⌘-click marks or unmarks it, ⇧-click marks from the anchor to it, ⌘⇧-click adds those (as FileRow): one
    // handler for every modifier, as acceptedModifiers wants an exact match and ⌘ arrives as Meta or Ctrl
    TapHandler {
        acceptedModifiers: Qt.KeyboardModifierMask
        onTapped: {
            const m = point.modifiers
            const cmd = (m & (Qt.ControlModifier | Qt.MetaModifier)) !== 0
            if (m & Qt.ShiftModifier) tile.app.markTo(tile.index, cmd)
            else if (cmd) { tile.app.current = tile.index; tile.app.toggleMarkAt(tile.index) }
            else return
            tile.app.toList()
        }
    }
    DragHandler {
        target: null
        enabled: !tile.app.trashShown
        onActiveChanged: active ? tile.app.drag.start(tile, tile.app.dragPaths(tile.file.path)) : tile.app.drag.release(tile)
    }
    DropArea {
        id: drop
        anchors.fill: parent
        enabled: tile.file.dir && !tile.app.trashShown
        keys: ["text/uri-list"]
        onDropped: e => tile.app.acts.dropped(e, tile.file.path, false)
    }

    // The thumbnail's square, at the top: the picture fits in it, centred, at its own shape
    Item {
        id: box
        anchors.horizontalCenter: parent.horizontalCenter
        y: 8
        width: tile.pic; height: tile.pic
        Image {
            id: img
            anchors.fill: parent
            visible: status === Image.Ready
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            // The file's time in the URL: a thumbnail drawn again for a changed file keeps its name, and Qt's cache
            // would show the old one
            source: tile.thumb ? Format.url(tile.thumb) + "?" + (tile.file.modified ? tile.file.modified.valueOf() : "") : ""
            sourceSize.width: tile.pic * 2; sourceSize.height: tile.pic * 2
        }
        // A thin line round the picture itself (not the square), so a white page or a photo of the sky has an edge
        Rectangle {
            visible: img.visible
            anchors.centerIn: parent
            width: img.paintedWidth + 2; height: img.paintedHeight + 2
            color: "transparent"
            border.color: tile.c.line
        }
        Text {
            visible: !img.visible
            anchors.centerIn: parent
            text: Icons.g(Format.glyph(tile.file))
            font.family: Icons.family; font.pixelSize: Math.round(tile.pic * 0.5)
            color: tile.file.dir ? tile.c.primary : tile.c.dim
        }
        // Marked: a tick at the corner, on a disc of the window's colour so a picture behind it doesn't hide it
        Rectangle {
            visible: tile.isMarked
            x: -4; y: -4
            width: 24; height: 24; radius: 12
            color: tile.c.solid
            Text {
                anchors.centerIn: parent
                text: Icons.g("circle-check")
                font.family: Icons.family; font.pixelSize: 20
                color: tile.c.accent
            }
        }
    }
    Text {
        anchors.top: box.bottom; anchors.topMargin: 8
        anchors.left: parent.left; anchors.right: parent.right
        anchors.leftMargin: 6; anchors.rightMargin: 6
        horizontalAlignment: Text.AlignHCenter
        textFormat: Text.PlainText
        wrapMode: Text.WrapAtWordBoundaryOrAnywhere
        maximumLineCount: 2
        elide: Text.ElideRight          // Qt elides only at the right once a text wraps
        text: tile.file.name
        font.family: tile.c.font; font.pixelSize: 12
        color: tile.isMarked ? tile.c.accent : tile.selected ? tile.c.title : tile.c.text
    }
}
