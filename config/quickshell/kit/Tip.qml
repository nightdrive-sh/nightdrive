import QtQuick

// A button's tip: what it does and its key, shown once the pointer has rested on it (delay). Place it with x and y
// beside the button, and bind hovered to the button's HoverHandler.
// Part of the apps' kit (README.md).
Rectangle {
    id: root
    required property QtObject c
    property string text
    property string keys
    property bool hovered: false
    readonly property int delay: 500       // ms under the pointer before it shows
    Timer { id: wait; interval: root.delay; running: root.hovered && root.text !== "" }
    visible: hovered && !wait.running && text !== ""
    z: 10
    implicitWidth: row.implicitWidth + 20; implicitHeight: 32
    radius: 8
    color: c.solid
    border.color: c.line
    Row {
        id: row
        anchors.centerIn: parent
        spacing: 10
        Text { anchors.verticalCenter: parent.verticalCenter; text: root.text; color: root.c.text; font.family: root.c.font; font.pixelSize: 12 }
        KeyCap { anchors.verticalCenter: parent.verticalCenter; visible: root.keys !== ""; c: root.c; keys: root.keys }
    }
}
