import QtQuick
import QtQuick.Layouts
import qs.kit

// The search (/, ⌘F) in the header's place: the kit's field over every list, how many it found, and a button to end it.
// ⏎ and ↓ give the keys to the tasks found, Esc ends the search and the view picked before comes back (shell.qml).
RowLayout {
    id: root
    required property QtObject c
    required property var app            // the window: query, shown, toList(), closeSearch()
    property alias field: field
    spacing: 12

    AppSearchField {
        id: field
        Layout.fillWidth: true
        c: root.c
        pixelSize: 14
        placeholder: "Search every list"
        onEdited: root.app.query = text
        onReturnPressed: root.app.toList()
        onDownPressed: root.app.toList()
        onEscapePressed: root.app.closeSearch()
    }
    Text {
        textFormat: Text.PlainText
        visible: root.app.query.trim() !== ""
        text: root.app.shown.length + " found"
        color: root.c.faint; font.family: root.c.font; font.pixelSize: 11
    }
    AppIconButton {
        c: root.c; glyph: "x"; tip: "End the search"; keys: "Esc"; tipAlign: "right"
        onClicked: root.app.closeSearch()
    }
}
