pragma Singleton
import QtQuick
import Quickshell
import "Words.js" as Words

// ⌥ word keys in the apps' text fields, as on macOS (#3725): ⌥← ⌥→ move by word, ⌥⇧← ⌥⇧→ select by word, ⌥⌫ ⌥⌦
// delete a word. Qt's TextInput and TextEdit move by word only with Ctrl on Linux, and Alt + an arrow does nothing in
// them; ⌥ comes to Nightdrive's windows as Alt (hypr/option-keys.lua), so every field hands its presses here first:
//   Keys.onPressed: e => { if (TextKeys.key(e, this)) return; … the field's own keys }
// The words are the launcher's (Words.js): past spaces and punctuation, then the word. ⌥⌫ with the Mac Keyboard
// Shortcuts plugin comes as Ctrl+⌫ (keyd), which Qt deletes a word with itself.
Singleton {
    // Takes the key (accepted, true) when it is one of these, in a TextInput or TextEdit
    function key(e, field) {
        if ((e.modifiers & (Qt.AltModifier | Qt.ControlModifier | Qt.MetaModifier)) !== Qt.AltModifier) return false
        const k = e.key
        if (k === Qt.Key_Left || k === Qt.Key_Right) move(field, k === Qt.Key_Left ? -1 : 1, (e.modifiers & Qt.ShiftModifier) !== 0)
        else if ((k === Qt.Key_Backspace || k === Qt.Key_Delete) && !field.readOnly) remove(field, k === Qt.Key_Backspace ? -1 : 1)
        else return false
        e.accepted = true
        return true
    }

    // Where the cursor goes by a word: a hidden password's words aren't shown, so it goes to the end, as macOS does
    function target(field, dir) {
        if (field.echoMode !== undefined && field.echoMode !== TextInput.Normal) return dir < 0 ? 0 : field.length
        // getText, not text: a rich TextEdit's text is HTML, whose places aren't the cursor's
        return Words.pos(field.getText(0, field.length), field.cursorPosition, dir)
    }

    // ⇧ extends the selection from its other end (moveCursorSelection keeps the end the cursor isn't at)
    function move(field, dir, extend) {
        const to = target(field, dir)
        if (extend) { field.moveCursorSelection(to); return }
        field.deselect()
        field.cursorPosition = to
    }

    // A selection goes as a whole, else the word before (⌫) or after (⌦) the cursor
    function remove(field, dir) {
        if (field.selectedText !== "") { field.remove(field.selectionStart, field.selectionEnd); return }
        const at = field.cursorPosition, to = target(field, dir)
        if (to !== at) field.remove(Math.min(at, to), Math.max(at, to))
    }
}
