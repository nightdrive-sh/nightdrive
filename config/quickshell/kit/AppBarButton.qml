import QtQuick
import qs

// A button of the bar over what a view shows (the actions over Mail's message, over Notes' note): no frame, its glyph
// and name dim until the pointer is on it, a quiet fill then. strong, the one Enter presses, is filled and lit all along.
// compact drops the name, so a narrow bar keeps the glyphs and the tip says the rest. The tip goes below it, from its
// left edge (tipAlign "right" for one at the bar's end, so it stays inside the window). Under the pointer it rises over
// its neighbours, which would otherwise draw over its tip.
Rectangle {
    id: root
    required property QtObject c
    property string glyph: ""
    property string label: ""
    property bool compact: false
    property bool strong: false        // what Enter does (Notes' Edit): a quiet fill and the accent, still no frame
    property string tip: ""
    property string keys: ""
    property string tipAlign: "left"
    readonly property alias hovered: hover.hovered
    signal clicked()
    implicitWidth: row.implicitWidth + 20
    implicitHeight: 30
    radius: 8
    z: hovered ? 1 : 0
    color: strong ? (hovered ? c.sel : c.hover) : hovered ? c.hover : "transparent"
    HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
    TapHandler { onTapped: root.clicked() }
    Row {
        id: row
        anchors.centerIn: parent
        spacing: 7
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: Icons.g(root.glyph); font.family: Icons.family; font.pixelSize: 14
            color: root.strong ? root.c.accent : root.hovered ? root.c.text : root.c.dim
        }
        Text {
            visible: !root.compact && root.label !== ""
            anchors.verticalCenter: parent.verticalCenter
            text: root.label; font.family: root.c.font; font.pixelSize: 12
            color: root.strong ? root.c.title : root.hovered ? root.c.text : root.c.dim
        }
    }
    Tip { x: root.tipAlign === "right" ? parent.width - width : 0; y: parent.height + 6; c: root.c; text: root.tip; keys: root.keys; hovered: root.hovered }
}
