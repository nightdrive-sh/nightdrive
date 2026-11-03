import QtQuick
import Quickshell
import "ListEdit.js" as ListEdit

// The editor's help with Markdown (NoteEditor.qml): Enter goes on with a list (and ends it on an empty item), Tab and
// ⇧Tab nest a list item and take it back, ⌘B and ⌘I make the selection bold and italic (or no longer), ⌘K makes it a
// link. The text stays the Markdown it is: each helps with typing what one would type anyway, and nothing else is
// changed. The rules are ListEdit.js's.
//
// Undo: TextEdit's own stack, so ⌘Z undoes the help as it undoes typing. A change in two places (bold's two "**")
// is two steps on that stack, as QML can't group them; such a change is noted here (steps), and ⌘Z and ⇧⌘Z take its
// steps together while the text is still what the change left, so each press undoes or redoes one whole step.
QtObject {
    id: root
    required property TextEdit area

    property var undos: []        // the changes made in more than one step: { before, after, steps }, the latest last
    property var redos: []
    property bool applying: false
    readonly property int keep: 50

    // A note read in (begin, take): TextEdit's stack starts again with it, and so do these
    function reset() { undos = []; redos = [] }

    // The editor's keys first come here: true when one was the help's
    function key(e) {
        const ctrl = e.modifiers & (Qt.ControlModifier | Qt.MetaModifier)
        const shift = e.modifiers & Qt.ShiftModifier
        const alt = e.modifiers & Qt.AltModifier
        const a = area
        if (ctrl && !alt && e.key === Qt.Key_Z) return shift ? redo() : undo()
        if (ctrl && !alt && !shift && e.key === Qt.Key_Y) return redo()
        if (ctrl && !alt && !shift && e.key === Qt.Key_B) return emphasis("**")
        if (ctrl && !alt && !shift && e.key === Qt.Key_I) return emphasis("_")
        if (ctrl && !alt && !shift && e.key === Qt.Key_K) return link()
        if (ctrl || alt) return false
        if ((e.key === Qt.Key_Return || e.key === Qt.Key_Enter) && !shift && a.selectionStart === a.selectionEnd) {
            const r = ListEdit.enter(a.text, a.cursorPosition)
            if (!r) return false
            // One step each: an insert, or a removal (the cursor, at the line's end, stays there)
            if (r.insert !== undefined) { apply([[r.at, r.insert]]); a.cursorPosition = r.at + r.insert.length }
            else apply([[r.remove[0], r.remove[0] - r.remove[1]]])
            return true
        }
        if (e.key === Qt.Key_Tab || e.key === Qt.Key_Backtab) {
            const out = e.key === Qt.Key_Backtab || shift
            const from = a.selectionStart, to = a.selectionEnd, at = a.cursorPosition
            const changes = ListEdit.shift(a.text, from, to, out)
            if (!changes) return out        // ⇧Tab off a list does nothing, rather than move the keyboard elsewhere
            if (!changes.length) return true
            // The cursor or selection moves with its line's text
            const moved = p => p + changes.reduce((d, c) => d + (c[0] < p || (c[0] === p && typeof c[1] === "string") ? delta(c, p) : 0), 0)
            apply(changes)
            if (from === to) a.cursorPosition = moved(at)
            else a.select(moved(from), moved(to))
            return true
        }
        return false
    }

    // How far a change moves a place after it: an insert by its length, a removal by what it took before the place
    function delta(c, p) { return typeof c[1] === "string" ? c[1].length : -Math.min(-c[1], p - c[0]) }

    function emphasis(mark) {
        const r = ListEdit.emphasis(area.text, area.selectionStart, area.selectionEnd, mark)
        apply(r.changes)
        area.select(r.select[0], r.select[1])
        return true
    }
    function link() {
        const r = ListEdit.link(area.text, area.selectionStart, area.selectionEnd, Quickshell.clipboardText || "")
        apply(r.changes)
        area.cursorPosition = r.select[0]
        return true
    }

    // Changes in order, each [at, text] (an insert) or [at, -n] (n characters removed): each a step of TextEdit's undo
    function apply(changes) {
        const before = area.text
        applying = true
        for (const c of changes) {
            if (typeof c[1] === "string") area.insert(c[0], c[1])
            else area.remove(c[0], c[0] - c[1])
        }
        applying = false
        redos = []
        if (changes.length > 1) {
            const u = undos.concat([{ before: before, after: area.text, steps: changes.length }])
            undos = u.length > keep ? u.slice(u.length - keep) : u
        }
    }

    // ⌘Z: a change of the help's in several steps, all of them, while the text is what it left; else TextEdit's one
    function undo() {
        const last = undos.length ? undos[undos.length - 1] : null
        if (last && last.after === area.text) {
            for (let i = 0; i < last.steps; i++) area.undo()
            undos = undos.slice(0, -1)
            redos = redos.concat([last])
        } else area.undo()
        return true
    }
    function redo() {
        const next = redos.length ? redos[redos.length - 1] : null
        if (next && next.before === area.text) {
            for (let i = 0; i < next.steps; i++) area.redo()
            redos = redos.slice(0, -1)
            undos = undos.concat([next])
        } else area.redo()
        return true
    }
}
