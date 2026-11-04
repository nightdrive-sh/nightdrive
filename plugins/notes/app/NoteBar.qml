import QtQuick
import qs.kit

// The bar over the open note, as Mail's over a message: its buttons and nothing else, the note's title and date being
// the note's own header (NoteHeader.qml) at the top of what scrolls. Reading: Edit, Rename, Trash and Apostrophe, and New at
// the bar's end (also with no note at all). Writing: Done, or with a conflict its two ways out, and whether it is saved. In one
// pane a back button to the list first, and the buttons centred in the room after it, as in Mail. As high as the
// sidebars' headers, so the line under it runs on under their titles and the search (AppSidebar.headerLine).
Item {
    id: root
    required property QtObject c
    property bool onePane: false
    property bool editing: false
    property bool hasNote: false
    property bool conflicted: false
    property string status: ""           // NoteEditor.status, while writing
    property int margin: 40              // the note's own, so the first button stands over its text
    signal back()
    signal edit()
    signal newNote()
    signal rename()
    signal trash()
    signal apostrophe()
    signal keepTheirs()
    signal keepMine()
    signal done()
    height: 62
    // What the bar offers now, as Mail's actions: each a kit AppBarButton (frameless, as Mail's), its name shown while every name fits (labels)
    readonly property var actions: editing ? (conflicted ? [
            { id: "mine", glyph: "save", label: "Keep mine", strong: true, tip: "Write yours over the one saved elsewhere", keys: "⌘S" },
            { id: "theirs", glyph: "rotate-ccw", label: "Keep theirs", tip: "Drop what you wrote since, take the saved one", keys: "" }
        ] : [
            { id: "done", glyph: "check", label: "Done", strong: true, tip: "Back to reading (it saves by itself)", keys: "Esc" }
        ]) : !hasNote ? [] : [
            { id: "edit", glyph: "pencil", label: "Edit", strong: true, tip: "Write in it here", keys: "⏎  e" },
            { id: "rename", glyph: "text-cursor-input", label: "Rename", tip: "Rename", keys: "F2  r" },
            { id: "trash", glyph: "trash-2", label: "Trash", tip: "Move to the trash", keys: "Del" },
            { id: "apostrophe", glyph: "external-link", label: "Apostrophe", tip: "Open in Apostrophe", keys: "⇧⏎" }
        ]
    function act(id) {
        if (id === "edit") edit()
        else if (id === "rename") rename()
        else if (id === "trash") trash()
        else if (id === "apostrophe") apostrophe()
        else if (id === "mine") keepMine()
        else if (id === "theirs") keepTheirs()
        else if (id === "done") done()
    }
    // Names on while the buttons with their names and New's (or the saved state) fit beside each other; else glyphs
    // alone, and the tips say the rest. Measured from copies with their names, as Mail measures its bar.
    readonly property real start: onePane ? backButton.x + backButton.width + 8 : margin - 10
    readonly property real endWidth: editing ? statusText.implicitWidth : newFull.implicitWidth
    readonly property bool labels: fullRow.implicitWidth + 16 + endWidth + 14 <= width - start

    // Under the buttons, so their tips lie over it (NoteView puts the whole bar over the note's text)
    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: root.c.divider }

    Row {
        id: fullRow
        visible: false
        spacing: 2
        Repeater { model: root.actions; delegate: AppBarButton { required property var modelData; c: root.c; glyph: modelData.glyph; label: modelData.label } }
    }
    AppBarButton { id: newFull; visible: false; c: root.c; glyph: "plus"; label: "New" }

    AppIconButton {
        id: backButton
        visible: root.onePane
        anchors.left: parent.left; anchors.leftMargin: 16; anchors.verticalCenter: parent.verticalCenter
        c: root.c; glyph: "arrow-left"; tip: "The notes"; keys: "Esc"; tipAlign: "left"
        onClicked: root.back()
    }
    Row {
        id: buttons
        // In one pane centred in the room after the back button, as in Mail
        readonly property real end: root.width - 14 - (statusText.visible ? statusText.width : newButton.width) - 16
        x: root.onePane ? Math.max(root.start, Math.min((root.width - width) / 2, end - width)) : root.start
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2
        Repeater {
            model: root.actions
            delegate: AppBarButton {
                required property var modelData
                c: root.c; glyph: modelData.glyph; label: modelData.label; compact: !root.labels; strong: !!modelData.strong
                tip: modelData.tip; keys: modelData.keys
                onClicked: root.act(modelData.id)
            }
        }
    }
    // New at the bar's end, apart from what acts on the open note (it shows with no note at all, too)
    AppBarButton {
        id: newButton
        visible: !root.editing
        anchors.right: parent.right; anchors.rightMargin: 14; anchors.verticalCenter: parent.verticalCenter
        c: root.c; glyph: "plus"; label: "New"; compact: !root.labels && root.hasNote
        tip: "New note"; keys: "n"; tipAlign: "right"
        onClicked: root.newNote()
    }
    // While writing, whether what is written is saved, at the bar's end: the editor's own first line is the title
    Text {
        id: statusText
        visible: root.editing
        anchors.right: parent.right; anchors.rightMargin: 20; anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: root.status
        font.family: root.c.font; font.pixelSize: 12
        color: root.conflicted ? root.c.danger : root.c.faint
    }
}
