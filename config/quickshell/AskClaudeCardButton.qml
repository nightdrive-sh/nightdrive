import QtQuick

// A button on Ask Claude's result cards (AskClaudeCard.qml, #2245): a glyph and a label in a thin frame, as the kit's
// AppButton looks, in the shell's Theme. Without room for the label (compact) it is the glyph alone. done: it has done
// its one thing (Saved), so it shows that and takes no more clicks.
Rectangle {
    id: b
    property string glyph: ""
    property string label: ""
    property bool compact: false
    property bool done: false
    property bool strong: false          // the card's main act (Play): filled
    readonly property alias hovered: hover.hovered
    signal clicked()

    implicitWidth: row.implicitWidth + (label !== "" && !compact ? 22 : 14)
    implicitHeight: 28
    radius: 7
    color: strong ? Theme.primary : hovered && !done ? Theme.hover : "transparent"
    border { color: strong ? Theme.primary : done ? Theme.ok : Theme.border; width: 1 }

    HoverHandler { id: hover; cursorShape: b.done ? Qt.ArrowCursor : Qt.PointingHandCursor }
    TapHandler { onTapped: if (!b.done) b.clicked() }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 6
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: Icons.g(b.done ? "check" : b.glyph)
            color: b.strong ? Theme.bg : b.done ? Theme.ok : Theme.text
            font { family: Icons.family; pixelSize: 14 }
        }
        Text {
            visible: b.label !== "" && !b.compact
            anchors.verticalCenter: parent.verticalCenter
            text: b.label
            color: b.strong ? Theme.bg : b.done ? Theme.ok : Theme.text
            font { family: Theme.font; pixelSize: 12 }
        }
    }
}
