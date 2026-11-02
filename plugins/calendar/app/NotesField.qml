import QtQuick

// The event's notes: a few lines in a frame, as the kit's AppField is one line only. ⏎ is a new line here, so Ctrl+⏎
// saves (save), and Tab leaves for the next field rather than typing a tab, as in the panel's other fields.
Column {
    id: root
    required property QtObject c
    property alias text: edit.text
    signal save()
    signal escaped()
    spacing: 6
    Text { text: "Notes"; color: root.c.title; font.family: root.c.font; font.pixelSize: 13 }
    Rectangle {
        width: root.width; height: 74; radius: 7
        color: "transparent"
        border.color: edit.activeFocus ? root.c.primary : root.c.line
        clip: true
        TextEdit {
            id: edit
            anchors.fill: parent; anchors.margins: 9; anchors.leftMargin: 10; anchors.rightMargin: 10
            textFormat: TextEdit.PlainText
            wrapMode: TextEdit.Wrap
            color: root.c.text; font.family: root.c.font; font.pixelSize: 13
            selectionColor: root.c.sel; selectByMouse: true
            activeFocusOnTab: true
            Keys.onPressed: e => {
                const ctrl = e.modifiers & (Qt.ControlModifier | Qt.MetaModifier)
                if (ctrl && (e.key === Qt.Key_Return || e.key === Qt.Key_Enter)) root.save()
                else if (e.key === Qt.Key_Escape) root.escaped()
                else if (e.key === Qt.Key_Tab) nextItemInFocusChain(true).forceActiveFocus()
                else if (e.key === Qt.Key_Backtab) nextItemInFocusChain(false).forceActiveFocus()
                else return
                e.accepted = true
            }
        }
    }
}
