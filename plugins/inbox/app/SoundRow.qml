import QtQuick
import qs
import qs.kit

// One sound file in a message (SoundFiles): Play / Pause, its name, the time played and its length, Copy (its name), and
// under them a thin bar of the place in it while it is the one loaded. A click elsewhere on the row opens the file in
// its app, as the other files' rows do.
Rectangle {
    id: row
    required property QtObject c
    property string name: ""
    property real length: 0                   // seconds; 0 until ffprobe has answered
    property bool loaded: false               // the one playing or paused
    property bool playing: false
    property real position: 0
    property real progress: 0
    property var clock: s => ""
    signal play()
    signal open()
    signal copy()
    height: 38
    z: button.hovered || copyButton.hovered ? 1 : 0   // a button's tip over the rows after it
    radius: 8
    color: rowHover.hovered ? c.hover : loaded ? Qt.rgba(c.sel.r, c.sel.g, c.sel.b, 0.25) : "transparent"

    HoverHandler { id: rowHover; cursorShape: Qt.PointingHandCursor }
    // Both tap handlers see a click on a button: that one is the button's alone
    TapHandler { onTapped: if (!button.hovered && !copyButton.hovered) row.open() }

    AppIconButton {
        id: button
        anchors.left: parent.left; anchors.leftMargin: 4; anchors.verticalCenter: parent.verticalCenter
        width: 30; height: 30
        c: row.c
        glyph: row.playing ? "pause" : "play"
        glyphSize: 15
        glyphColor: row.loaded ? row.c.accent : row.c.dim
        tip: row.playing ? "Pause" : "Play"
        keys: "p"
        onClicked: row.play()
    }
    Text {
        anchors.left: button.right; anchors.leftMargin: 8; anchors.verticalCenter: parent.verticalCenter
        anchors.right: time.left; anchors.rightMargin: 10
        elide: Text.ElideMiddle
        textFormat: Text.PlainText
        text: row.name
        font.family: row.c.font; font.pixelSize: 13; color: row.c.text
    }
    Text {
        id: time
        anchors.right: copyButton.left; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter
        visible: row.length > 0
        text: row.loaded ? row.clock(row.position) + " / " + row.clock(row.length) : row.clock(row.length)
        font.family: row.c.font; font.pixelSize: 11
        font.features: { "tnum": 1 }
        color: row.loaded ? row.c.dim : row.c.faint
    }
    AppIconButton {
        id: copyButton
        anchors.right: parent.right; anchors.rightMargin: 4; anchors.verticalCenter: parent.verticalCenter
        c: row.c
        glyph: "copy"
        tip: "Copy the name"
        tipAlign: "right"
        onClicked: row.copy()
    }
    // The place in it, along the row's foot under the name and the time
    Rectangle {
        visible: row.loaded
        anchors.left: button.right; anchors.leftMargin: 8
        anchors.right: copyButton.left; anchors.rightMargin: 8
        anchors.bottom: parent.bottom; anchors.bottomMargin: 3
        height: 2; radius: 1
        color: row.c.divider
        Rectangle {
            width: parent.width * row.progress
            height: parent.height; radius: 1
            color: row.c.accent
        }
    }
}
