import QtQuick
import qs.kit

// The bar over the open note, as Mail's over a message: its buttons and nothing else, the note's title and date being
// the note's own header (NoteHeader.qml) at the top of what scrolls. Reading: Edit, New, Rename, Trash and Apostrophe
// (New also with no note at all). Writing: Done, or with a conflict its two ways out, and whether it is saved. In one
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
    readonly property bool narrow: width < 520     // the buttons give up their words

    AppIconButton {
        id: backButton
        visible: root.onePane
        anchors.left: parent.left; anchors.leftMargin: 16; anchors.verticalCenter: parent.verticalCenter
        c: root.c; glyph: "arrow-left"; tip: "The notes"; keys: "Esc"
        onClicked: root.back()
    }
    Row {
        id: buttons
        // Where it may start: after the back button in one pane, else over the note's text (less the button's padding)
        readonly property real start: root.onePane ? backButton.x + backButton.width + 8 : root.margin - 10
        readonly property real end: root.width - 16 - (statusText.visible ? statusText.width + 16 : 0)
        x: root.onePane ? Math.max(start, Math.min((root.width - width) / 2, end - width)) : start
        anchors.verticalCenter: parent.verticalCenter
        spacing: 8
        AppButton {
            visible: !root.editing && root.hasNote
            c: root.c; glyph: "pencil"; label: root.narrow ? "" : "Edit"; strong: true
            tip: "Write in it here"; keys: "⏎  e"
            onClicked: root.edit()
        }
        AppButton {
            visible: !root.editing
            c: root.c; glyph: "plus"; label: root.narrow ? "" : "New"
            tip: "New note"; keys: "n"
            onClicked: root.newNote()
        }
        AppIconButton {
            visible: !root.editing && root.hasNote
            c: root.c; glyph: "text-cursor-input"; tip: "Rename"; keys: "F2  r"
            onClicked: root.rename()
        }
        AppIconButton {
            visible: !root.editing && root.hasNote
            c: root.c; glyph: "trash-2"; tip: "Move to the trash"; keys: "Del"
            onClicked: root.trash()
        }
        AppIconButton {
            visible: !root.editing && root.hasNote
            c: root.c; glyph: "external-link"; tip: "Open in Apostrophe"; keys: "⇧⏎"
            onClicked: root.apostrophe()
        }
        AppButton {
            visible: root.conflicted
            c: root.c; glyph: "save"; label: root.narrow ? "" : "Keep mine"; strong: true
            tip: "Write yours over the one saved elsewhere"; keys: "⌘S"
            onClicked: root.keepMine()
        }
        AppButton {
            visible: root.conflicted
            c: root.c; glyph: "rotate-ccw"; label: root.narrow ? "" : "Keep theirs"
            tip: "Drop what you wrote since, take the saved one"
            onClicked: root.keepTheirs()
        }
        AppButton {
            visible: root.editing && !root.conflicted
            c: root.c; glyph: "check"; label: root.narrow ? "" : "Done"; strong: true
            tip: "Back to reading (it saves by itself)"; keys: "Esc"
            onClicked: root.done()
        }
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
    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: root.c.divider }
}
