import QtQuick

// ⌘⇧V over a launcher text field (Snippets › text, Rename space, Wi-Fi password…): the Clipboard level opens as a picker
// for that field. Enter puts the picked text in the field at the cursor and returns there, Esc (Backspace) returns
// without it; what was typed is kept either way. A level counts as a field when its Levels file lists it in `inputs`.
// ToolsLevels owns it (the Clipboard level is there); Launcher.qml asks begin() from openLevel and back() from back().
QtObject {
    id: p
    property var launcher: null
    property var from: null                   // { level, text, cursor } while picking, otherwise null
    readonly property bool active: from !== null

    // Whether the open level is a text field. Asked by ⌘⇧V (openLevel clipboard): true = the picker took it
    function begin() {
        const l = launcher
        const e = l.open ? l.extOf(l.level) : null
        if (!e || !e.inputs || e.inputs.indexOf(l.level) < 0) return false
        from = { level: l.level, text: l.field.text, cursor: l.field.cursorPosition }
        l.go("clipboard")
        return true
    }
    // Back to the field with its text and cursor as they were, `text` inserted at the cursor
    function finish(text) {
        const f = from, l = launcher
        from = null
        // Snippets › text writes its line breaks as ↵ (the field has one line); other fields get spaces
        const t = text.replace(/\r?\n+$/, "").replace(/\r?\n/g, f.level === "sniptext" ? "↵" : " ")
        l.search(f.level, f.text.slice(0, f.cursor) + t + f.text.slice(f.cursor))
        l.field.cursorPosition = f.cursor + t.length
    }
    // Esc / Backspace with an empty search (Launcher.back): true = handled
    function back() {
        if (!active || launcher.level !== "clipboard") return false
        finish("")
        return true
    }
    // Enter on a row: its whole text (the list shows only a preview), then back. A picture can't go in a text field
    function pick(it) {
        if (it.glyph === "image") { launcher.shakeNow(); return }
        decode.command = ["cliphist", "decode", it.id]
        decode.running = true
    }
    function reset() { from = null }

    property Sh decode: Sh { onResult: text => { if (p.active) p.finish(text) } }
}
