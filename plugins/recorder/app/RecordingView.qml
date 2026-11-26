import QtQuick
import QtQuick.Layouts
import qs
import qs.kit

// The picked recording: its name, when it was made, its length and size, the player (Transport: Play, the place in
// it), and what can be done to it (RecordingActions: Rename, Export, Show in Files, Trash), with the exports made so far
// under them, and its transcript in the rest of the height (TranscriptView). In a narrow window it is a page of its own,
// with Back (Esc) to the list; below compactMax the buttons are their glyphs alone.
Item {
    id: v
    required property QtObject c
    property bool onePane: false
    required property var store
    required property var player
    required property var actions
    readonly property var rec: store.current
    readonly property bool compact: width < 400   // the two-pane view of a 720 px window (419) keeps its words
    signal back()
    signal openSettings()
    function transcribe() { transcript.toggle() }      // t

    function mb(bytes) { return bytes >= 1e6 ? (bytes / 1e6).toFixed(1) + " MB" : Math.max(1, Math.round(bytes / 1e3)) + " kB" }
    function home(path) { return path.replace(/^\/home\/[^/]+/, "~") }

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

    ColumnLayout {
        visible: v.rec !== null
        anchors.left: parent.left; anchors.leftMargin: v.compact ? 16 : 24
        anchors.right: parent.right; anchors.rightMargin: v.compact ? 16 : 24
        anchors.top: parent.top; anchors.topMargin: v.onePane ? 44 : 14
        anchors.bottom: parent.bottom; anchors.bottomMargin: 8
        spacing: 8

        Text {
            Layout.fillWidth: true
            wrapMode: Text.Wrap; textFormat: Text.PlainText
            text: v.rec ? v.rec.name : ""
            font.family: v.c.font; font.pixelSize: 17; font.weight: Font.DemiBold
            color: v.c.title
        }
        Text {
            Layout.fillWidth: true
            wrapMode: Text.Wrap; textFormat: Text.PlainText
            text: v.rec ? [Regional.format(v.rec.modified, "long") + " " + Regional.format(v.rec.modified, "time"),
                           v.store.clock(v.rec.duration), v.mb(v.rec.size)].join("  ·  ") : ""
            font.family: v.c.font; font.pixelSize: 12
            color: v.c.dim
        }

        // z: a later sibling draws over an earlier one, so the rows whose tips hang down over the rest come first in z
        Transport {
            z: 3
            Layout.fillWidth: true
            Layout.topMargin: 10
            c: v.c
            player: v.player
            store: v.store
            compact: v.compact
        }

        // What can be done to it: frameless, as Notes' bar over a note; the glyphs alone when narrow
        Flow {
            z: 2
            Layout.fillWidth: true
            Layout.topMargin: 6
            Layout.leftMargin: -10                    // the first glyph lines up with the text above
            spacing: 2
            AppBarButton { c: v.c; glyph: "pencil"; label: "Rename"; compact: v.compact; tip: "Rename"; keys: "F2"; onClicked: v.actions.rename() }
            AppBarButton { c: v.c; glyph: "file-output"; label: "Export"; compact: v.compact; tip: "MP3, M4A, FLAC or Opus"; keys: "e"; onClicked: v.actions.exportIt() }
            AppBarButton { c: v.c; glyph: "folder-open"; label: "Show"; compact: v.compact; tip: "Show in Files"; keys: "o"; onClicked: v.actions.show() }
            AppBarButton { c: v.c; glyph: "trash-2"; label: "Trash"; compact: v.compact; tip: "To the trash (⌘Z puts it back)"; keys: "⌘⌫"; onClicked: v.actions.trash() }
        }

        Text {
            Layout.fillWidth: true
            Layout.topMargin: 4
            elide: Text.ElideMiddle; textFormat: Text.PlainText
            text: v.rec ? v.home(v.rec.path) : ""
            font.family: v.c.font; font.pixelSize: 11
            color: v.c.faint
        }
        Text {
            Layout.fillWidth: true
            visible: !!v.rec && v.rec.exports.length > 0
            wrapMode: Text.Wrap; textFormat: Text.PlainText
            text: v.rec ? "Exported: " + v.rec.exports.map(e => ({ mp3: "MP3", m4a: "M4A", flac: "FLAC", opus: "Opus" })[e.split(".").pop()] || e).join(", ") : ""
            font.family: v.c.font; font.pixelSize: 11
            color: v.c.faint
        }

        TranscriptView {
            id: transcript
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.topMargin: 12
            c: v.c
            store: v.store
            player: v.player
            compact: v.compact
            onOpenSettings: v.openSettings()
        }
    }

    Text {
        anchors.centerIn: parent
        visible: v.rec === null && v.store.loaded
        text: "No recording picked"
        font.family: v.c.font; font.pixelSize: 12
        color: v.c.faint
    }
}
