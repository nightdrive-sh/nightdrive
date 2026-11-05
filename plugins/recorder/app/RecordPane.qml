import QtQuick
import QtQuick.Layouts
import qs
import qs.kit

// The recording: its time, the microphone's level, the mic it records from, and Record / Pause / Resume (Space), Save (⏎)
// and New (n: save and go straight on with the next). It is the whole window while a recording is made (a low strip,
// shell.qml), and the top of the tall one otherwise. Below compactMax the buttons are glyphs alone; in the strip their
// tips stay off, as there is no room under them (the key sheet, ?, has the keys).
Item {
    id: pane
    required property QtObject c
    required property var store
    required property var mics                 // the MicPicker: names and nodes
    property bool strip: false                 // the window is the strip: no tips
    property bool canExpand: false             // while recording: the recordings shown or not (l)
    property bool expanded: false
    signal pickMic()
    signal toggleList()
    readonly property bool compact: width < 520
    readonly property string micShown: store.idle ? store.mic : store.recMic
    function short(text, n) { return text.length > n ? text.slice(0, n - 1) + "…" : text }
    implicitHeight: 88

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 18; anchors.rightMargin: 14
        spacing: 14

        // The state: a red dot while recording (fading as the bar's icon does), a pause sign while paused
        Text {
            Layout.alignment: Qt.AlignVCenter
            text: Icons.g(pane.store.recording ? "circle" : pane.store.idle ? "mic" : "pause")
            font.family: Icons.family; font.pixelSize: pane.store.recording ? 13 : 16
            color: pane.store.recording ? pane.c.danger : pane.c.dim
            SequentialAnimation on opacity {
                running: pane.store.recording; loops: Animation.Infinite
                NumberAnimation { to: 0.35; duration: 700; easing.type: Easing.InOutSine }
                NumberAnimation { to: 1; duration: 700; easing.type: Easing.InOutSine }
                onRunningChanged: if (!running) parent.opacity = 1
            }
            Rectangle {      // the dot filled: the glyph is a ring
                visible: pane.store.recording
                anchors.centerIn: parent; width: 9; height: 9; radius: 4.5; color: pane.c.danger
            }
        }
        Text {
            Layout.alignment: Qt.AlignVCenter
            Layout.preferredWidth: timeMetrics.advanceWidth     // the digits don't push the meter as they change
            text: pane.store.clock(pane.store.elapsed)
            font.family: pane.c.font; font.pixelSize: 26; font.weight: Font.Light
            font.features: { "tnum": 1 }
            color: pane.store.idle ? pane.c.faint : pane.c.title
            TextMetrics { id: timeMetrics; font.family: pane.c.font; font.pixelSize: 26; text: pane.store.elapsed >= 3600 ? "0:00:00" : "00:00" }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: 6
            LevelMeter {
                Layout.fillWidth: true
                Layout.maximumWidth: 560          // a wide window: not a bar from edge to edge
                c: pane.c
                node: pane.mics.nodeOf(pane.micShown)
                live: pane.store.recording
            }
            // The mic (a click picks another, but not in the middle of a piece: pause first) and the recording's name
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                // Its own width, its label cut short rather than the button squeezed (its row doesn't elide), and its
                // glyph lined up with the meter's left end
                AppBarButton {
                    Layout.preferredWidth: implicitWidth
                    Layout.leftMargin: -10
                    c: pane.c
                    glyph: "mic"
                    label: pane.short(pane.mics.nameOf(pane.micShown), pane.compact ? 18 : 30)
                    enabled: !pane.store.recording
                    tip: pane.strip ? "" : "Microphone"
                    keys: "m"
                    onClicked: pane.pickMic()
                }
                Text {
                    Layout.fillWidth: true
                    visible: !pane.store.idle && !pane.compact
                    elide: Text.ElideRight; textFormat: Text.PlainText
                    text: pane.store.name
                    font.family: pane.c.font; font.pixelSize: 12
                    color: pane.c.faint
                }
            }
        }

        Row {
            Layout.alignment: Qt.AlignVCenter
            spacing: 8
            AppButton {
                c: pane.c
                glyph: pane.store.recording ? "pause" : "circle"
                label: pane.compact ? "" : pane.store.recording ? "Pause" : pane.store.idle ? "Record" : "Resume"
                strong: !pane.store.recording && pane.store.idle
                tip: pane.strip ? "" : pane.store.recording ? "Pause" : pane.store.idle ? "Start recording" : "Go on"
                keys: "Space"
                onClicked: pane.store.toggle()
            }
            AppButton {
                visible: !pane.store.idle
                c: pane.c
                glyph: "check"
                label: pane.compact ? "" : "Save"
                strong: true
                tip: pane.strip ? "" : "Save into " + (pane.store.folder || "~/Recordings").replace(/^\/home\/[^/]+/, "~")
                keys: "⏎"
                onClicked: pane.store.save()
            }
            AppButton {
                visible: !pane.store.idle
                c: pane.c
                glyph: "plus"
                label: pane.compact ? "" : "New"
                tip: pane.strip ? "" : "Save, and start the next one"
                keys: "n"
                onClicked: pane.store.newOne()
            }
            AppIconButton {
                visible: pane.canExpand
                anchors.verticalCenter: parent.verticalCenter
                c: pane.c
                glyph: pane.expanded ? "chevron-up" : "chevron-down"
                tip: pane.strip ? "" : pane.expanded ? "Back to the strip" : "The recordings"
                keys: "l"
                tipAlign: "right"
                onClicked: pane.toggleList()
            }
        }
    }
}
