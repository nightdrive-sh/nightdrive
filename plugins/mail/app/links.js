.pragma library

// A plain-text message as rich text for the read view: web links clickable, quoted lines quiet (#2224).
// A bare URL stops where the sentence goes on: "(see https://a.b/c)." links https://a.b/c, not "c).", while a
// Wikipedia address's own parentheses (…/Heat_(1995_film)) stay in it. A Markdown link [text](url), as Claude and
// GitHub's mails write them, shows its text as the link.
// Tested by links_test.py (runs this file in Quickshell).

// One pattern for both, in one literal (Qt's engine doubles the escapes of a RegExp's .source, so they can't be
// joined from two): a Markdown link, its text in 1 and its URL in 2, which may hold balanced parentheses one level
// deep; or a bare URL, up to a space or a character that can't be in one unescaped.
const LINK = /\[([^\[\]\n]+)\]\((https?:\/\/[^\s()<>"]*(?:\([^\s()<>"]*\)[^\s()<>"]*)*)\)|https?:\/\/[^\s<>"]+/g

function esc(s) {
    return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;")
}

function count(s, ch) { return s.split(ch).length - 1 }

// The URL without what follows it in the sentence: a full stop, comma and the like at the end, and a closing
// parenthesis that has no opening one in the URL (the URL was written in parentheses). Repeated, as ")." and ".)"
// both end sentences.
function trim(url) {
    for (;;) {
        if (/[.,;:!?'*]$/.test(url)) url = url.slice(0, -1)
        else if (url.endsWith(")") && count(url, ")") > count(url, "(")) url = url.slice(0, -1)
        else return url
    }
}

function anchor(href, text, accent) {
    return '<a href="' + esc(href) + '" style="color:' + accent + '">' + esc(text) + '</a>'
}

// One line of text with its links as <a>, the rest escaped
function line(l, accent) {
    let out = "", at = 0, m
    LINK.lastIndex = 0
    while ((m = LINK.exec(l)) !== null) {
        out += esc(l.slice(at, m.index))
        if (m[2] !== undefined) {
            out += anchor(m[2], m[1], accent)
            at = m.index + m[0].length
        } else {
            const url = trim(m[0])
            // "https://." alone is no address: leave it as text
            if (url.length > url.indexOf("//") + 2) out += anchor(url, url, accent)
            else out += esc(url)
            at = m.index + url.length
            LINK.lastIndex = at
        }
    }
    return out + esc(l.slice(at))
}

// The whole body: lines joined with <br>, a quoted line (> …) in the faint colour
function rich(t, accent, faint) {
    return t.replace(/\r/g, "").split("\n").map(l => {
        const h = line(l, accent)
        return /^\s*>/.test(l) ? '<span style="color:' + faint + '">' + h + '</span>' : h
    }).join("<br>")
}
