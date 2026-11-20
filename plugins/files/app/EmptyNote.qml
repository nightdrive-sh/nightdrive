import QtQuick

// What the list or the grid says when it has no rows: an empty folder or trash, a filter or search that found
// nothing, a search without fd; and under it what to do next. FileList and FileGrid centre it in their view.
Column {
    id: root
    required property QtObject c
    required property var app
    visible: app.rows.length === 0 && !app.loading
    spacing: 8
    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        textFormat: Text.PlainText
        text: root.app.trashShown ? "The trash is empty"
            : root.app.searching && root.app.search.missing ? "Searching the folders below needs fd"
            : root.app.searching ? "Nothing " + (root.app.inHome ? "in home" : "here or below") + " named “" + root.app.filter.trim() + "”"
            : root.app.filter ? "Nothing here named “" + root.app.filter + "”" : "Empty folder"
        color: root.c.faint; font.family: root.c.font; font.pixelSize: 12
    }
    Text {
        visible: !root.app.trashShown
        anchors.horizontalCenter: parent.horizontalCenter
        text: root.app.searching && root.app.search.missing ? "sudo dnf install fd-find, then search again"
            : root.app.filter && !root.app.below ? (root.app.inHome ? "Tab searches all of home" : "Tab searches the folders below too") + ", Esc shows all"
            : root.app.filter ? "Esc shows all" : root.app.showHidden ? "a makes a file, p pastes" : ". shows the hidden ones, a makes a file"
        color: root.c.faint; font.family: root.c.font; font.pixelSize: 11
    }
}
