.pragma library

// A plain-text message as rich text for the read view: web links clickable, quoted lines quiet (#2224).
// A bare URL stops where the sentence goes on: "(see https://a.b/c)." links https://a.b/c, not "c).", while a
// Wikipedia address's own parentheses (…/Heat_(1995_film)) stay in it. A Markdown link [text](url), as Claude and
// GitHub's mails write them, shows its text as the link. An address alone in square brackets, as newsletters' text made
// from HTML writes a link ("Docs: Variants → [https://…]"), shows as the link without its brackets (#3321).
// Outlook writes a link as "words<https://…>" and a picture as its address in brackets, so a shared file reads
// "[https://…/xlsx.png]Report.xlsx<https://…sharepoint…>": the picture goes, and the words show as the link (#3626).
// Tested by links_test.py (runs this file in Quickshell).

// One pattern for all, in one literal (Qt's engine doubles the escapes of a RegExp's .source, so they can't be
// joined from parts): a Markdown link, its text in 1 and its URL in 2, which may hold balanced parentheses one level
// deep; a picture's address alone in brackets, in 3; Outlook's "words<URL>", the words in 4 (none may be "<URL>" alone;
// no brackets or zero-width space in them, so they start after a picture) and the URL in 5; an address alone in
// brackets, in 6 (after the Markdown link, so [https://a](https://b) stays one); or a bare URL, up to a space or a
// character that can't be in one unescaped.
const LINK = /\[([^\[\]\n]+)\]\((https?:\/\/[^\s()<>"]*(?:\([^\s()<>"]*\)[^\s()<>"]*)*)\)|\[(https?:\/\/[^\s\[\]<>"]+\.(?:png|jpe?g|gif|svg|webp)(?:\?[^\s\[\]<>"]*)?)\]|((?:(?!https?:\/\/)[^<>|\[\]\n\u200b])*)<(https?:\/\/[^\s<>"]+)>|\[(https?:\/\/[^\s\[\]<>"]+)\]|https?:\/\/[^\s<>"]+/gi

// The words of "words<URL>" that are the link: those after the sentence or clause before them ("Hi, the file is
// here<…>" links "the file is here"), as Outlook gives no mark where the link's own words begin.
const LEAD = /^(.*(?:[.!?:;,]\s|\s-\s|\s–\s))/

function esc(s) {
    return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;")
}

function count(s, ch) { return s.split(ch).length - 1 }

// The URL without what follows it in the sentence: a full stop, comma and the like at the end, and a closing
// parenthesis or bracket that has no opening one in the URL (the URL was written in them: "[see https://a.b]").
// Repeated, as ")." and ".)" both end sentences.
function trim(url) {
    for (;;) {
        if (/[.,;:!?'*]$/.test(url)) url = url.slice(0, -1)
        else if (url.endsWith(")") && count(url, ")") > count(url, "(")) url = url.slice(0, -1)
        else if (url.endsWith("]") && count(url, "]") > count(url, "[")) url = url.slice(0, -1)
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
        } else if (m[3] !== undefined) {
            // A picture Outlook left as its address (a file type's icon, a logo): nothing to read or open
            at = m.index + m[0].length
        } else if (m[5] !== undefined) {
            // "Report.xlsx<https://…>": the words are the link, without the sentence before them. Outlook writes no
            // space before "<": with one ("See <https://…>"), or no words, the address is the link, without its brackets.
            const lead = /\s$/.test(m[4]) ? m[4] : (m[4].match(LEAD) || ["", ""])[1]
            const rest = m[4].slice(lead.length)
            const words = rest.trim()
            out += esc(lead + rest.match(/^\s*/)[0])     // not trimStart(): Qt's engine has none
            out += anchor(m[5], words || m[5], accent)
            at = m.index + m[0].length
        } else if (m[6] !== undefined) {
            // [https://…]: the brackets only marked the address, so they go. Its own trailing "." stays in it: the
            // brackets already say where it ends.
            out += anchor(m[6], m[6], accent)
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
