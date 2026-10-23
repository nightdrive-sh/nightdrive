import QtQuick
import qs.kit

// A yes-or-no question before what can't be undone (deleting a snapshot): the question, a line on what it means, and
// the button that does it. Return answers yes, Esc or a click outside no.
AppPanel {
    id: root
    property string question
    property string detail
    property string action: "Delete"
    signal answered(bool ok)
    cardWidth: 440
    onOutsideTapped: answered(false)
    onVisibleChanged: if (visible) forceActiveFocus()
    Keys.onReturnPressed: answered(true)
    Keys.onEnterPressed: answered(true)
    Keys.onEscapePressed: answered(false)

    Text {
        width: parent.width
        wrapMode: Text.Wrap
        text: root.question
        color: root.c.title; font.family: root.c.font; font.pixelSize: 15; font.weight: Font.Medium
    }
    Text {
        visible: root.detail !== ""
        width: parent.width
        wrapMode: Text.Wrap
        text: root.detail
        color: root.c.dim; font.family: root.c.font; font.pixelSize: 12
    }
    Row {
        spacing: 8
        AppButton { c: root.c; glyph: "trash-2"; label: root.action; strong: true; keys: "⏎"; onClicked: root.answered(true) }
        AppButton { c: root.c; label: "Cancel"; keys: "Esc"; onClicked: root.answered(false) }
    }
}
