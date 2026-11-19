import QtQuick
import "Format.js" as Format

// Files dragged out of the list, as text/uri-list: into another app (a mail, a chat, a browser's upload), onto a folder
// in the list or the sidebar, or another Files window. The drag runs from this item, which lives as long as the window,
// not from the row pressed: Qt makes the drag's mime data a child of the item that started it and runs a nested loop
// until the drop, so a row recycled meanwhile (the folder changed under the drag) took the data with it and the drop
// read freed memory (the desktop's DragOut.qml says how that crashed the shell, #3020). A row's DragHandler calls
// start() as it turns active and release() as it stops.
Item {
    id: root
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
        src.Drag.active = true
    }
    function release(item) { if (chain.indexOf(item) >= 0) src.Drag.active = false }

    Item {
        id: src
        Drag.dragType: Drag.Automatic
        Drag.supportedActions: Qt.CopyAction | Qt.MoveAction
        Drag.proposedAction: Qt.CopyAction
        Drag.onActiveChanged: if (!Drag.active) { root.chain = []; root.paths = [] }
    }
}
