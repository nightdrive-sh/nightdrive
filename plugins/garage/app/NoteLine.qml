import QtQuick
import qs
import qs.kit

// What went wrong, at the foot of the page: garage-ctl's message (a line it means to be read: "Another VM has the ssh port"),
// in the danger colour, until ✕ or the next call, which starts with no error (VmCtl.next). Two lines at most; the whole
// of a longer one is in the log (`garage log`).
Rectangle {
    id: root
    required property QtObject c
    property string text: ""
    signal dismissed()
    visible: text !== ""
    implicitHeight: Math.max(36, line.implicitHeight + 16)
    radius: 8
    color: Qt.rgba(c.danger.r, c.danger.g, c.danger.b, 0.12)
    border.color: Qt.rgba(c.danger.r, c.danger.g, c.danger.b, 0.4)

    Text {
        id: glyph
        x: 12; anchors.verticalCenter: parent.verticalCenter
        text: Icons.g("triangle-alert"); font.family: Icons.family; font.pixelSize: 13
        color: root.c.danger
    }
    Text {
        id: line
        anchors.left: glyph.right; anchors.leftMargin: 10
        anchors.right: close.left; anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        wrapMode: Text.Wrap
        maximumLineCount: 2
        elide: Text.ElideRight
        text: root.text
        color: root.c.text; font.family: root.c.font; font.pixelSize: 12
    }
    AppIconButton {
        id: close
        anchors.right: parent.right; anchors.rightMargin: 6; anchors.verticalCenter: parent.verticalCenter
        c: root.c; glyph: "x"; glyphSize: 12; tip: "Dismiss"; tipSide: "above"
        onClicked: root.dismissed()
    }
}
