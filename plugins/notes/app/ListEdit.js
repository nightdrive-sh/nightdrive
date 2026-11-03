.pragma library

// The Markdown rules of the editor's help (EditorHelp.qml) and of ticking a task box while reading (TaskBoxes.qml), as
// plain functions over text: no editor in here, so they read alike wherever they are used. Each answers with the change
// to make, never makes it, so the editor can make it in as few steps as its undo needs.

// The line around pos: where it starts and ends, and its text
function lineAt(text, pos) {
    const start = text.lastIndexOf("\n", pos - 1) + 1
    let end = text.indexOf("\n", pos)
    if (end < 0) end = text.length
    return { start: start, end: end, text: text.slice(start, end) }
}

// A list item's parts: "  - [ ] milk" is indent "  ", marker "-", box " ", rest "milk". null for any other line.
// A number's delimiter is kept ("1)" goes on as "2)"). The marker needs its space: "-foo" and "1.5" are not items.
const ITEM = /^([ \t]*)([-*+]|\d{1,9}[.)])([ \t]+)(\[[ xX]\][ \t]+)?(.*)$/
function item(line) {
    const m = line.match(ITEM)
    if (!m) return null
    // A rule ("- - -", "***") is not an item, though it starts like one
    if (/^\s{0,3}([-*_])(\s*\1){2,}\s*$/.test(line)) return null
    return {
        indent: m[1], marker: m[2], gap: m[3], box: m[4] ? m[4][1] : null, rest: m[5],
        content: m[1].length + m[2].length + m[3].length + (m[4] ? m[4].length : 0),  // where the item's text starts
        boxAt: m[4] ? m[1].length + m[2].length + m[3].length + 1 : -1                  // its box's x or space
    }
}

// Enter at pos with nothing selected: what to do, or null for a plain new line. On an item with text, the next item
// ("- ", the next number, an empty box) after the new line: { insert, at }. On an empty item, the list ends there: an
// indented one moves out a level, one at the left edge loses its marker: { remove: [from, to] }. Only with the cursor
// past the marker: Enter before it is a plain new line, as anywhere else.
function enter(text, pos) {
    const line = lineAt(text, pos)
    const it = item(line.text)
    if (!it || pos - line.start < it.content) return null
    if (!it.rest.trim() && pos === line.end) {
        if (it.indent.length) {
            const out = outdentWidth(text, line.start, it)
            return { remove: [line.start, line.start + out] }
        }
        return { remove: [line.start, line.end] }
    }
    const n = it.marker.match(/^(\d+)(.)$/)
    const marker = n ? (+n[1] + 1) + n[2] : it.marker
    return { insert: "\n" + it.indent + marker + it.gap + (it.box !== null ? "[ ] " : ""), at: pos }
}

// The item above a line (the nearest item before it with less indent), or null: Tab nests under it, ⇧Tab goes back
// to its level
function parentOf(text, lineStart, indent) {
    let end = lineStart - 1
    while (end > 0) {
        const line = lineAt(text, end)
        if (!line.text.trim()) return null             // a blank line ends the list
        const it = item(line.text)
        if (it && it.indent.length < indent) return it
        end = line.start - 1
    }
    return null
}

// Tab on an item: in under the item above it, its text's column (what Markdown reads as nested: three spaces under
// "1. "), or two spaces deeper without one
function indentWidth(text, lineStart, it) {
    let end = lineStart - 1, above = null
    while (end > 0 && !above) {
        const line = lineAt(text, end)
        if (!line.text.trim()) break
        above = item(line.text)
        end = line.start - 1
    }
    if (above && above.content > it.indent.length) return above.content - it.indent.length
    return 2
}

// ⇧Tab on an item: back to the indent of the item it is nested under, or out of the indent when there is none
function outdentWidth(text, lineStart, it) {
    const parent = parentOf(text, lineStart, it.indent.length)
    const to = parent ? parent.indent.length : 0
    return Math.max(0, it.indent.length - to)
}

// Tab or ⇧Tab over the lines from..to (a selection, or the cursor's line): the same width added at each item's start or
// taken from it, the first item's (indentWidth, outdentWidth). Lines that aren't items are left as they are. null
// when the first line isn't an item: Tab is then a tab, as without the help. Each change is [at, insert] or [at, -n],
// last line first, so each one leaves the places of the ones after it as they are.
function shift(text, from, to, out) {
    if (to > from && text[to - 1] === "\n") to--          // whole lines selected: not the one after them
    const first = lineAt(text, from)
    const it = item(first.text)
    if (!it) return null
    const width = out ? outdentWidth(text, first.start, it) : indentWidth(text, first.start, it)
    const changes = []
    let start = first.start
    while (true) {
        const line = lineAt(text, start)
        const li = item(line.text)
        if (li) {
            if (!out) changes.push([line.start, " ".repeat(width)])
            else if (Math.min(width, li.indent.length)) changes.push([line.start, -Math.min(width, li.indent.length)])
        }
        if (line.end >= to || line.end >= text.length) break
        start = line.end + 1
    }
    return changes.reverse()
}

// ⌘B and ⌘I: mark is "**" or "_". The selection from..to without the spaces at its ends, as a double click or a drag
// past a word picks them up. Already inside the marks (just outside the selection, or its own ends): unwrap, else
// wrap. With nothing selected, the marks go in with the cursor between them. Answers { changes, select: [from, to] },
// the changes last place first, as shift's.
function emphasis(text, from, to, mark) {
    const n = mark.length
    if (from === to)
        return { changes: [[from, mark + mark]], select: [from + n, from + n] }
    while (from < to && /\s/.test(text[from])) from++
    while (to > from && /\s/.test(text[to - 1])) to--
    const inside = text.slice(from, to)
    if (text.slice(from - n, from) === mark && text.slice(to, to + n) === mark && !(n === 1 && boldAround(text, from, to)))
        return { changes: [[to, -n], [from - n, -n]], select: [from - n, to - n] }
    if (inside.length >= 2 * n && inside.startsWith(mark) && inside.endsWith(mark))
        return { changes: [[to - n, -n], [from, -n]], select: [from, to - 2 * n] }
    return { changes: [[to, mark], [from, mark]], select: [from + n, to + n] }
}
// "_" alone inside "__x__" is bold's, not italic's
function boldAround(text, from, to) { return text[from - 2] === text[from - 1] && text[to] === text[to + 1] }

// ⌘K: the selection as a link's text, and the address from the clipboard when it holds one ("[text](https://…)", the
// cursor after it); without one, the cursor between the parentheses for it. Nothing selected: "[](…)", the cursor in
// the brackets for the text.
function link(text, from, to, clip) {
    const url = /^(https?:\/\/|mailto:)\S+$/i.test(clip.trim()) ? clip.trim() : ""
    while (from < to && /\s/.test(text[from])) from++
    while (to > from && /\s/.test(text[to - 1])) to--
    const label = to - from
    const close = "](" + url + ")"
    const changes = [[to, close], [from, "["]]
    const end = to + 1 + close.length
    const at = label === 0 ? from + 1 : url ? end : end - 1
    return { changes: changes, select: [at, at] }
}

// The task boxes in a note, in order: the place of each one's mark (the x or the space between its brackets). Code
// blocks are left out, as reading shows them as code; the k-th box here is the k-th one Markdown.html draws.
function boxes(md) {
    const out = []
    let pos = 0, fence = false
    for (const line of md.split("\n")) {
        if (/^\s*(```|~~~)/.test(line)) fence = !fence
        else if (!fence) {
            const it = item(line)
            if (it && it.box !== null) out.push(pos + it.boxAt)
        }
        pos += line.length + 1
    }
    return out
}

// The note with its k-th box ticked or unticked; null when it has no such box (changed meanwhile)
function toggle(md, k) {
    const at = boxes(md)[k]
    if (at === undefined) return null
    return md.slice(0, at) + (md[at] === " " ? "x" : " ") + md.slice(at + 1)
}
