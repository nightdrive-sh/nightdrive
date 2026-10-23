import QtQuick
import qs

// Keys in rounded boxes, as the desktop's Claude writes card shows them: "⌘N  c" (alternatives two spaces apart) is a box
// for each. A hint puts these first and its text after them. ⌘ ⇧ ⌥ ⏎ and the arrows are Lucide glyphs, as in the
// launcher's footer (the font's own ⇧ and ⌘ are faint); a letter beside them is as big and heavy as they are.
Row {
    id: root
    required property QtObject c
    property string keys: ""
    property color tint: c.dim
    property bool or: false             // "/" between the alternatives (the key sheet), as the launcher's Keybindings show them; a pair of opposites ("← →") is one box
    readonly property var glyphs: ({ "⌘": "command", "⇧": "arrow-big-up", "⌥": "option", "⌃": "chevron-up", "⏎": "corner-down-left",
                                     "⌫": "delete", "↑": "arrow-up", "↓": "arrow-down", "←": "arrow-left", "→": "arrow-right" })
    // "⌘⇧C" → [{ glyph: "command" }, { glyph: "arrow-big-up" }, { text: "C" }]; spaces only separate
    function parts(box) {
        const out = []
        let text = ""
        const flush = () => { for (const w of text.split(" ")) if (w !== "") out.push({ text: w }); text = "" }
        for (const ch of box) {
            if (glyphs[ch]) { flush(); out.push({ glyph: glyphs[ch] }) }
            else text += ch
        }
        flush()
        return out
    }
    spacing: 4
    Repeater {
        model: root.keys.split("  ").filter(k => k !== "")
        delegate: Row {
            id: alt
            required property string modelData
            required property int index
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4
            Text {
                visible: root.or && alt.index > 0
                anchors.verticalCenter: parent.verticalCenter
                text: "/"; color: root.c.faint; font.family: root.c.font; font.pixelSize: 12
            }
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.max(22, caps.implicitWidth + 14); height: 22; radius: 6
                color: "transparent"
                border { width: 1; color: root.tint }
                Row {
                    id: caps
                    anchors.centerIn: parent
                    spacing: 3
                    Repeater {
                        model: root.parts(alt.modelData)
                        delegate: Text {
                            required property var modelData
                            readonly property bool letter: !modelData.glyph && modelData.text.length === 1
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.glyph ? Icons.g(modelData.glyph) : modelData.text
                            color: root.tint
                            font { family: modelData.glyph ? Icons.family : root.c.font
                                   pixelSize: modelData.glyph ? 12 : letter ? 13 : 11
                                   weight: letter ? Font.Medium : Font.Normal }
                        }
                    }
                }
            }
        }
    }
}
