import QtQuick
import qs

// One of a few that go together, as one framed button cut into parts (a segmented switch: Week | Month): the picked
// part filled as AppButton's strong one, and the fill slides to the part clicked, so the switch reads as one thing
// with one state rather than buttons side by side. Each option is { label, glyph, tip, keys }; compact shows the glyphs
// alone (a narrow window), and the tip says the rest. picked(i) on a click: the view sets current itself.
// Part of the apps' kit (README.md).
Rectangle {
    id: root
    required property QtObject c
    property var options: []            // [{ label, glyph, tip, keys }]
    property int current: 0
    property bool compact: false
    property string tipAlign: "left"     // the tip's edge that lines up with its part's: "left" or "right"
    signal picked(int i)

    implicitWidth: parts.implicitWidth + 2; implicitHeight: 28; radius: 7
    color: "transparent"
    border.color: c.line
    // Under the pointer it rises over its neighbours, which would otherwise draw over its part's tip
    property int hoveredParts: 0
    z: hoveredParts > 0 ? 1 : 0

    // The fill under the picked part, sliding between them
    Rectangle {
        // parts.count: read again once the Repeater has made its parts (itemAt is null before)
        readonly property Item at: parts.count, repeater.itemAt(root.current)
        visible: at !== null
        x: at ? parts.x + at.x : 0; y: 0
        width: at ? at.width : 0; height: root.height
        radius: root.radius
        color: root.c.sel
        border.color: root.c.primary
        Behavior on x { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
    }

    Row {
        id: parts
        x: 1; height: parent.height
        readonly property int count: repeater.count
        Repeater {
            id: repeater
            model: root.options
            delegate: Item {
                id: part
                required property var modelData
                required property int index
                readonly property bool picked: index === root.current
                width: row.implicitWidth + 24; height: parts.height
                z: hover.hovered ? 1 : 0
                onZChanged: root.hoveredParts += hover.hovered ? 1 : -1
                // Under the pointer, the part not picked lights as a button does; the picked one has its fill
                Rectangle {
                    anchors.fill: parent; anchors.margins: 1
                    radius: root.radius - 1
                    visible: hover.hovered && !part.picked
                    color: root.c.hover
                }
                HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: root.picked(part.index) }
                Row {
                    id: row
                    anchors.centerIn: parent
                    spacing: 8
                    Text {
                        visible: root.compact && (part.modelData.glyph || "") !== ""
                        anchors.verticalCenter: parent.verticalCenter
                        text: Icons.g(part.modelData.glyph || ""); font.family: Icons.family; font.pixelSize: 13
                        color: part.picked ? root.c.accent : root.c.dim
                    }
                    Text {
                        visible: !root.compact || (part.modelData.glyph || "") === ""
                        anchors.verticalCenter: parent.verticalCenter
                        text: part.modelData.label || ""; font.family: root.c.font; font.pixelSize: 12
                        color: part.picked || hover.hovered ? root.c.title : root.c.text
                    }
                }
                Tip {
                    x: root.tipAlign === "left" ? 0 : parent.width - width; y: parent.height + 8
                    c: root.c; text: part.modelData.tip || ""; keys: part.modelData.keys || ""; hovered: hover.hovered
                }
            }
        }
    }
}
