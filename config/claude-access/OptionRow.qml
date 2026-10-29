import QtQuick
import qs
import qs.kit

// One of an area's own choices in its panel (AreaPanel; Home Assistant's locks, Dashboard #1830): a box, its name and
// what it means as it is now, in plain words (config/mcp/areas.py), and whether it is the user's own or the level's.
// A click or Space turns it on or off.
Rectangle {
    id: row
    required property QtObject c
    property var option: ({ name: "", value: false, on: "", off: "", own: false, preset: false })
    property bool picked: false
    signal toggled()
    implicitHeight: body.implicitHeight + 12
    radius: 6
    color: picked ? c.sel : hover.hovered ? c.hover : "transparent"

    HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
    TapHandler { onTapped: row.toggled() }

    Row {
        id: body
        x: 8; y: 6
        width: parent.width - 16
        spacing: 10
        Text {
            text: Icons.g(row.option.value ? "square-check" : "square")
            color: row.option.value ? row.c.accent : row.c.dim
            font { family: Icons.family; pixelSize: 16 }
        }
        Column {
            width: parent.width - 26
            spacing: 2
            Text {
                width: parent.width
                text: row.option.name + (row.option.own
                      ? "  (your own; the level's is " + (row.option.preset ? "on" : "off") + ")" : "")
                elide: Text.ElideRight
                color: row.c.text
                font { family: row.c.font; pixelSize: 13; weight: Font.DemiBold }
            }
            Text {
                width: parent.width
                text: row.option.value ? row.option.on : row.option.off
                wrapMode: Text.Wrap
                color: row.c.dim
                font { family: row.c.font; pixelSize: 12 }
            }
        }
    }
}
