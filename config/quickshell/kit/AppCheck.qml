import QtQuick
import qs

// A box to tick and its word, for the panels (All day, Important): a click or Space turns it, ⏎ comes out as accepted
// (the panel saves). Tab reaches it; the frame shows when the keys are on it.
Item {
    id: root
    required property QtObject c
    property string label
    property bool on: false
    signal toggled()                    // after on has turned
    signal accepted()
    activeFocusOnTab: true
    implicitWidth: row.implicitWidth
    implicitHeight: 22

    function toggle() { on = !on; toggled() }
    Keys.onPressed: e => {
        if (e.key === Qt.Key_Space) toggle()
        else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) accepted()
        else return
        e.accepted = true
    }
    TapHandler { onTapped: { root.toggle(); root.forceActiveFocus() } }
    HoverHandler { cursorShape: Qt.PointingHandCursor }
    Row {
        id: row
        spacing: 8
        anchors.verticalCenter: parent.verticalCenter
        Rectangle {
            width: 16; height: 16; radius: 4
            color: root.on ? root.c.sel : "transparent"
            border.color: root.activeFocus ? root.c.primary : root.c.line
            Text {
                anchors.centerIn: parent
                visible: root.on
                text: Icons.g("check"); font.family: Icons.family; font.pixelSize: 11
                color: root.c.title
            }
        }
        Text { text: root.label; color: root.c.text; font.family: root.c.font; font.pixelSize: 13 }
    }
}
