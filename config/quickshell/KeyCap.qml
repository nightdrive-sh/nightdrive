import QtQuick

// One key as a rounded cap a little lighter than what it stands on, as in Raycast's footer: "Actions [⌘] [K]".
// key is a name (Enter, Cmd, Esc, F3, K) or a SHORTCUTS.md symbol (⌘ ⇧ ⌥ ⌃ ⌫); modifiers and arrows show as Lucide
// glyphs, since JetBrains Mono's ⇧ is a faint outline. dim: a secondary action's cap, quieter than the primary's.
Rectangle {
    id: cap
    property string key: ""
    property bool dim: false
    property int size: 22

    readonly property var glyphs: ({ Enter: "corner-down-left", Ctrl: "chevron-up", Shift: "arrow-big-up", Alt: "option",
                                     Cmd: "command", Up: "arrow-up", Down: "arrow-down", Left: "arrow-left", Right: "arrow-right",
                                     Backspace: "delete", Space: "space" })
    readonly property var symbols: ({ "⌘": "Cmd", "⇧": "Shift", "⌥": "Alt", "⌃": "Ctrl", "⌫": "Backspace" })
    readonly property string name: symbols[key] || key
    readonly property string glyph: glyphs[name] || ""
    // a letter (K) and a function key (F3) stay capitals; Hyper, a modifier with no symbol, is in capitals like the bar's
    // tags; other names (esc, tab) are small
    readonly property bool letter: glyph === "" && (name.length === 1 || /^F\d+$/.test(name))

    // Square for a glyph or a letter, wider for a name; the tint of the text colour lightens any background the same way
    width: Math.max(size, label.implicitWidth + 12); height: size; radius: 5
    color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, dim ? 0.08 : 0.13)

    Text {
        id: label
        anchors.centerIn: parent
        text: cap.glyph !== "" ? Icons.g(cap.glyph) : cap.letter ? cap.name : cap.name === "Hyper" ? "HYPER" : cap.name.toLowerCase()
        color: cap.dim ? Theme.dim : Theme.text
        font { family: cap.glyph !== "" ? Icons.family : Theme.font; pixelSize: cap.glyph !== "" ? 12 : cap.letter ? 13 : 11
               weight: cap.letter ? Font.Bold : Font.DemiBold }
    }
}
