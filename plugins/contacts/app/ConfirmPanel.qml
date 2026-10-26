import QtQuick
import qs.kit

// A question before what can't be undone (deleting a contact, leaving the editor without saving): Return does it, Esc
// or a click outside doesn't. ask() shows it and takes the keys; the window gets them back from closed().
AppPanel {
    id: root
    property string title: ""
    property string text: ""
    property string action: ""
    property string keepText: "Cancel"
    property var onYes: null
    signal closed()
    visible: false
    cardWidth: 460

    function ask(title, text, action, yes) {
        root.title = title; root.text = text; root.action = action; onYes = yes
        visible = true
        forceActiveFocus()
    }
    function answer(yes) {
        visible = false
        const f = onYes
        onYes = null
        closed()
        if (yes && f) f()
    }
    onOutsideTapped: answer(false)
    Keys.onPressed: e => {
        if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) answer(true)
        else if (e.key === Qt.Key_Escape) answer(false)
        e.accepted = true
    }
    Text { text: root.title; color: c.title; font.family: c.font; font.pixelSize: 15; font.weight: Font.Medium }
    Text {
        visible: root.text !== ""
        width: parent.width; wrapMode: Text.Wrap; lineHeight: 1.2
        text: root.text; color: c.dim; font.family: c.font; font.pixelSize: 12
    }
    // As Garage's questions: the yes first, filled, each with its key
    Row {
        spacing: 8
        PanelButton { c: root.c; label: root.action; strong: true; keys: ["Enter"]; onClicked: root.answer(true) }
        PanelButton { c: root.c; label: root.keepText; keys: ["Esc"]; onClicked: root.answer(false) }
    }
}
