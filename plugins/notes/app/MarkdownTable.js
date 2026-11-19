.pragma library

// Pipe tables for Markdown.js (#3209): "| a | b |", then "| --- | :---: |", then the rows. Qt's rich text lays an HTML
// table out by itself: each column as wide as its content wants, and in a narrow window the cells wrap at their spaces
// rather than the table growing past the text's width, so the window never widens for it. Its borders are all or none
// (a cell's own border style is ignored), so a faint grid in the theme's line colour, the header in the titles' colour.

// The separator under the header: each cell dashes, with a colon at the side the column is aligned to
const SEPARATOR = /^\s*\|?\s*:?-+:?\s*(\|\s*:?-+:?\s*)*\|?\s*$/

// Whether lines[i] starts a table: a row with a pipe, the separator under it, with as many cells
function starts(lines, i) {
    if (i + 1 >= lines.length || !lines[i].includes("|") || !SEPARATOR.test(lines[i + 1])) return false
    return cells(lines[i]).length === cells(lines[i + 1]).length
}

// A row's cells: split at its pipes, but not at an escaped one ("\|") nor at one inside `code`
function cells(line) {
    let s = line.trim()
    if (s.startsWith("|")) s = s.slice(1)
    if (s.endsWith("|") && !s.endsWith("\\|")) s = s.slice(0, -1)
    const out = []
    let cell = "", code = false
    for (let i = 0; i < s.length; i++) {
        const ch = s[i]
        if (ch === "\\" && s[i + 1] === "|") { cell += "|"; i++; continue }
        if (ch === "`") code = !code
        if (ch === "|" && !code) { out.push(cell.trim()); cell = ""; continue }
        cell += ch
    }
    out.push(cell.trim())
    return out
}

function aligns(separator) {
    return cells(separator).map(s => s.endsWith(":") ? (s.startsWith(":") ? "center" : "right") : "left")
}

// How many lines from lines[i] on are the table: the header, the separator and the rows up to a blank line or a line
// without a pipe (GitHub's way: a row may leave out its outer pipes)
function length(lines, i) {
    let n = 2
    while (i + n < lines.length && lines[i + n].trim() && lines[i + n].includes("|")) n++
    return n
}

// Code in a cell breaks only at its spaces: Qt would break a narrow column's "./play --skip --daylight" after "--", which
// reads as another command. A word joiner after each hyphen keeps it whole; the column wraps at the spaces.
function unbroken(html) {
    return html.replace(/(<code[^>]*>)(.*?)(<\/code>)/g, (m, open, code, close) => open + code.replace(/-/g, "-\u2060") + close)
}

// The table's HTML; inline is Markdown.js's own (bold, code, links inside a cell), c the look for the colours. A row
// with fewer cells than the header gets empty ones, extra cells are left out, as GitHub does.
function html(lines, inline, c) {
    const align = aligns(lines[1])
    function row(line, head) {
        const got = cells(line)
        return "<tr>" + align.map((a, k) => {
            const text = k < got.length ? unbroken(inline(got[k], c)) : ""
            const tag = head ? "th" : "td"
            // No background for the header: Qt fills only inside the cell's padding, a bar in a box
            const look = head ? ` style="color:${c.title}"` : ""
            return `<${tag} align="${a}" valign="top"${look}>${text}</${tag}>`
        }).join("") + "</tr>"
    }
    const body = lines.slice(2).map(l => row(l, false)).join("")
    // A small empty line above: Qt ignores a table's own top margin, and a heading's would leave it right under it
    return `<p style="font-size:4px; margin-top:0; margin-bottom:0">&nbsp;</p>`
           + `<table border="1" cellspacing="0" cellpadding="6" style="border-collapse:collapse; border-style:solid; `
           + `border-color:${c.line}; margin-bottom:8px">`
           + `<thead>${row(lines[0], true)}</thead>${body}</table>`
}
