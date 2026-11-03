.pragma library

// A note's Markdown as the HTML Qt's rich text shows (NoteView.qml). Qt's own MarkdownText would do, but it colours links
// its own blue whatever the theme, and it passes HTML in the note through, pictures from the web and all. This one knows
// what notes use (headings, paragraphs, lists and checkboxes, quotes, code, rules, bold, italic, code, links) and shows
// anything else, HTML included, as the text it is: a note Claude wrote can't load anything or look like something else.

function escape(s) {
    return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;")
}

// Bold, italic, strike, code and links inside a line; c is the look (AppLook): its colours go in as styles
function inline(text, c) {
    const codes = []
    // Code first, so nothing inside it is read as Markdown
    let s = text.replace(/`([^`]+)`/g, (m, code) => { codes.push(code); return "\u0000" + (codes.length - 1) + "\u0000" })
    s = escape(s)
    s = s.replace(/!?\[([^\]]*)\]\(([^)\s]+)(?:\s+&quot;[^)]*&quot;)?\)/g, (m, label, url) => {
        if (!/^(https?:\/\/|mailto:)/i.test(url)) return label     // a link to a file or elsewhere: its text alone
        return `<a href="${url}" style="color:${c.primary}; text-decoration:none">${label || url}</a>`
    })
    s = s.replace(/(^|[\s(])(https?:\/\/[^\s<]+[^\s<.,;:!?)])/g,
                  (m, before, url) => `${before}<a href="${url}" style="color:${c.primary}; text-decoration:none">${url}</a>`)
    s = s.replace(/\*\*(\S(?:.*?\S)?)\*\*|__(\S(?:.*?\S)?)__/g, (m, a, b) => `<b>${a || b}</b>`)
    s = s.replace(/(^|[^\w*])\*(\S(?:.*?\S)?)\*(?!\w)|(^|[^\w_])_(\S(?:.*?\S)?)_(?!\w)/g,
                  (m, p1, a, p2, b) => `${p1 || p2 || ""}<i>${a || b}</i>`)
    s = s.replace(/~~(\S(?:.*?\S)?)~~/g, "<s>$1</s>")
    return s.replace(/\u0000(\d+)\u0000/g, (m, i) => `<code style="color:${c.accent}">${escape(codes[+i])}</code>`)
}

// The column a list marker's indent reaches, a tab as four
function columns(indent) {
    let n = 0
    for (const ch of indent) n = ch === "\t" ? n + 4 - n % 4 : n + 1
    return n
}

// A list item's opening, in the lists open (html()'s): at the column of a list's own items it is the next of them, past
// it it starts a list inside the item above, before it it closes lists until it is at one's level. The nesting is a
// little looser than CommonMark's (an item's text column): two spaces nest under "1." too, as many notes are written,
// and a kind that changes at a level starts a new list there, as CommonMark has it.
function openItem(lists, out, at, marker, space) {
    while (lists.length && at < lists[lists.length - 1].at) closeList(lists, out)
    const kind = /\d/.test(marker) ? "ol" : "ul"
    const top = lists[lists.length - 1]
    if (top && at < Math.min(top.at + 2, top.text)) {
        if (top.kind === kind) { out.push("</li>"); return }
        closeList(lists, out)                  // its new list goes where this one was
    }
    // An ordered list starts at its first number ("3." goes on from a list broken by a paragraph)
    const n = parseInt(marker)
    out.push(kind === "ol" && n !== 1 ? `<ol start="${n}">` : `<${kind}>`)
    lists.push({ kind, at, text: at + marker.length + space })
}

function closeList(lists, out) { out.push(`</li></${lists.pop().kind}>`) }

// The whole note; c is the look, for the colours
function html(md, c) {
    const lines = md.replace(/\r\n?/g, "\n").split("\n")
    const out = []
    let para = [], fence = null, quote = [], boxes = 0
    // The lists open, outermost first: each one's kind (ol, ul) and its marker's column. An item stays open (no </li>)
    // until the next one at its level, so a list nested in it is inside it and Qt numbers the outer one on after it
    // (with each item closed, every "1." under a nested list started again at 1).
    let lists = [], gap = false
    const sizes = [0, 22, 19, 17, 15, 14, 14]
    function flushPara() { if (para.length) out.push(`<p>${para.map(l => inline(l, c)).join("<br>")}</p>`); para = [] }
    function flushList() { while (lists.length) closeList(lists, out); gap = false }
    function flushQuote() {
        if (!quote.length) return
        out.push(`<table width="100%" cellpadding="0" cellspacing="0"><tr><td width="3" bgcolor="${c.line}"></td>`
                 + `<td style="padding-left:14px; color:${c.dim}">${quote.map(l => inline(l, c)).join("<br>")}</td></tr></table>`)
        quote = []
    }
    function flush() { flushPara(); flushList(); flushQuote() }

    for (const line of lines) {
        if (fence !== null) {
            if (/^\s*(```|~~~)/.test(line)) {
                out.push(`<pre style="color:${c.accent}">${escape(fence.join("\n"))}</pre>`)
                fence = null
            } else fence.push(line)
            continue
        }
        let m
        if (/^\s*(```|~~~)/.test(line)) { flush(); fence = []; continue }
        // A blank line between items keeps the list going ("1. a", "", "2. b" is one list): it ends at what isn't in it
        if (!line.trim()) { flushPara(); flushQuote(); gap = lists.length > 0; continue }
        if ((m = line.match(/^\s{0,3}(#{1,6})\s+(.*?)\s*#*\s*$/))) {
            flush()
            const n = m[1].length
            out.push(`<p style="font-size:${sizes[n]}px; font-weight:600; color:${c.title}">${inline(m[2], c)}</p>`)
            continue
        }
        if (/^\s{0,3}([-*_])(\s*\1){2,}\s*$/.test(line)) { flush(); out.push("<hr>"); continue }
        if ((m = line.match(/^\s*>\s?(.*)$/))) { flushPara(); flushList(); quote.push(m[1]); continue }
        if ((m = line.match(/^(\s*)([-*+]|\d+[.)])(\s+)(.*)$/))) {
            flushPara(); flushQuote()
            openItem(lists, out, columns(m[1]), m[2], m[3].length)
            gap = false
            let item = m[4]
            const box = item.match(/^\[([ xX])\]\s+(.*)$/)
            // A box is a link to itself ("box:K", the K-th as ListEdit.boxes counts them): a click ticks it (TaskBoxes.qml)
            const mark = box ? `<a href="box:${boxes++}" style="color:${c.primary}; text-decoration:none">${box[1] === " " ? "☐" : "☑"}</a> ` : ""
            if (box) item = box[2]
            out.push(`<li>${mark}${inline(item, c)}`)
            continue
        }
        // An indented line under an item goes on with it, after a blank line too (Qt's rich text has no bulletless
        // item). The last line out is that item's own, its </li> still to come.
        if (lists.length && (m = line.match(/^(\s+)\S/)) && columns(m[1]) >= 2) {
            out[out.length - 1] += `${gap ? "<br>" : ""}<br>${inline(line.trim(), c)}`
            gap = false
            continue
        }
        flushList(); flushQuote()
        para.push(line.trim())
    }
    if (fence !== null) out.push(`<pre style="color:${c.accent}">${escape(fence.join("\n"))}</pre>`)
    flush()
    return out.join("\n")
}

// The search's words marked in the note's HTML (html()'s): in its text only, never inside a tag or an entity, each
// match case aside, as notes.py finds them. words are lower case. The mark is the theme's primary, faded: its selection
// colour is too near the background to find a word by.
function mark(html, words, c) {
    if (!words.length) return html
    const pattern = new RegExp(words.map(w => escape(w).replace(/[.*+?^${}()|[\]\\]/g, "\\$&"))
                                    .sort((a, b) => b.length - a.length).join("|"), "gi")
    const p = c.primary
    const style = `background-color:${Qt.rgba(p.r, p.g, p.b, 0.4)}; color:${c.title}`
    // Tags and entities kept as they are; the text between them marked
    return html.split(/(<[^>]*>|&[#\w]+;)/).map((part, i) =>
        i % 2 ? part : part.replace(pattern, m => `<span style="${style}">${m}</span>`)).join("")
}
