import QtQuick

// A labelled text of a few lines in a frame, for the panels (a task's note), as AppField is one line only. ⏎ is a new
// line here, so Ctrl+⏎ comes out as save; Tab leaves for the next field rather than typing a tab, as in the panel's
// other fields, and Esc comes out as escaped. A long text scrolls inside the frame.
Column {
    id: root
    required property QtObject c
    property string label
    property int boxHeight: 74
    property alias text: edit.text
    property alias input: edit
    signal save()
    signal escaped()
    spacing: 6
    Text { visible: root.label !== ""; text: root.label; color: root.c.title; font.family: root.c.font; font.pixelSize: 13 }
    Rectangle {
        width: root.width; height: root.boxHeight; radius: 7
        color: "transparent"
        border.color: edit.activeFocus ? root.c.primary : root.c.line
        clip: true
        Flickable {
            id: flick
            anchors.fill: parent; anchors.margins: 9; anchors.leftMargin: 10; anchors.rightMargin: 10
            contentWidth: width; contentHeight: edit.implicitHeight
            boundsBehavior: Flickable.StopAtBounds
            // The caret stays in sight as the text grows past the frame
            function follow(r) {
                if (r.y < contentY) contentY = r.y
                else if (r.y + r.height > contentY + height) contentY = r.y + r.height - height
            }
            TextEdit {
                id: edit
                width: flick.width
                textFormat: TextEdit.PlainText
                wrapMode: TextEdit.Wrap
                color: root.c.text; font.family: root.c.font; font.pixelSize: 13
                selectionColor: root.c.sel; selectByMouse: true
                activeFocusOnTab: true
                onCursorRectangleChanged: flick.follow(cursorRectangle)
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
}
