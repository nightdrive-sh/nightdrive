import QtQuick
import "Format.js" as Format

// What the list or the grid says when it has no rows: an empty folder or trash, a filter or search that found
// nothing, a search without fd; and under it what to do next. FileList and FileGrid centre it in their view.
Column {
    id: root
    required property QtObject c
    required property var app
    visible: app.rows.length === 0 && (!app.loading || app.inArchive)
    readonly property var arc: app.archive
    spacing: 8
    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        textFormat: Text.PlainText
        text: root.app.inArchive && root.arc.loading ? "Reading " + Format.base(root.arc.file) + "…" + (root.arc.done > 0 ? " " + Math.floor(100 * root.arc.done) + " %" : "")
            : root.app.inArchive && root.arc.error ? root.arc.error
            : root.app.trashShown ? "The trash is empty"
            : root.app.searching && root.app.search.missing ? "Searching the folders below needs fd"
            : root.app.searching ? "Nothing " + (root.app.inHome ? "in home" : "here or below") + " named “" + root.app.filter.trim() + "”"
            : root.app.filter ? "Nothing here named “" + root.app.filter + "”" : "Empty folder"
        color: root.c.faint; font.family: root.c.font; font.pixelSize: 12
    }
    Text {
        visible: !root.app.trashShown
        anchors.horizontalCenter: parent.horizontalCenter
        text: root.app.inArchive && root.arc.loading ? (root.arc.done > 0 ? "A compressed tar is read from start to end, once: the next look is at once" : "")
            : root.app.inArchive && root.arc.error ? "← goes back"
            : root.app.inArchive && !root.app.filter ? "← goes back out" + (root.arc.skipped ? ", " + root.arc.skipped + " unsafe left out" : "")
            : root.app.searching && root.app.search.missing ? "sudo dnf install fd-find, then search again"
            : root.app.filter && !root.app.below ? (root.app.inHome ? "Tab searches all of home" : "Tab searches the folders below too") + ", Esc shows all"
            : root.app.filter ? "Esc shows all" : root.app.showHidden ? "a makes a file, p pastes" : ". shows the hidden ones, a makes a file"
        color: root.c.faint; font.family: root.c.font; font.pixelSize: 11
    }
}
