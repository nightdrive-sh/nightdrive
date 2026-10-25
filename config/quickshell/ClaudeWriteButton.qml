import QtQuick

// A button of the Claude writes card (ClaudeWrite.qml): its key in the theme colour, then what it does, for the mouse
// as well as the key. No frame: a lighter ground sets it off the card, and the one Enter presses (strong) has the
// theme's selection colour, as a menu's buttons do. ⌘ ⇧ ⏎ are Lucide glyphs (the font's ⇧ is faint).
Rectangle {
    id: b
    property var keys: []               // "Enter", "Cmd", "Shift", "Esc" or a letter
    property string label: ""
    property bool strong: false
    readonly property alias hovered: hover.hovered
    signal clicked()

    readonly property var glyphs: ({ Enter: "corner-down-left", Cmd: "command", Shift: "arrow-big-up" })

    implicitWidth: row.implicitWidth + 21
    implicitHeight: 34
    radius: 9
    // Under the mouse just brighter, as MenuButton
    color: strong ? (hovered ? Qt.lighter(Theme.sel, 1.3) : Theme.sel)
                  : Qt.rgba(1, 1, 1, hovered ? 0.11 : 0.06)

    HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
    TapHandler { onTapped: b.clicked() }

    Row {
        id: row
        x: 9
        anchors.verticalCenter: parent.verticalCenter
        spacing: 8
        Row {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 3
            Repeater {
                model: b.keys
                Text {
                    required property string modelData
                    readonly property string glyph: b.glyphs[modelData] || ""
                    anchors.verticalCenter: parent.verticalCenter
                    text: glyph !== "" ? Icons.g(glyph) : modelData.length === 1 ? modelData : modelData.toLowerCase()
                    color: Theme.primary
                    font { family: glyph !== "" ? Icons.family : Theme.font
                           pixelSize: glyph !== "" ? 11 : 12; weight: Font.Medium }
                }
            }
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: b.label
            color: b.strong || b.hovered ? Theme.title : Theme.text
            font { family: Theme.font; pixelSize: 12 }
        }
    }
}
