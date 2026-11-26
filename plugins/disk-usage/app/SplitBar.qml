import QtQuick

// How the folder on show splits, at a glance: its five biggest entries in their colours, then the rest in one quiet
// block, end to end in one bar, 2 px apart. The list below says the names and sizes (its rows carry the same colours),
// so the bar has no text of its own; a segment under the pointer lights its row (hot), and a click opens it.
Item {
    id: root
    required property QtObject c
    property var parts: []               // [{ s, color, index }]: index is the entry's row, -1 for the rest
    property real total: 0
    property int hot: -1                 // the row whose segment is under the pointer
    signal picked(int index)
    implicitHeight: 10

    readonly property real gap: 2
    // Each segment's width; one too small to see still gets 2 px, so none vanishes
    readonly property var widths: {
        const n = parts.length, room = width - gap * Math.max(0, n - 1)
        return parts.map(p => total > 0 ? Math.max(2, room * p.s / total) : 0)
    }

    Row {
        anchors.fill: parent
        spacing: root.gap
        Repeater {
            model: root.parts
            delegate: Rectangle {
                id: seg
                required property var modelData
                required property int index
                width: root.widths[index] || 0
                height: parent.height
                radius: 3
                color: modelData.color
                opacity: root.hot < 0 || root.hot === modelData.index ? 1 : 0.45
                Behavior on opacity { NumberAnimation { duration: 120 } }
                HoverHandler {
                    cursorShape: seg.modelData.index >= 0 ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onHoveredChanged: root.hot = hovered ? seg.modelData.index : -1
                }
                TapHandler { onTapped: if (seg.modelData.index >= 0) root.picked(seg.modelData.index) }
            }
        }
    }
    // An empty folder: the track alone
    Rectangle { visible: root.total <= 0; anchors.fill: parent; radius: 3; color: root.c.line }
}
