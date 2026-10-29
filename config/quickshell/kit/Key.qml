import QtQuick
import qs

// One key as a rounded cap a little lighter than what it stands on, as in Raycast's footer: "Actions [⌘] [K]". The
// launcher's footer, rows and Keybindings use it directly; the apps through KeyCap, which turns "⌘N  c" into these.
// key is a name (Enter, Cmd, Esc, F3, K) or a symbol (⌘ ⇧ ⌥ ⌃ ⌫ ⏎ ↑ ↓ ← →); modifiers and arrows show as Lucide glyphs,
// since JetBrains Mono's ⇧ is a faint outline. dim: a secondary action's cap, quieter than the primary's.
Rectangle {
    id: cap
    property string key: ""
    property bool dim: false
    property int size: 22
    property color ink: dim ? Theme.dim : Theme.text     // the key's colour: an app's key sheet gives its accent

    readonly property var glyphs: ({ Enter: "corner-down-left", Ctrl: "chevron-up", Shift: "arrow-big-up", Alt: "option",
                                     Cmd: "command", Up: "arrow-up", Down: "arrow-down", Left: "arrow-left", Right: "arrow-right",
                                     Backspace: "delete", Space: "space" })
    readonly property var symbols: ({ "⌘": "Cmd", "⇧": "Shift", "⌥": "Alt", "⌃": "Ctrl", "⌫": "Backspace", "⏎": "Enter",
                                      "↑": "Up", "↓": "Down", "←": "Left", "→": "Right", Return: "Enter" })
    readonly property string name: symbols[key] || key
    readonly property string glyph: glyphs[name] || ""
    // a letter (K) and a function key (F3) stay as they are; Hyper, a modifier with no symbol, is in capitals like the
    // bar's tags; other names (esc, tab) are small
    readonly property bool letter: glyph === "" && (name.length === 1 || /^F\d+$/.test(name))

    // A glyph or a single character is a square cap (a glyph is wider than a letter, and would stretch it); a name
    // (HYPER, esc, F12) is as wide as it needs. The tint of the text colour lightens any background the same way.
    width: glyph !== "" || name.length === 1 ? size : Math.max(size, label.implicitWidth + 12); height: size; radius: 5
    color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, dim ? 0.08 : 0.13)

    Text {
        id: label
        anchors.centerIn: parent
        text: cap.glyph !== "" ? Icons.g(cap.glyph) : cap.letter ? cap.name : cap.name === "Hyper" ? "HYPER" : cap.name.toLowerCase()
        color: cap.ink
        font { family: cap.glyph !== "" ? Icons.family : Theme.font; pixelSize: cap.glyph !== "" ? 12 : cap.letter ? 13 : 11
               weight: cap.letter ? Font.Bold : Font.DemiBold }
    }
}
