import QtQuick
import qs
import qs.kit

// A task in the list: its circle (ticked when done), the title, and a line with when it's due (red once late), its list
// (in the views that mix lists) and the note's first line. The picked row shows the whole note: there is no other pane,
// so Copy text (c) sits under it, to paste the note as such into another app or a Claude session.
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
    TapHandler {
        onTapped: { row.app.current = row.index; row.app.toList() }
        onDoubleTapped: row.app.editTask(row.index)
    }

    // Ticked a moment ago (Actions.ticking): the row shows the new state at once and fades just before it leaves
    readonly property var tick: app.ticking[task.id]
    readonly property bool ticked: tick !== undefined
    readonly property bool done: ticked ? tick : task.done
    SequentialAnimation {
        id: leaving
        PauseAnimation { duration: 1500 }
        NumberAnimation { target: row; property: "opacity"; to: 0.5; duration: 450 }
    }
    onTickedChanged: { leaving.stop(); if (ticked) leaving.start(); else opacity = 1 }

    // The circle ticks it off (or, in Done, opens it again)
    TaskCheck {
        id: mark
        anchors.left: parent.left; anchors.leftMargin: 14
        anchors.top: parent.top; anchors.topMargin: 11
        c: row.c
        done: row.done
        fresh: row.ticked
        important: row.task.priority === "high"
        onClicked: { row.app.current = row.index; row.app.toggleDone(row.index) }
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
            font.family: row.c.font; font.pixelSize: 13; font.strikeout: row.done
            color: row.done ? row.c.faint : row.c.title
        }
        Row {
            width: parent.width
            spacing: 10
            visible: due.text !== "" || where.text !== "" || (firstLine.text !== "" && !row.open)
            Text {
                id: due
                textFormat: Text.PlainText
                visible: text !== ""
                text: row.task.done ? row.app.doneLabel(row.task.completed) : row.app.dueLabel(row.task.due)
                font.family: row.c.font; font.pixelSize: 11
                color: row.task.overdue ? row.c.danger : row.c.dim
            }
            Text {
                id: where
                textFormat: Text.PlainText
                visible: text !== ""
                // In the views that mix lists, unless its heading says it already (the search's open ones)
                text: row.app.mixed && row.task.section !== row.task.list ? row.task.list : ""
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
        // The note alone, not the title: it is what holds the words to paste. Frameless, as the actions over Mail's
        // message: a framed button was a muddy box on the picked row's colour. Its glyph lines up with the note's words,
        // and it is lit, saying Copied, for a moment, as the sign
        Item {
            visible: row.open
            width: parent.width; height: copy.height + 4
            AppBarButton {
                id: copy
                x: -10; y: 4
                c: row.c
                readonly property bool done: row.app.copied === row.task.id
                glyph: done ? "copy-check" : "copy"
                label: done ? "Copied" : "Copy text"
                strong: done
                tip: "Copy the note"; keys: "c"
                onClicked: row.app.copyNote(row.index)
            }
        }
    }
}
