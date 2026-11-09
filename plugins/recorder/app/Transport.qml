import QtQuick
import QtQuick.Layouts
import qs
import qs.kit

// The player's controls under the recording's name: Play / Pause (p), the place in it as a bar to click or drag
// (← → move five seconds), and the time played and the length. Below compactMax the button is its glyph alone.
RowLayout {
    id: t
    required property QtObject c
    required property var player
    required property var store               // its clock()
    property bool compact: false
    spacing: 12

    AppButton {
        Layout.alignment: Qt.AlignVCenter
        c: t.c
        glyph: t.player.playing ? "pause" : "play"
        label: t.compact ? "" : t.player.playing ? "Pause" : "Play"
        strong: !t.player.playing
        tip: t.player.playing ? "Pause" : "Play"
        keys: "p"
        tipAlign: "left"
        onClicked: t.player.toggle()
    }

    // The bar: the part played in the accent, a knob where it is; a click or a drag goes there
    Item {
        id: bar
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignVCenter
        implicitHeight: 24
        readonly property real at: drag.pressed ? drag.ratio : t.player.progress
        Rectangle {
            id: track
            anchors.left: parent.left; anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            height: 4; radius: 2
            color: t.c.divider
            Rectangle {
                width: parent.width * bar.at
                height: parent.height; radius: 2
                color: t.c.accent
            }
        }
        Rectangle {
            x: track.width * bar.at - width / 2
            anchors.verticalCenter: parent.verticalCenter
            width: 12; height: 12; radius: 6
            color: t.c.accent
            visible: t.player.position > 0 || t.player.playing || drag.pressed || drag.containsMouse
        }
        MouseArea {
            id: drag
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            property real ratio: 0
            function place(mx) { ratio = Math.max(0, Math.min(1, mx / width)) }
            onPressed: m => place(m.x)
            onPositionChanged: m => { if (pressed) place(m.x) }
            onReleased: t.player.seek(ratio * t.player.duration)
        }
    }

    Text {
        Layout.alignment: Qt.AlignVCenter
        text: t.store.clock(drag.pressed ? drag.ratio * t.player.duration : t.player.position) + " / "
              + t.store.clock(t.player.duration)
        font.family: t.c.font; font.pixelSize: 12
        font.features: { "tnum": 1 }
        color: t.c.dim
    }
}
