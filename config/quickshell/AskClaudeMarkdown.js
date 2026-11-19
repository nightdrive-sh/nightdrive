.pragma library
.import "kit/Markdown.js" as Markdown

// Claude's answer in Ask Claude's conversation (AskClaudeThread.qml) as formatted text, by the kit's Markdown.js (as Notes
// and Inbox show theirs) rather than Qt's MarkdownText, which colours links its own blue and passes HTML through.
// While the answer is still being written (live), its last line is often half-done Markdown: "**Fil" would show its
// stars until "**" closes it, and then jump to bold. ready() makes such a tail what it will be, so nothing flickers.

// Theme's colours as Markdown.js wants them (c: Theme), with headings a step or two over the answer's size (px), not
// a note's big titles, code blocks on the card colour, and no #tag links (they open a note's tag in Notes)
function look(c, size) {
    return {
        primary: c.primary, accent: c.accent, line: c.border, dim: c.dim, title: c.title, code: c.card,
        headings: [0, size + 3, size + 2, size + 1, size, size, size], tags: false
    }
}

// The last line's open marks closed and its half-typed starts left out. Inside a code block that is still open, nothing:
// Markdown.js shows an unclosed block as code to the end.
function ready(md) {
    const lines = md.replace(/\s+$/, "").split("\n")
    const fences = lines.filter(l => /^\s*(```|~~~)/.test(l)).length
    if (fences % 2) {
        // Its closing fence half-typed ("``"): left out until it closes the block
        if (/^\s*(`{1,2}|~{1,2})\s*$/.test(lines[lines.length - 1])) lines.pop()
        return lines.join("\n")
    }
    let last = lines.pop()
    // Only a mark so far ("#", "-", "1.", "``"): the line comes once its text does
    if (/^\s*(#{1,6}|[-*+]|\d+[.)]?|`{1,2}|~{1,2}|>)\s*$/.test(last)) last = ""
    // A mark just opened, its text still to come ("see **"): it comes with its text
    last = last.replace(/(^|\s)[*_`~]+$/, "$1")
    // A link whose address is still coming: its text alone until then
    last = last.replace(/\[([^\]]*)(\]\([^)]*)?$/, "$1")
    // An open `code`, then **bold**, then *italic* or _italic_, each closed where the line ends. The list's own
    // marker ("* item") and code's insides don't count.
    if ((last.match(/`/g) || []).length % 2) last += "`"
    const plain = last.replace(/`[^`]*`/g, "").replace(/^\s*[-*+]\s+/, "")
    if ((plain.match(/\*\*/g) || []).length % 2) last += "**"
    const single = plain.replace(/\*\*/g, "")
    if ((single.match(/\*/g) || []).length % 2) last += "*"
    else if ((single.match(/(^|\W)_|_(?=\W|$)/g) || []).length % 2) last += "_"
    lines.push(last)
    return lines.join("\n")
}

// The HTML for a TextEdit's RichText; live: the answer is still coming
function html(md, c, size, live) {
    return Markdown.html(live ? ready(md) : md, look(c, size))
}
