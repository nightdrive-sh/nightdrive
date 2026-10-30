.pragma library

// Where ⌥← / ⌥→ moves the cursor in s from pos: past the spaces and punctuation, then past the word (letters of any
// alphabet, digits, _). dir is -1 or 1. The launcher's search field and Ask Claude's field share these.
function pos(s, pos, dir) {
    const isWord = c => c.toLowerCase() !== c.toUpperCase() || /[0-9_]/.test(c)
    const at = i => s.charAt(dir < 0 ? i - 1 : i)
    const inside = i => dir < 0 ? i > 0 : i < s.length
    while (inside(pos) && !isWord(at(pos))) pos += dir
    while (inside(pos) && isWord(at(pos))) pos += dir
    return pos
}

// ⌘⌫ / ⌥⌫ in a text field (TextInput or TextEdit), which Hyprland takes and sends over IPC: the selection, else back to
// the line's start (⌘) or over the word to the cursor's left (⌥), as in macOS
function deleteBack(input, word) {
    if (input.selectedText !== "") { input.remove(input.selectionStart, input.selectionEnd); return }
    const end = input.cursorPosition
    let start = input.text.lastIndexOf("\n", end - 1) + 1
    if (word) {
        start = end
        while (start > 0 && /\s/.test(input.text[start - 1])) start--
        while (start > 0 && !/\s/.test(input.text[start - 1])) start--
    }
    if (start < end) input.remove(start, end)
}
