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

// The whole note; c is the look, for the colours
function html(md, c) {
    const lines = md.replace(/\r\n?/g, "\n").split("\n")
    const out = []
    let para = [], list = null, fence = null, quote = []
    const sizes = [0, 22, 19, 17, 15, 14, 14]
    function flushPara() { if (para.length) out.push(`<p>${para.map(l => inline(l, c)).join("<br>")}</p>`); para = [] }
    function flushList() { if (list) out.push(`</${list}>`); list = null }
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
        if (!line.trim()) { flush(); continue }
        if ((m = line.match(/^\s{0,3}(#{1,6})\s+(.*?)\s*#*\s*$/))) {
            flush()
            const n = m[1].length
            out.push(`<p style="font-size:${sizes[n]}px; font-weight:600; color:${c.title}">${inline(m[2], c)}</p>`)
            continue
        }
        if (/^\s{0,3}([-*_])(\s*\1){2,}\s*$/.test(line)) { flush(); out.push("<hr>"); continue }
        if ((m = line.match(/^\s*>\s?(.*)$/))) { flushPara(); flushList(); quote.push(m[1]); continue }
        if ((m = line.match(/^(\s*)([-*+]|\d+[.)])\s+(.*)$/))) {
            flushPara(); flushQuote()
            const kind = /\d/.test(m[2]) ? "ol" : "ul"
            if (list !== kind) { flushList(); out.push(`<${kind}>`); list = kind }
            let item = m[3]
            const box = item.match(/^\[([ xX])\]\s+(.*)$/)
            if (box) item = (box[1] === " " ? "☐ " : "☑ ") + box[2]
            out.push(`<li>${inline(item, c)}</li>`)
            continue
        }
        // An indented line under an item goes on with it (Qt's rich text has no bulletless item)
        if (list && /^\s{2,}\S/.test(line)) {
            out[out.length - 1] = out[out.length - 1].replace(/<\/li>$/, `<br>${inline(line.trim(), c)}</li>`)
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
