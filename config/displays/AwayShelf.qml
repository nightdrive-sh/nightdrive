import QtQuick

// The shelf under the desk for the virtual screens put away (a phone used away from the desk): out of the pointer's
// reach, so it never strays there. Only its ground and words: ArrangeCanvas draws the tiles on it and handles the drops.
Rectangle {
    id: root
    required property QtObject c
    property bool empty: true
    property bool lit: false                // a virtual screen dragged over it: dropped here, it goes away
    readonly property real firstX: 16
    radius: 8
    color: lit ? Qt.rgba(c.primary.r, c.primary.g, c.primary.b, 0.12) : "transparent"
    border.color: lit ? c.primary : c.line
    border.width: 1

    Text {
        x: root.firstX; y: 7
        text: "Away" + (root.empty ? "" : "  ·  out of the pointer's reach")
        color: root.c.dim; font.family: root.c.font; font.pixelSize: 11; font.weight: Font.DemiBold
    }
    Text {
        visible: root.empty
        anchors.centerIn: parent; anchors.verticalCenterOffset: 8
        width: parent.width - 32; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight
        text: "Drag a phone or tablet here to keep the pointer from straying onto it"
        color: root.c.faint; font.family: root.c.font; font.pixelSize: 11
    }
}
