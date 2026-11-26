pragma Singleton
import QtQuick
import Quickshell

// Every drag out of the shell (a screenshot's preview, a shelf chip, a Ferry row) runs from here, not from the item that
// was pressed. Qt makes the drag's QDrag, and with it its mime data, a child of the pressed item's Drag attachment, and
// QDrag::exec runs a nested event loop until the drop. An item destroyed meanwhile (the notification menu swapped for
// Ferry's as the drag lingers over its bar icon, a popup expiring, a list reloading) took the mime data with it, and a
// drop on one of our own windows then read it back through Wayland from freed memory: Quickshell crashed in
// QMimeData::hasImage, and Hyprland 0.56 with it (#3020). This item lives as long as the shell, so the drag does too.
//
// An item starts its drag when its DragHandler or MouseArea drag turns active and releases it when that turns inactive
// (which cancels a drag Qt hasn't started yet, and is ignored once it runs: Qt keeps it going until the drop):
//     onActiveChanged: active ? DragOut.start(item, mime, image, hotSpot) : DragOut.release(item)
// A menu or shelf asks DragOut.active && DragOut.from(itself) for "a drag of mine is out" rather than counting its rows'
// drags: a row destroyed mid-drag never counted back down. finished(action) tells them how it ended.
Singleton {
    id: d

    readonly property bool active: src.Drag.active
    property var mime: ({})                    // the current drag's {type: text}
    property var chain: []                     // the item that started it and its parents, as they were at the start
    signal finished(int action)                // the drop (Qt.IgnoreAction: none took it); from() still answers here

    // True while (and as it ends) the current drag came from item or from inside it
    function from(item) { return d.chain.indexOf(item) >= 0 }

    // mime: {type: text}; image: a url for the picture under the pointer (a grabToImage result's: keep the result
    // object alive until here, its url goes with it), or "" for none; hotSpot: where the pointer holds the picture
    function start(item, mime, image, hotSpot) {
        if (src.Drag.active) return
        const c = []
        for (let o = item; o; o = o.parent) c.push(o)
        d.chain = c
        d.mime = mime
        src.Drag.mimeData = mime
        src.Drag.imageSource = image || ""
        src.Drag.hotSpot = hotSpot || Qt.point(0, 0)
        src.Drag.active = true
    }
    function release(item) { if (d.from(item)) src.Drag.active = false }

    Item {
        id: src
        Drag.dragType: Drag.Automatic
        Drag.supportedActions: Qt.CopyAction
        Drag.onDragFinished: action => d.finished(action)
        // After finished (Qt clears active last), or at once for a drag cancelled before Qt started it
        Drag.onActiveChanged: if (!Drag.active) { d.chain = []; d.mime = ({}) }
    }
}
