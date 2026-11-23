import QtQuick
import qs

// One choice in the settings panel (a resolution, a scale, a rate): its words, a quieter note at the right. The one in
// use is filled and its words lit, with a check at the far right, so every label starts at the same place. A click
// picks one; the one in use does nothing.
Rectangle {
    id: root
    required property QtObject c
    property string label
    property string note: ""
    property bool current: false
    signal picked()
    // Out past the column by its padding on both sides, so its words line up with the section titles above
    readonly property int inset: 10
    x: -inset
    width: (parent ? parent.width : 200) + 2 * inset
    height: 30
    radius: 6
    color: current ? Qt.rgba(c.sel.r, c.sel.g, c.sel.b, 0.7) : hover.hovered ? c.hover : "transparent"
    HoverHandler { id: hover; cursorShape: root.current ? Qt.ArrowCursor : Qt.PointingHandCursor }
    TapHandler { onTapped: if (!root.current) root.picked() }

    Text {
        anchors { left: parent.left; leftMargin: root.inset; right: noteText.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
        elide: Text.ElideRight
        text: root.label
        color: root.current ? root.c.title : root.c.text; font.family: root.c.font; font.pixelSize: 12
    }
    Text {
        id: noteText
        anchors { right: check.left; rightMargin: root.current ? 8 : 0; verticalCenter: parent.verticalCenter }
        text: root.note
        color: root.c.dim; font.family: root.c.font; font.pixelSize: 11
    }
    Text {
        id: check
        anchors { right: parent.right; rightMargin: root.inset; verticalCenter: parent.verticalCenter }
        visible: root.current
        text: root.current ? Icons.g("check") : ""       // empty: no width, so the note goes to the edge
        font.family: Icons.family; font.pixelSize: 12; color: root.c.accent
    }
}
