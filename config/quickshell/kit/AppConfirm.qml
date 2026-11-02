import QtQuick
import qs.kit

// A yes-or-no question before what can't be undone (Garage: deleting or restoring a snapshot): the question, a line on
// what it means, and the button that does it (action). Return answers yes, Esc or a click outside no; the app shows and
// hides it (visible) and acts on answered.
AppPanel {
    id: root
    property string question
    property string detail
    property string action: "Delete"
    property string glyph: "trash-2"      // what the action is, for the app to keep with it; the card draws no glyph
    signal answered(bool ok)
    cardWidth: 440
    onOutsideTapped: answered(false)
    onVisibleChanged: if (visible) forceActiveFocus()
    Keys.onReturnPressed: answered(true)
    Keys.onEnterPressed: answered(true)
    Keys.onEscapePressed: answered(false)

    // Plain text: a question may quote what others wrote (an event's title from an invitation), and rich text would
    // style it or load an image it names
    Text {
        textFormat: Text.PlainText
        width: parent.width
        wrapMode: Text.Wrap
        text: root.question
        color: root.c.title; font.family: root.c.font; font.pixelSize: 15; font.weight: Font.Medium
    }
    Text {
        visible: root.detail !== ""
        textFormat: Text.PlainText
        width: parent.width
        wrapMode: Text.Wrap
        text: root.detail
        color: root.c.dim; font.family: root.c.font; font.pixelSize: 12
    }
    Row {
        spacing: 8
        AppPanelButton { c: root.c; label: root.action; strong: true; keys: ["Enter"]; onClicked: root.answered(true) }
        AppPanelButton { c: root.c; label: "Cancel"; keys: ["Esc"]; onClicked: root.answered(false) }
    }
}
