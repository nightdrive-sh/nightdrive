import QtQuick
import qs

// One screen as a tile: its name, size and state, in proportion to the others (ArrangeCanvas sets its size). The main
// display says so under its size, in the theme's colour; one that is off (a closed lid, a device not connected) is
// dimmed, and still moves. Pressed and dragged, it tells the canvas, which draws it where it goes.
Rectangle {
    id: root
    required property QtObject c
    required property var screen
    property bool selected: false
    property bool lifted: false             // being dragged: the canvas draws it at the pointer
    signal grabbed(real px, real py)        // the pointer, in this tile's coordinates
    signal dragged(real px, real py)
    signal dropped()
    signal picked()

    readonly property string glyph: screen.kind === "builtin" ? "laptop" : screen.kind === "virtual"
                                    ? (screen.h > screen.w ? "smartphone" : "tablet") : "monitor"
    radius: 6
    color: Qt.rgba(c.sel.r, c.sel.g, c.sel.b, selected ? 0.9 : 0.55)
    border.width: selected ? 2 : 1
    border.color: selected ? c.primary : c.line
    opacity: lifted ? 0.85 : screen.on ? 1 : 0.5
    z: lifted ? 10 : selected ? 2 : 1

    Column {
        anchors.centerIn: parent
        width: parent.width - 12
        spacing: 2
        visible: root.height >= 30
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Icons.g(root.glyph); font.family: Icons.family; font.pixelSize: Math.min(18, root.height / 4)
            color: root.selected ? root.c.accent : root.c.dim
            visible: root.height >= 70
        }
        Text {
            width: parent.width; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight
            text: root.screen.name; color: root.c.title
            font.family: root.c.font; font.pixelSize: 12; font.weight: Font.DemiBold
        }
        Text {
            width: parent.width; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight
            visible: root.height >= 54
            text: root.screen.note !== "" ? root.screen.note : root.screen.w + " × " + root.screen.h
            color: root.c.dim; font.family: root.c.font; font.pixelSize: 11
        }
        // The main display: workspaces 1–9 are on it. 6 px above it, with the column's spacing
        Item { width: 1; height: 4; visible: mainBadge.visible }
        Rectangle {
            id: mainBadge
            visible: root.screen.main && root.height >= 46
            anchors.horizontalCenter: parent.horizontalCenter
            width: mainText.implicitWidth + 14; height: mainText.implicitHeight + 4
            radius: 5
            color: root.c.primary
            Text {
                id: mainText
                anchors.centerIn: parent
                text: "Main display"
                color: root.c.solid; font.family: root.c.font; font.pixelSize: 10; font.weight: Font.DemiBold
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
        preventStealing: true
        onPressed: m => { root.picked(); root.grabbed(m.x, m.y) }
        onPositionChanged: m => { if (pressed) root.dragged(m.x, m.y) }
        onReleased: root.dropped()
    }
}
