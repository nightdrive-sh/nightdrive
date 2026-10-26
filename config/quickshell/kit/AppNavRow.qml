import QtQuick
import QtQuick.Layouts
import qs

// A row of the sidebar: a glyph, a name and a count on the right. Picked, its glyph takes the accent and its name the title
// colour. Anything put inside it (a button that shows under the pointer) lies over the row.
Rectangle {
    id: root
    required property QtObject c
    property string glyph
    property string label
    property string count: ""
    property color countColor: c.faint
    property bool selected: false
    property bool dropTarget: false     // something dragged over it would land here
    property bool active: false         // the keyboard is in the sidebar (Tab): the picked row has a frame of the accent
    readonly property alias hovered: hover.hovered
    signal clicked()
    Layout.fillWidth: true
    Layout.leftMargin: 12
    Layout.rightMargin: 12
    implicitHeight: 34
    radius: 8
    color: selected ? c.sel : hovered || dropTarget ? c.hover : "transparent"
    // Tab's frame, as AppRow's: the list beside it shows its row only marked meanwhile
    border.color: dropTarget ? c.primary : selected && active ? c.frame : "transparent"
    border.width: selected && active && !dropTarget ? 2 : 1
    HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
    TapHandler { onTapped: root.clicked() }
    Text {
        id: glyphText
        anchors.left: parent.left; anchors.leftMargin: 14; anchors.verticalCenter: parent.verticalCenter
        text: Icons.g(root.glyph); font.family: Icons.family; font.pixelSize: 15
        color: root.selected ? root.c.accent : root.c.dim
    }
    // A long name in a narrow sidebar gives way to the count (cut short with …), never under it
    Text {
        anchors.left: glyphText.right; anchors.leftMargin: 12; anchors.verticalCenter: parent.verticalCenter
        anchors.right: countText.left; anchors.rightMargin: root.count === "" ? 0 : 8
        elide: Text.ElideRight
        text: root.label; font.family: root.c.font; font.pixelSize: 13
        color: root.selected ? root.c.title : root.c.dim
    }
    Text {
        id: countText
        anchors.right: parent.right; anchors.rightMargin: 16; anchors.verticalCenter: parent.verticalCenter
        text: root.count
        font.family: root.c.font; font.pixelSize: 11; color: root.countColor
    }
}
