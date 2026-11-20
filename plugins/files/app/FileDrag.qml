import QtQuick
import qs
import "Format.js" as Format

// Files dragged out of the list, as text/uri-list: into another app (a mail, a chat, a browser's upload), onto a folder
// in the list or the sidebar, or another Files window. The drag runs from this item, which lives as long as the window,
// not from the row pressed: Qt makes the drag's mime data a child of the item that started it and runs a nested loop
// until the drop, so a row recycled meanwhile (the folder changed under the drag) took the data with it and the drop
// read freed memory (the desktop's DragOut.qml says how that crashed the shell, #3020). A row's DragHandler calls
// start() as it turns active and release() as it stops.
// What follows the pointer is a chip: the file's glyph and name, or how many are dragged. grabToImage takes a frame to
// come back, too late once the drag runs, so the row calls prepare() as it is pressed and the drag takes that picture.
Item {
    id: root
    required property QtObject c
    property var grab: null                // the chip's picture: kept alive, its url is the drag's image
    property var paths: []
    property var chain: []
    readonly property bool active: src.Drag.active
    // Whether the drag that just dropped came from this window: a drop from here moves, from elsewhere copies
    function ours(e) { return e.source === src }

    function start(item, ps) {
        if (src.Drag.active || !ps.length) return
        const c = []
        for (let o = item; o; o = o.parent) c.push(o)
        chain = c
        paths = ps
        src.Drag.mimeData = { "text/uri-list": ps.map(Format.url).join("\r\n") + "\r\n" }
        src.Drag.imageSource = grab ? grab.url : ""
        src.Drag.hotSpot = Qt.point(-12, chip.height / 2)     // the chip just right of the pointer
        src.Drag.active = true
    }
    // As a row is pressed: the chip for the files it would drag (that row's, or the marked ones with it)
    function prepare(file, count) {
        chip.glyph = count > 1 ? "files" : Format.glyph(file)
        chip.label = count > 1 ? count + " items" : file.name
        chip.grabToImage(r => root.grab = r, Qt.size(chip.width, chip.height))
    }
    function release(item) { if (chain.indexOf(item) >= 0) src.Drag.active = false }

    // Drawn out of sight, for grabToImage. Its width comes from the name's implicitWidth, which is up to date as soon
    // as the name is set: a Row lays out a frame later, and the first drag's picture came out squeezed
    Rectangle {
        id: chip
        property string glyph: "file"
        property string label: ""
        x: -2000; y: 0
        width: Math.min(280, 12 + 18 + 10 + name.implicitWidth + 14); height: 34
        radius: 8
        color: root.c.sel
        border.color: root.c.frame
        Text {
            x: 12; width: 18
            anchors.verticalCenter: parent.verticalCenter
            text: Icons.g(chip.glyph); font.family: Icons.family; font.pixelSize: 15
            color: root.c.primary
        }
        Text {
            id: name
            x: 40; width: chip.width - 40 - 14
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            elide: Text.ElideMiddle
            text: chip.label; font.family: root.c.font; font.pixelSize: 13
            color: root.c.title
        }
    }

    Item {
        id: src
        Drag.dragType: Drag.Automatic
        Drag.supportedActions: Qt.CopyAction | Qt.MoveAction
        Drag.proposedAction: Qt.CopyAction
        Drag.onActiveChanged: if (!Drag.active) { root.chain = []; root.paths = [] }
    }
}
