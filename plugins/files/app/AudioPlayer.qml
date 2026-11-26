import QtQuick
import QtQuick.Layouts
import qs
import qs.kit
import "Format.js" as Format

// A sound file's player in the previews (#3416): Play / Pause, the time played, a bar of the place in it (a click or a
// drag seeks) and the length, through the kit's AppAudio (ffmpeg into PipeWire, "Files" in the Sound menu). The caller
// binds `path` to the file while it is shown and to "" when it isn't: AppAudio stops on a new path, so another file,
// the big preview closing or the pane hiding never leaves the old one playing. `autoplay` starts each new path at once
// (the big preview, as Quick Look does); the pane waits for a click. `big` is the big preview's larger size.
Item {
    id: root
    required property QtObject c
    property string path: ""
    property real duration: 0                 // seconds, from peek.py's ffprobe
    property string title: ""
    property bool autoplay: false
    property bool big: false
    readonly property bool playing: audio.playing
    property string error: ""
    implicitHeight: big ? 64 : 44
    implicitWidth: 320

    function toggle() { if (path) audio.toggle() }
    function skip(d) { if (path) audio.skip(d) }

    // Later, so AppAudio has taken the new path (and stopped the old one) and the length is set before it starts
    onPathChanged: { error = ""; if (autoplay && path) Qt.callLater(() => { if (root.path && !audio.playing) audio.play() }) }

    AppAudio {
        id: audio
        app: "Files"
        path: root.path
        title: root.title
        duration: root.duration
        onFailed: text => root.error = text
    }

    RowLayout {
        anchors.fill: parent
        spacing: root.big ? 14 : 8

        AppIconButton {
            Layout.preferredWidth: root.big ? 44 : 30
            Layout.preferredHeight: root.big ? 44 : 30
            c: root.c
            glyph: audio.playing ? "pause" : "play"
            glyphSize: root.big ? 22 : 15
            glyphColor: audio.playing ? root.c.accent : root.c.dim
            tip: audio.playing ? "Pause" : "Play"
            keys: root.big ? "p" : ""
            onClicked: root.toggle()
        }
        Text {
            text: Format.length(bar.dragging ? bar.dragAt * root.duration : audio.position)
            color: root.c.dim; font.family: root.c.font; font.pixelSize: root.big ? 13 : 11
            font.features: { "tnum": 1 }
        }
        // The place in it: a click goes there, a drag shows where and goes there on release
        Item {
            id: bar
            Layout.fillWidth: true
            Layout.preferredHeight: 24
            property bool dragging: false
            property real dragAt: 0
            readonly property real shown: dragging ? dragAt : audio.progress
            Rectangle {
                id: track
                anchors.left: parent.left; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                height: root.big ? 4 : 3; radius: height / 2
                color: root.c.divider
                Rectangle { width: parent.width * bar.shown; height: parent.height; radius: parent.radius; color: root.c.accent }
            }
            Rectangle {
                visible: root.duration > 0 && (audio.playing || audio.position > 0 || bar.dragging || seekArea.containsMouse)
                width: root.big ? 12 : 10; height: width; radius: width / 2
                x: bar.shown * (bar.width - width)
                anchors.verticalCenter: parent.verticalCenter
                color: root.c.accent
            }
            MouseArea {
                id: seekArea
                anchors.fill: parent
                hoverEnabled: true
                enabled: root.duration > 0 && root.path !== ""
                cursorShape: Qt.PointingHandCursor
                function at(x) { return Math.max(0, Math.min(1, x / width)) }
                onPressed: m => { bar.dragging = true; bar.dragAt = at(m.x) }
                onPositionChanged: m => { if (bar.dragging) bar.dragAt = at(m.x) }
                onReleased: m => {
                    bar.dragging = false
                    audio.seek(at(m.x) * root.duration)   // paused, it moves the place and stays paused
                }
                onCanceled: bar.dragging = false
            }
        }
        Text {
            text: root.duration > 0 ? Format.length(root.duration) : "–:––"
            color: root.c.faint; font.family: root.c.font; font.pixelSize: root.big ? 13 : 11
            font.features: { "tnum": 1 }
        }
    }
    Text {
        visible: root.error !== ""
        anchors.top: parent.bottom; anchors.left: parent.left; anchors.right: parent.right
        wrapMode: Text.Wrap
        textFormat: Text.PlainText
        text: root.error
        color: Theme.danger
        font.family: root.c.font; font.pixelSize: 11
    }
}
