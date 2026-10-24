import QtQuick
import qs
import qs.kit

// A key at the bottom of the Welcome window, as a button big enough to hit with the mouse (the VM test found the kit's
// AppKeyAction, a key and a word, too small for the window's few controls): its key, its word, and a glyph after it
// (Next's arrow). Strong, it is the one to press, filled as a picked row.
Rectangle {
    id: root
    required property QtObject c
    property string keys: ""
    property string label
    property string glyph: ""
    property bool strong: false
    readonly property alias hovered: hover.hovered
    signal clicked()
    implicitWidth: row.implicitWidth + 32; implicitHeight: 40; radius: 8
    color: strong ? c.sel : hovered ? c.hover : "transparent"
    border.color: strong ? c.primary : c.faint      // the kit's c.line is too faint to show a button
    HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
    TapHandler { onTapped: root.clicked() }
    Row {
        id: row
        anchors.centerIn: parent
        spacing: 10
        // The key bare, without the kit's box (KeyCap), in the accent colour: Jari's #1538 review. An arrow or ⏎ is
        // its Lucide glyph, as in KeyCap; a word (esc) is text.
        Text {
            visible: root.keys !== ""
            anchors.verticalCenter: parent.verticalCenter
            readonly property string glyph: ({ "←": "arrow-left", "→": "arrow-right", "⏎": "corner-down-left" })[root.keys] || ""
            text: glyph ? Icons.g(glyph) : root.keys
            font.family: glyph ? Icons.family : root.c.font; font.pixelSize: glyph ? 14 : 12
            color: root.c.primary
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.label; font.family: root.c.font; font.pixelSize: 13
            font.weight: root.strong ? Font.Medium : Font.Normal
            color: root.strong || root.hovered ? root.c.title : root.c.text
        }
        Text {
            visible: root.glyph !== ""
            anchors.verticalCenter: parent.verticalCenter
            text: Icons.g(root.glyph); font.family: Icons.family; font.pixelSize: 14
            color: root.strong ? root.c.accent : root.c.dim
        }
    }
}
