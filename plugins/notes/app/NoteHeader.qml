import QtQuick
import qs.kit

// The open note's header, at the top of its text as Mail's message header is (the buttons are NoteBar's): its title,
// large and whole (wrapped, not cut), then when it was saved and where its file is. Wide, the two share a line, the
// date whole and the path shortened in the middle; narrow, the path gets a line of its own.
Column {
    id: root
    required property QtObject c
    property var note: null              // Store.note
    property string folder: ""           // the notes' folder, for the path (~/Notes)
    readonly property bool wide: width >= 520
    spacing: 6

    Text {
        width: parent.width
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        text: root.note ? root.note.title : ""
        font.family: root.c.font; font.pixelSize: 22; font.weight: Font.Medium; font.letterSpacing: -0.2
        lineHeight: 1.1
        color: root.c.title
    }
    Item {
        width: parent.width
        height: root.wide ? dateText.implicitHeight : dateText.implicitHeight + pathText.implicitHeight + 2
        Text {
            id: dateText
            width: Math.min(implicitWidth, parent.width)
            elide: Text.ElideRight
            textFormat: Text.PlainText
            text: !root.note ? "" : Regional.format(new Date(root.note.modified), "medium")
                + "  " + Regional.format(new Date(root.note.modified), "time")
            font.family: root.c.font; font.pixelSize: 12; color: root.c.faint
        }
        Text {
            id: pathText
            x: root.wide ? dateText.width + 16 : 0
            y: root.wide ? 0 : dateText.implicitHeight + 2
            width: root.wide ? Math.max(0, parent.width - x) : parent.width
            visible: width > 40          // a path cut to a few letters says nothing
            elide: Text.ElideMiddle
            textFormat: Text.PlainText
            text: root.note ? root.folder + "/" + root.note.id : ""
            font.family: root.c.font; font.pixelSize: 12; color: root.c.faint
        }
    }
}
