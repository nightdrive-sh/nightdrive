import QtQuick
import qs.kit

// Find (⌘F): a field under the bar; typing goes to the first place with the words after the cursor, ⏎ to the next,
// ⇧⏎ the one before, Esc back to the text with the place found selected. The open file does the finding (Doc.find).
Rectangle {
    id: root
    required property QtObject c
    property QtObject doc: null
    property bool open: false
    property bool missing: false
    signal closed()
    height: open ? 44 : 0
    visible: open
    color: "transparent"

    function show() {
        open = true
        const sel = doc ? doc.area.selectedText : ""
        if (sel && sel.indexOf(" ") < 0) field.text = sel      // a selection within a line is what to find
        field.forceActiveFocus()
        field.selectAll()
    }
    function next(back) { if (doc) missing = field.text !== "" && !doc.find(field.text, back) }
    function hide() { open = false; closed() }

    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: root.c.divider }
    AppSearchField {
        id: field
        anchors.left: parent.left; anchors.leftMargin: 24
        anchors.right: note.left; anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        c: root.c
        placeholder: "Find in the file"
        onEdited: {
            // From where the last find started, so each letter typed narrows the same place down
            if (root.doc) root.doc.area.cursorPosition = root.doc.area.selectionStart
            root.next(false)
        }
        onReturnPressed: root.next(false)
        onEscapePressed: root.hide()
        Keys.onPressed: e => {
            if ((e.key === Qt.Key_Return || e.key === Qt.Key_Enter) && (e.modifiers & Qt.ShiftModifier)) {
                root.next(true); e.accepted = true
            } else if (e.key === Qt.Key_G && (e.modifiers & (Qt.ControlModifier | Qt.MetaModifier))) {
                root.next(e.modifiers & Qt.ShiftModifier); e.accepted = true
            }
        }
    }
    Text {
        id: note
        anchors.right: parent.right; anchors.rightMargin: 24
        anchors.verticalCenter: parent.verticalCenter
        text: root.missing ? "Not found" : "⏎ next  ⇧⏎ previous"
        color: root.missing ? root.c.danger : root.c.faint
        font.family: root.c.font; font.pixelSize: 12
    }
}
