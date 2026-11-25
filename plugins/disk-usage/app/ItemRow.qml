import QtQuick
import qs
import qs.kit
import "Fmt.js" as Fmt

// One entry of the folder on show: its glyph, name, a bar as long as its size against the biggest entry's (ranked bars
// compare better than slices), its size and its share of the folder. The five biggest have their colour of the split
// bar above the list (SplitBar), on the glyph and the bar; the rest share a quiet one. A folder ends in a chevron: Enter
// or a click opens it. The folder's smaller items, folded into one row (walk.py), have nothing to open.
AppRow {
    id: root
    required property var item           // { n, s, k, i, c, u }
    required property real biggest       // the biggest entry's size: its bar is full
    required property real total         // the folder's size, for the share
    property color tint: c.faint         // the entry's colour: one of the split bar's, or the rest's
    property bool hot: false             // its segment of the split bar is under the pointer
    readonly property bool folder: item.k === "d"
    readonly property bool fold: item.k === "o"
    signal open()
    implicitHeight: 40
    color: selected ? c.sel : marked || hovered || hot ? c.hover : "transparent"

    TapHandler { onTapped: root.open() }

    Text {
        id: glyph
        x: 14; anchors.verticalCenter: parent.verticalCenter
        text: Icons.g(root.fold ? "ellipsis" : root.folder ? "folder" : "file")
        font.family: Icons.family; font.pixelSize: 15
        color: root.fold ? root.c.faint : root.tint
    }
    Text {
        textFormat: Text.PlainText
        anchors.left: glyph.right; anchors.leftMargin: 12
        anchors.right: bar.left; anchors.rightMargin: 16
        anchors.verticalCenter: parent.verticalCenter
        elide: Text.ElideMiddle
        text: root.fold ? Fmt.plural(root.item.i, "smaller item", "smaller items") : root.item.n
        color: root.fold ? root.c.dim : root.selected ? root.c.title : root.c.text
        font.family: root.c.font; font.pixelSize: 13
    }
    // The bar: a hairline track, the entry's part over it
    Item {
        id: bar
        anchors.right: size.left; anchors.rightMargin: 16
        anchors.verticalCenter: parent.verticalCenter
        width: Math.max(60, Math.min(260, root.width * 0.3)); height: 6
        Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width; height: 2; radius: 1; color: root.c.line }
        Rectangle {
            width: root.biggest > 0 ? Math.max(3, parent.width * root.item.s / root.biggest) : 0
            height: parent.height; radius: 3
            color: root.tint
            opacity: root.fold ? 0.6 : 1
        }
    }
    Text {
        id: size
        anchors.right: share.left; anchors.rightMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        width: 72; horizontalAlignment: Text.AlignRight
        text: Fmt.bytes(root.item.s)
        color: root.selected ? root.c.title : root.c.text
        font.family: root.c.font; font.pixelSize: 12
    }
    Text {
        id: share
        anchors.right: chevron.left; anchors.rightMargin: 6
        anchors.verticalCenter: parent.verticalCenter
        width: 54; horizontalAlignment: Text.AlignRight
        text: Fmt.percent(root.item.s, root.total)
        color: root.c.faint
        font.family: root.c.font; font.pixelSize: 11
    }
    Text {
        id: chevron
        anchors.right: parent.right; anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        width: 14
        text: root.folder ? Icons.g("chevron-right") : ""
        font.family: Icons.family; font.pixelSize: 13
        color: root.selected ? root.c.accent : root.c.faint
    }
}
