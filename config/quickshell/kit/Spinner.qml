import QtQuick
import qs

// A turning glyph while something runs in the background (Mail's fetch): shown only while `running`, and then at
// least `minimum` ms, so a fetch of a second still shows as a turn instead of a flicker. A tip says what runs.
Item {
    id: root
    required property QtObject c
    property bool running: false
    property string glyph: "loader-circle"
    property int glyphSize: 13
    property color glyphColor: c.dim
    property string tip: ""
    property string tipAlign: "left"
    property int minimum: 800
    implicitWidth: 22; implicitHeight: 22
    visible: running || hold.running
    onRunningChanged: if (running) hold.restart()

    Timer { id: hold; interval: root.minimum }
    HoverHandler { id: hover }
    Text {
        anchors.centerIn: parent
        text: Icons.g(root.glyph); font.family: Icons.family; font.pixelSize: root.glyphSize
        color: root.glyphColor
        RotationAnimation on rotation {
            running: root.visible
            from: 0; to: 360; duration: 1000; loops: Animation.Infinite
        }
    }
    Tip {
        x: root.tipAlign === "right" ? parent.width - width : 0
        y: parent.height + 8
        c: root.c; text: root.tip; hovered: hover.hovered && root.tip !== ""
    }
}
