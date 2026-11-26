import QtQuick
import qs
import "Words.js" as Words

// One right of an area's row: Allow, Ask or No in a frame with ▾, which opens the menu (ChoiceMenu). A right the area
// has no tools for is a dash. A value set apart from the level has a dot, so the user's own choices stand out.
Item {
    id: root
    required property QtObject c
    property var info: null             // the summary's { value, preset, own, choices, words, tools }, or null
    property bool current: false        // the keyboard is on this cell
    signal clicked()
    implicitHeight: 28

    readonly property color tint: !info ? c.faint : info.value === "allow" ? c.text
                                : info.value === "ask" ? Theme.warning : c.dim

    Text {
        visible: !root.info
        anchors.centerIn: parent
        text: "–"; color: root.c.faint
        font { family: root.c.font; pixelSize: 13 }
    }
    Rectangle {
        visible: !!root.info
        anchors { left: parent.left; verticalCenter: parent.verticalCenter }
        width: Math.min(parent.width - 12, 96); height: 26; radius: 7
        color: hover.hovered ? root.c.hover : "transparent"
        border.color: root.current ? root.c.primary : root.c.line
        border.width: root.current ? 2 : 1
        HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: root.clicked() }
        Rectangle {
            visible: !!root.info && root.info.own
            x: 7; anchors.verticalCenter: parent.verticalCenter
            width: 5; height: 5; radius: 2.5; color: root.c.primary
        }
        Text {
            x: 16; anchors.verticalCenter: parent.verticalCenter
            text: root.info ? Words.VALUE_NAMES[root.info.value] : ""
            color: root.tint
            font { family: root.c.font; pixelSize: 13; weight: root.info && root.info.value === "ask" ? Font.DemiBold : Font.Normal }
        }
        Text {
            anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
            text: Icons.g("chevron-down"); color: root.c.dim
            font { family: Icons.family; pixelSize: 12 }
        }
    }
}
