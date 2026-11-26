import QtQuick
import qs
import qs.kit
import "refs.js" as Refs

// Threads and messages dragged out of Mail, as text/plain: a line each (refs.js) saying what the mail is and how Claude
// reads it, for a Claude Code terminal (#3611); any app that takes text gets the same line. Only text: a terminal
// given a text/uri-list too pastes that instead (kitty does), and a file of the message would let Claude read past
// Access. The list's threads go once the pointer leaves the window (Actions.qml), as inside it they drag to a folder;
// a message goes from its header in the reading pane or a message window (Thread.qml).
// The drag runs from this item, which lives as long as its window, not from the row or header pressed: Qt makes the
// drag's mime data a child of the item that started it and runs a nested loop until the drop, so a row recycled
// meanwhile took the data with it and the drop read freed memory (the desktop's DragOut.qml says how that crashed the
// shell, #3020; Files' FileDrag.qml does the same). A handler calls start as it turns active and release as it stops.
// What follows the pointer is a chip with the subject, or how many threads. grabToImage takes a frame to come back, too
// late once the drag runs, so prepare() makes it as the drag may begin.
Item {
    id: root
    required property QtObject c
    property var grab: null                // the chip's picture: kept alive, its url is the drag's image
    property var chain: []
    readonly property bool active: src.Drag.active

    function day(ts) { return ts ? Regional.format(new Date(ts * 1000), "short") : "" }

    function prepare(label, many) {
        chip.glyph = many ? "mails" : "mail"
        chip.label = label || "(no subject)"
        chip.grabToImage(r => root.grab = r, Qt.size(chip.width, chip.height))
    }
    // The list's threads (notmuch search's rows)
    function threads(item, ts) { start(item, Refs.text(ts.map(t => Refs.thread(t, day(t.timestamp))))) }
    // One message of an open thread; who: the sender's name
    function message(item, m, who) { start(item, Refs.text([Refs.message(m, who, day(m.timestamp))])) }

    function start(item, text) {
        if (src.Drag.active || !text) return
        const c = []
        for (let o = item; o; o = o.parent) c.push(o)
        chain = c
        src.Drag.mimeData = { "text/plain": text }
        src.Drag.imageSource = grab ? grab.url : ""
        src.Drag.hotSpot = Qt.point(-12, chip.height / 2)     // the chip just right of the pointer
        src.Drag.active = true
    }
    // Cancels a drag Qt hasn't started yet; one that runs goes on until the drop
    function release(item) { if (chain.indexOf(item) >= 0) src.Drag.active = false }

    // Drawn out of sight, for grabToImage. Its width comes from the label's implicitWidth, up to date as soon as the
    // label is set (a Row lays out a frame later, and the picture came out squeezed: FileDrag.qml)
    Rectangle {
        id: chip
        property string glyph: "mail"
        property string label: ""
        x: -2000; y: 0
        width: Math.min(320, 12 + 18 + 10 + name.implicitWidth + 14); height: 34
        radius: 8
        color: root.c.solid
        border.color: root.c.primary
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
            elide: Text.ElideRight
            text: chip.label; font.family: root.c.font; font.pixelSize: 12
            color: root.c.title
        }
    }

    Item {
        id: src
        Drag.dragType: Drag.Automatic
        Drag.supportedActions: Qt.CopyAction
        Drag.onActiveChanged: if (!Drag.active) root.chain = []
    }
}
