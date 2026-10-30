.pragma library

// Where ⌥← / ⌥→ moves the cursor in s from pos: past the spaces and punctuation, then past the word (letters of any
// alphabet, digits, _). dir is -1 or 1. The launcher's search field and Ask Claude's field share it.
function pos(s, pos, dir) {
    const isWord = c => c.toLowerCase() !== c.toUpperCase() || /[0-9_]/.test(c)
    const at = i => s.charAt(dir < 0 ? i - 1 : i)
    const inside = i => dir < 0 ? i > 0 : i < s.length
    while (inside(pos) && !isWord(at(pos))) pos += dir
    while (inside(pos) && isWord(at(pos))) pos += dir
    return pos
}
