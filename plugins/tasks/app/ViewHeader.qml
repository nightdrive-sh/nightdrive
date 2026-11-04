import QtQuick
import QtQuick.Layouts
import qs.kit

// The view's name over its tasks, level with the sidebar's title, and what can be done there: Rename and Delete when
// the view is a list (#2022), Search (#2023) and New always. The buttons give up their words as the room goes, Rename and Delete first,
// so the name keeps what is left and is cut short with … rather than pushed under them.
RowLayout {
    id: root
    required property QtObject c
    required property var app            // the window: view, shown, newTask(), lists (ListActions)
    signal renameList()
    signal removeList()
    signal search()
    readonly property bool isList: app.view.kind === "list"
    readonly property bool compact: width < 600     // Rename and Delete as their glyphs alone
    readonly property bool tiny: width < 400        // New too

    Text {
        textFormat: Text.PlainText
        Layout.fillWidth: true
        elide: Text.ElideRight
        text: root.app.view.name
        color: root.c.title; font.family: root.c.font; font.pixelSize: 15; font.weight: Font.Medium
    }
    Text {
        textFormat: Text.PlainText
        text: root.app.shown.length ? root.app.shown.length + (root.app.view.kind === "done" ? " done" : " open") : ""
        color: root.c.faint; font.family: root.c.font; font.pixelSize: 11
    }
    // Higher than the header's text (AppButton's 28): it reaches a little over and under it
    AppButton {
        visible: root.isList
        Layout.leftMargin: 12
        c: root.c; glyph: "pencil"; label: root.compact ? "" : "Rename"; tip: "Rename the list"; keys: "F2"
        onClicked: root.renameList()
    }
    AppButton {
        visible: root.isList
        Layout.leftMargin: 4
        c: root.c; glyph: "trash-2"; label: root.compact ? "" : "Delete"; tip: "Delete the list"
        onClicked: root.removeList()
    }
    // Its glyph alone at every width: / and ⌘F are how it is mostly opened, and the tip says so
    AppButton {
        Layout.leftMargin: root.isList ? 4 : 12
        c: root.c; glyph: "search"; label: ""; tip: "Search every list"; keys: "/"
        onClicked: root.search()
    }
    AppButton {
        Layout.leftMargin: 4
        c: root.c; glyph: "plus"; label: root.tiny ? "" : "New"; tip: "New task"; keys: "n"; tipAlign: "right"
        onClicked: root.app.newTask("")
    }
}
