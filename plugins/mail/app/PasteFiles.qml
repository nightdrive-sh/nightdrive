import QtQuick
import Quickshell
import Quickshell.Io

// A paste in the message being written (#3304): files on the clipboard (Files' ⌘C / y, another file browser's copy)
// are attached, as `nightmail new FILE…` and a drop attach them; anything else pastes as text, as before. The clipboard
// is asked first (lib/clipfiles.py), so the key is taken from the field and the text pasted into it afterwards: the
// same field, where the caret was. Apart from Compose.qml, which hands each of its fields' keys here.
QtObject {
    id: root
    required property var composer          // Compose.qml: attach(), status, failed

    property var target: null               // the field the paste goes into, should it be text
    readonly property Process reader: Process {
        command: ["python3", Quickshell.shellDir + "/../lib/clipfiles.py"]
        stdout: StdioCollector { onStreamFinished: root.read(text) }
    }

    // ⌘V comes as Shift+Insert (Hyprland's bindings.lua); Ctrl+V and the platform's Paste too
    function isPaste(e) {
        return e.matches(StandardKey.Paste) || (e.key === Qt.Key_Insert && e.modifiers & Qt.ShiftModifier)
            || (e.key === Qt.Key_V && (e.modifiers & Qt.ControlModifier) && !(e.modifiers & Qt.ShiftModifier))
    }
    // For a field's Keys.onPressed: true (and the key taken) when it was a paste
    function key(e, field) {
        if (!isPaste(e)) return false
        e.accepted = true
        if (reader.running) return true
        target = field
        reader.running = true
        return true
    }
    function read(text) {
        let r = null
        try { r = JSON.parse(text) } catch (err) {}
        const files = r ? r.files : [], folders = r ? r.folders : []
        if (!files.length && !folders.length) { if (target) target.paste(); return }
        if (files.length) composer.attach(files)
        if (folders.length) {
            composer.failed = true
            composer.status = folders.length === 1 ? "A folder isn't attached: compress it first (c in Files)"
                            : folders.length + " folders aren't attached: compress them first (c in Files)"
        }
    }
}
