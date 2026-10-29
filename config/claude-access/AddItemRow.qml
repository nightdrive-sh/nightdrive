import QtQuick
import qs
import qs.kit

// The last row of a list the user types into (Access › Mail's blocked senders, domains and tags, Dashboard #1789): a
// field that adds what is written on Enter, if it is what the list takes (areas.py's `item` pattern, which access.py
// checks again). Picked by ↑ ↓ it takes the keys, and gives ↑ ↓ back to the panel (moved); Esc empties it, then closes.
Rectangle {
    id: row
    required property QtObject c
    property var option: ({})           // the list choice: { item, item_words }
    property bool picked: false
    signal added(string text)
    signal moved(int d)
    signal clicked()
    signal escaped()
    readonly property bool valid: {
        const t = input.text.trim()
        if (!t) return false
        try { return !option.item || new RegExp("^(?:" + option.item + ")$").test(t) } catch (e) { return false }
    }
    property bool tried: false          // Enter on what isn't an entry: say what is
    implicitHeight: body.implicitHeight + 12
    radius: 6
    color: picked ? c.sel : hover.hovered ? c.hover : "transparent"

    onPickedChanged: if (picked) input.forceActiveFocus()

    HoverHandler { id: hover; cursorShape: Qt.IBeamCursor }
    TapHandler { onTapped: { row.clicked(); input.forceActiveFocus() } }

    Row {
        id: body
        x: 8; y: 6
        width: parent.width - 16
        spacing: 10
        Text {
            text: Icons.g("plus")
            color: row.picked ? row.c.accent : row.c.dim
            font { family: Icons.family; pixelSize: 16 }
        }
        Column {
            width: parent.width - 26
            spacing: 2
            TextInput {
                id: input
                width: parent.width
                color: row.c.text
                selectionColor: row.c.sel
                font { family: row.c.font; pixelSize: 13 }
                onTextEdited: row.tried = false
                Text {
                    visible: !input.text
                    width: input.width
                    elide: Text.ElideRight
                    text: "Add " + (row.option.item_words || "an entry") + ", then Enter"
                    color: row.c.faint
                    font: input.font
                }
                Keys.onPressed: e => {
                    if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
                        if (row.valid) { row.added(input.text.trim()); input.text = "" }
                        else row.tried = !!input.text.trim()
                    } else if (e.key === Qt.Key_Up || e.key === Qt.Key_Down) {
                        row.moved(e.key === Qt.Key_Up ? -1 : 1)
                    } else if (e.key === Qt.Key_Escape) {
                        if (input.text) { input.text = ""; row.tried = false }
                        else row.escaped()
                    } else {
                        return
                    }
                    e.accepted = true
                }
            }
            Text {
                visible: row.tried
                width: parent.width
                text: "That isn't " + (row.option.item_words || "an entry") + "."
                wrapMode: Text.Wrap
                color: row.c.danger
                font { family: row.c.font; pixelSize: 12 }
            }
        }
    }
}
