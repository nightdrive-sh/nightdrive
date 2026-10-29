import QtQuick

// What a key does, for the mouse too: the key in a box and a word to click ("⏎ Set up with Claude", "esc Cancel").
Row {
    id: root
    required property QtObject c
    property string keys
    property string label
    property color color: c.dim
    property color hoverColor: c.text
    property int pixelSize: 12
    signal clicked()
    spacing: 8
    KeyCap { anchors.verticalCenter: parent.verticalCenter; c: root.c; keys: root.keys }
    Text {
        anchors.verticalCenter: parent.verticalCenter
        text: root.label; font.family: root.c.font; font.pixelSize: root.pixelSize
        color: hover.hovered ? root.hoverColor : root.color
        HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: root.clicked() }
    }
}
