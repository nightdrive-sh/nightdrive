import QtQuick
import qs.kit

// A panel's answer button (Delete, Leave, Cancel); Garage's own, until it moves to the kit (Dashboard #1641), bigger than AppButton as it is what the panel is for: its keys first
// in the theme colour (ctrl ⏎, esc), then what it does, as the desktop's Claude writes card has them. No frame: a lighter
// ground sets it off the card, and the one the key answers yes with (strong) has the selection's colour. ⏎ is a Lucide
// glyph, as there.
Rectangle {
    id: root
    required property QtObject c
    property var keys: []               // "Ctrl", "Enter", "Esc"
    readonly property var glyphs: ({ Enter: "corner-down-left" })
    property string label
    property bool strong: false
    readonly property alias hovered: hover.hovered
    signal clicked()
    implicitWidth: row.implicitWidth + 28; implicitHeight: 36; radius: 9
    // Under the mouse just brighter, as the card's buttons
    color: strong ? (hovered ? Qt.lighter(c.sel, 1.3) : c.sel) : Qt.rgba(1, 1, 1, hovered ? 0.11 : 0.06)
    HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
    TapHandler { onTapped: root.clicked() }
    Row {
        id: row
        anchors.centerIn: parent
        spacing: 9
        Row {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4
            Repeater {
                model: root.keys
                Text {
                    required property string modelData
                    readonly property string glyph: root.glyphs[modelData] || ""
                    anchors.verticalCenter: parent.verticalCenter
                    text: glyph !== "" ? Icons.g(glyph) : modelData.toLowerCase()
                    color: root.c.primary
                    font { family: glyph !== "" ? Icons.family : root.c.font; pixelSize: 12; weight: Font.Medium }
                }
            }
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.label
            color: root.strong || root.hovered ? root.c.title : root.c.text; font.family: root.c.font; font.pixelSize: 13
        }
    }
}
