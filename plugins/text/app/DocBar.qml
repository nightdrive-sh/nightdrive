import QtQuick
import Quickshell
import qs.kit

// The bar over the open file, as high as the sidebar's header so their line runs on: its name and folder, whether it is
// saved, and the buttons (Save; with a conflict its two ways out). With no file open, Open and New alone.
Item {
    id: root
    required property QtObject c
    property QtObject doc: null
    signal open()
    signal newFile()
    signal save()
    signal keepMine()
    signal keepTheirs()
    signal close()
    height: 62

    readonly property string home: Quickshell.env("HOME") || ""
    function tilde(p) { return home && p.startsWith(home) ? "~" + p.slice(home.length) : p }

    readonly property var actions: !doc ? [
            { id: "open", glyph: "folder-open", label: "Open", tip: "Open a file", keys: "⌘O" },
            { id: "new", glyph: "file-plus", label: "New", tip: "A new file: where it goes first", keys: "⌘N" }]
        : doc.conflicted ? [
            { id: "mine", glyph: "save", label: "Keep mine", strong: true, tip: "Write yours over the one saved elsewhere", keys: "⌘S" },
            { id: "theirs", glyph: "rotate-ccw", label: "Take theirs", tip: "The file as it is now; yours is lost" }]
        : [
            { id: "save", glyph: "save", label: "Save", strong: doc.dirty || doc.gone, tip: "Save the file", keys: "⌘S" },
            { id: "close", glyph: "x", label: "Close", tip: "Close the file", keys: "⌘W" }]

    Column {
        anchors.left: parent.left; anchors.leftMargin: 28
        anchors.right: buttons.left; anchors.rightMargin: 16
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2
        Text {
            width: parent.width
            elide: Text.ElideRight
            textFormat: Text.PlainText
            text: root.doc ? root.doc.name + (root.doc.dirty ? " •" : "") : "No file open"
            font.family: root.c.font; font.pixelSize: 15; font.weight: Font.Medium
            color: root.doc ? root.c.title : root.c.dim
        }
        Text {
            width: parent.width
            elide: Text.ElideMiddle
            textFormat: Text.PlainText
            visible: !!root.doc
            text: !root.doc ? "" : root.tilde(root.doc.dir) + (root.doc.status ? "  ·  " + root.doc.status : "")
            font.family: root.c.font; font.pixelSize: 12
            color: root.doc && (root.doc.conflicted || root.doc.gone) ? root.c.danger : root.c.faint
        }
    }
    Row {
        id: buttons
        anchors.right: parent.right; anchors.rightMargin: 16
        anchors.verticalCenter: parent.verticalCenter
        spacing: 4
        Repeater {
            model: root.actions
            AppBarButton {
                required property var modelData
                c: root.c
                glyph: modelData.glyph; label: modelData.label; strong: !!modelData.strong
                tip: modelData.tip; keys: modelData.keys || ""; tipAlign: "right"
                compact: root.width < 520
                onClicked: {
                    const id = modelData.id
                    if (id === "open") root.open()
                    else if (id === "new") root.newFile()
                    else if (id === "save") root.save()
                    else if (id === "mine") root.keepMine()
                    else if (id === "theirs") root.keepTheirs()
                    else if (id === "close") root.close()
                }
            }
        }
    }
    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: root.c.divider }
}
