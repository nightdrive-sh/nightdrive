import QtQuick
import qs
import qs.kit

// A task in the list: its circle (ticked when done), the title, and a line with when it's due (red once late), its list
// (in the views that mix lists) and the note's first line. The picked row shows the whole note: there is no other pane.
AppRow {
    id: row
    required property var modelData
    required property int index
    required property var app             // the window: current, list's focus, which view mixes lists
    readonly property var task: modelData
    readonly property bool open: selected && task.note !== ""

    implicitHeight: body.implicitHeight + 20
    selected: index === app.current
    active: app.listFocused
    TapHandler { onTapped: { row.app.current = row.index; row.app.toList() } }

    Text {
        id: mark
        anchors.left: parent.left; anchors.leftMargin: 14
        anchors.top: parent.top; anchors.topMargin: 11
        text: Icons.g(row.task.done ? "circle-check" : "circle")
        font.family: Icons.family; font.pixelSize: 16
        color: row.task.done ? row.c.faint : row.task.priority === "high" ? row.c.accent : row.c.dim
    }

    Column {
        id: body
        anchors.left: mark.right; anchors.leftMargin: 12
        anchors.right: parent.right; anchors.rightMargin: 16
        anchors.top: parent.top; anchors.topMargin: 10
        spacing: 3
        Text {
            textFormat: Text.PlainText
            width: parent.width; elide: Text.ElideRight
            text: row.task.title
            font.family: row.c.font; font.pixelSize: 13; font.strikeout: row.task.done
            color: row.task.done ? row.c.faint : row.c.title
        }
        Row {
            width: parent.width
            spacing: 10
            visible: due.text !== "" || where.text !== "" || (firstLine.text !== "" && !row.open)
            Text {
                id: due
                textFormat: Text.PlainText
                visible: text !== ""
                text: row.task.done ? (row.task.completed ? "Done " + row.app.dayOf(row.task.completed) : "Done") : row.task.due_label
                font.family: row.c.font; font.pixelSize: 11
                color: row.task.overdue ? row.c.danger : row.c.dim
            }
            Text {
                id: where
                textFormat: Text.PlainText
                visible: text !== ""
                text: row.app.mixed ? row.task.list : ""
                font.family: row.c.font; font.pixelSize: 11; color: row.c.faint
            }
            Text {
                id: firstLine
                textFormat: Text.PlainText
                visible: text !== "" && !row.open
                width: Math.max(0, parent.width - (due.visible ? due.width + 10 : 0) - (where.visible ? where.width + 10 : 0))
                elide: Text.ElideRight
                text: row.task.note.split("\n")[0]
                font.family: row.c.font; font.pixelSize: 11; color: row.c.faint
            }
        }
        Text {
            textFormat: Text.PlainText
            visible: row.open
            width: parent.width
            topPadding: 4
            wrapMode: Text.Wrap
            lineHeight: 1.2
            text: row.task.note
            font.family: row.c.font; font.pixelSize: 12; color: row.c.body
        }
    }
}
