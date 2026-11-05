import QtQuick
import QtQuick.Layouts
import qs
import qs.kit

// The picked recording: its name, when it was made, its length and size, and where its file is. Playing, renaming,
// exporting and the transcript come here next (Dashboard #2250, #2251). In a narrow window it is a page of its own,
// with Back (Esc) to the list.
Item {
    id: v
    required property QtObject c
    property bool onePane: false
    required property var store
    readonly property var rec: store.current
    signal back()

    function mb(bytes) { return bytes >= 1e6 ? (bytes / 1e6).toFixed(1) + " MB" : Math.max(1, Math.round(bytes / 1e3)) + " kB" }

    AppIconButton {
        id: backButton
        visible: v.onePane
        anchors.left: parent.left; anchors.leftMargin: 10
        anchors.top: parent.top; anchors.topMargin: 6
        c: v.c
        glyph: "arrow-left"
        tip: "The recordings"
        keys: "Esc"
        onClicked: v.back()
    }

    Column {
        visible: v.rec !== null
        anchors.left: parent.left; anchors.leftMargin: 24
        anchors.right: parent.right; anchors.rightMargin: 24
        anchors.top: parent.top; anchors.topMargin: v.onePane ? 44 : 14
        spacing: 8
        Text {
            width: parent.width
            wrapMode: Text.Wrap; textFormat: Text.PlainText
            text: v.rec ? v.rec.name : ""
            font.family: v.c.font; font.pixelSize: 17; font.weight: Font.DemiBold
            color: v.c.title
        }
        Text {
            width: parent.width
            wrapMode: Text.Wrap; textFormat: Text.PlainText
            text: v.rec ? [Regional.format(v.rec.modified, "long") + " " + Regional.format(v.rec.modified, "time"),
                           v.store.clock(v.rec.duration), v.mb(v.rec.size)].join("  ·  ") : ""
            font.family: v.c.font; font.pixelSize: 12
            color: v.c.dim
        }
        Text {
            width: parent.width
            elide: Text.ElideMiddle; textFormat: Text.PlainText
            text: v.rec ? v.rec.path.replace(/^\/home\/[^/]+/, "~") : ""
            font.family: v.c.font; font.pixelSize: 11
            color: v.c.faint
        }
    }
}
