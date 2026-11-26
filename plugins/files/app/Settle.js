.pragma library

// Which row to pick once the list's rows change (#3415): a delete, a move, a rename, a paste, an Undo or another app's
// change all come back as a new set of rows, and the pick must stay where the user was, not go back to the top.
//   before: the rows' paths as they were, index: the row picked among them (-1: none),
//   after:  the paths now, keep: a path to pick if it is there (one a change made, the folder come up from).
// In order: keep; the same file; the next row after it still there (the files deleted, moved or renamed away
// were picked or marked there); the last one before it still there (they were at the end); else the same index.
// The rows keep their order, so the next row still there is the one now in the place of the rows gone.
function place(before, index, after, keep) {
    if (!after.length) return -1
    const at = {}
    for (let i = 0; i < after.length; i++) at[after[i]] = i
    const has = p => Object.prototype.hasOwnProperty.call(at, p)
    if (keep && has(keep)) return at[keep]
    if (index >= 0 && index < before.length) {
        for (let i = index; i < before.length; i++) if (has(before[i])) return at[before[i]]
        for (let i = index - 1; i >= 0; i--) if (has(before[i])) return at[before[i]]
    }
    return Math.max(0, Math.min(index, after.length - 1))
}

// Where the view goes back to after its rows were set again (a new model resets it to the top): y as it was, kept
// inside what the shorter or longer list now has room for. top is the view's originY − topMargin, room its
// contentHeight + margins − height.
function scrollBack(y, top, room) { return Math.max(top, Math.min(y, top + Math.max(0, room))) }
