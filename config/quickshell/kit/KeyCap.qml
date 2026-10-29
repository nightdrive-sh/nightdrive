import QtQuick
import qs

// Keys as caps (Key: the launcher's), for an app's hints and key sheet: "⌘N  c" (alternatives two spaces apart) is
// [⌘][N] [c]. Within an alternative every key is a cap of its own: "⌘⇧C", "Ctrl+B" and "↑ ↓" split into keys, and
// what isn't a key ("click", "…", "–") stays text between them.
Row {
    id: root
    property QtObject c: null           // the app's look, as every kit part takes it; the caps use the theme's colours
    property string keys: ""
    property color tint: Theme.dim      // the keys' colour: a hint's dim, as the launcher's secondary caps; the key sheet's accent
    property bool or: false             // "/" between the alternatives (the key sheet), as the launcher's Keybindings show them
    readonly property string symbols: "⌘⇧⌥⌃⏎⌫↑↓←→"
    // "⌘⇧C" → [{ key: "⌘" }, { key: "⇧" }, { key: "C" }]; "Ctrl+B" → [Ctrl, B]; "⇧-click" → [⇧, text "click"]
    function parts(alt) {
        const out = []
        for (const w of alt.split(" ")) {
            if (w === "") continue
            if (/^(click|double)$/i.test(w) || /^[…–-]$/.test(w)) { out.push({ text: w }); continue }
            const click = w.match(/^(.*?)-click$/i)
            if (click) { for (const k of words(click[1])) out.push({ key: k }); out.push({ text: "click" }); continue }
            for (const k of words(w)) out.push({ key: k })
        }
        return out
    }
    // One word's keys: names joined by "+" (Ctrl+Shift+A), or each symbol a key and the rest one name (⌘F2 → ⌘, F2)
    function words(w) {
        if (/^[A-Za-z]+\+./.test(w)) return w.split("+").filter(k => k !== "")
        const out = []
        let name = ""
        for (const ch of w) {
            if (symbols.includes(ch)) { if (name !== "") out.push(name); name = ""; out.push(ch) }
            else name += ch
        }
        if (name !== "") out.push(name)
        return out
    }
    spacing: 8
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
                rightPadding: 4
                text: "/"; color: Theme.dim; font.family: Theme.font; font.pixelSize: 12
            }
            Repeater {
                model: root.parts(alt.modelData)
                delegate: Item {
                    id: part
                    required property var modelData
                    anchors.verticalCenter: parent.verticalCenter
                    width: modelData.key ? cap.width : word.implicitWidth
                    height: modelData.key ? cap.height : word.implicitHeight
                    Key { id: cap; visible: !!part.modelData.key; key: part.modelData.key || ""; ink: root.tint }
                    Text {
                        id: word
                        visible: !part.modelData.key
                        anchors.verticalCenter: parent.verticalCenter
                        text: part.modelData.text || ""; color: root.tint; font.family: Theme.font; font.pixelSize: 12
                    }
                }
            }
        }
    }
}
