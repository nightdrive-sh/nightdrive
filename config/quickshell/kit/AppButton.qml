import QtQuick
import qs

// A button with a frame: a glyph and a label, for what the view on show can do (Play, Queue, New list). Strong, it is the
// one to press (filled, as a picked row); on, its glyph is lit for a state that holds (playing, on the shelf). The tip
// tells what it does and its key, below it and ending at its right edge, as such buttons sit at the window's right
// (tipAlign "left" for one at its left: it starts at its left edge, so a clipping page doesn't cut it). Under the pointer
// it rises over its neighbours, which would otherwise draw over its tip. Without a label (a narrow window) it is the
// glyph alone, and the tip says the rest.
Rectangle {
    id: root
    required property QtObject c
    property string glyph: ""
    property string label
    property bool strong: false
    property bool on: false
    property string tip: ""
    property string keys: ""
    property string tipAlign: "right"      // the tip's edge that lines up with the button's: "right" or "left"
    readonly property alias hovered: hover.hovered
    signal clicked()
    implicitWidth: row.implicitWidth + 24; implicitHeight: 28; radius: 7
    z: hovered ? 1 : 0
    color: strong ? c.sel : hovered ? c.hover : "transparent"
    border.color: strong ? c.primary : c.line
    HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
    TapHandler { onTapped: root.clicked() }
    Row {
        id: row
        anchors.centerIn: parent
        spacing: 8
        Text {
            visible: root.glyph !== ""
            anchors.verticalCenter: parent.verticalCenter
            text: Icons.g(root.glyph); font.family: Icons.family; font.pixelSize: 13
            color: root.strong ? root.c.accent : root.on ? root.c.primary : root.c.dim
        }
        Text {
            visible: root.label !== ""
            anchors.verticalCenter: parent.verticalCenter
            text: root.label; font.family: root.c.font; font.pixelSize: 12
            color: root.strong || root.hovered ? root.c.title : root.c.text
        }
    }
    Tip { x: root.tipAlign === "left" ? 0 : parent.width - width; y: parent.height + 8; c: root.c; text: root.tip; keys: root.keys; hovered: root.hovered }
}
