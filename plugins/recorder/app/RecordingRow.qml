import QtQuick
import qs
import qs.kit

// A recording in the list: its name, and a line with when it was made (the list's "when": Regional.relative), its length
// and whether it has been turned into text yet, or how far that is.
AppRow {
    id: row
    required property var modelData
    required property int index
    required property var app                 // the window: the list's focus, open()
    required property var store
    readonly property var rec: modelData
    // A transcription under way shows how far it is ("Text 3/12"), one that failed says so
    readonly property var job: store.job(rec.name)
    readonly property string textState: !job ? (rec.transcript ? "Text" : "")
        : job.state === "failed" ? "Text failed" : job.state === "queued" ? "Text waits"
        : "Text " + job.done + "/" + (job.total || "…")

    implicitHeight: 52
    selected: rec.name === store.picked
    active: app.listFocused
    TapHandler {
        onTapped: { row.store.picked = row.rec.name; row.app.open() }
    }

    Text {
        id: mark
        anchors.left: parent.left; anchors.leftMargin: 14
        anchors.verticalCenter: parent.verticalCenter
        text: Icons.g("audio-lines")
        font.family: Icons.family; font.pixelSize: 16
        color: row.selected ? row.c.accent : row.c.dim
    }
    Column {
        anchors.left: mark.right; anchors.leftMargin: 12
        anchors.right: parent.right; anchors.rightMargin: 14
        anchors.verticalCenter: parent.verticalCenter
        spacing: 3
        Text {
            width: parent.width
            elide: Text.ElideRight; textFormat: Text.PlainText
            text: row.rec.name
            font.family: row.c.font; font.pixelSize: 13
            color: row.c.title
        }
        Text {
            width: parent.width
            elide: Text.ElideRight; textFormat: Text.PlainText
            text: [Regional.relative(row.rec.modified), row.store.clock(row.rec.duration),
                   row.textState].filter(s => s).join("  ·  ")
            font.family: row.c.font; font.pixelSize: 11
            color: row.c.dim
        }
    }
}
