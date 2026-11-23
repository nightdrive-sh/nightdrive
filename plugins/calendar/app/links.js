.pragma library

// An event's notes and place as rich text for EventPanel (#3444): web links clickable, written short.
// Built on Mail's links.js (#2224, #3321), with what invitations write on top of it:
// - Outlook and Teams write a link as "Join the meeting<https://…>": the words before it show as the link, and the
//   address goes. An address alone in angle brackets, "<https://…>", shows without them, and so does "[https://…]".
// - A Markdown link [text](url) shows its text as the link.
// - A bare address stops where the sentence goes on ("(see https://a.b/c)." links https://a.b/c), and one longer than
//   SHORT shows cut, without its https:// ("teams.microsoft.com/l/meetup-join/19%3ameeting_…"): a Teams address is
//   ~300 characters of one word that would fill the card. The link itself is whole.
// - A line of underscores or dashes (Teams' frame around its part) shows as a short faint rule.
// Mail keeps its own copy: its read view shows addresses whole, and an invitation's forms are rarer there.
// Tested by links_test.py (runs this file in Quickshell).

const SHORT = 48

// In one literal (Qt's engine doubles the escapes of a RegExp's .source, so it can't be joined from parts):
// 1, 2: a Markdown link's text and URL (balanced parentheses one level deep in it);
// 3, 4: Outlook's "words<URL>": the words (no < > | or address in them) and the URL; 3 may be empty, "<URL>" alone;
// 5: an address alone in square brackets;
// or a bare URL, up to a space or a character that can't be in one unescaped.
const LINK = /\[([^\[\]\n]+)\]\((https?:\/\/[^\s()<>"]*(?:\([^\s()<>"]*\)[^\s()<>"]*)*)\)|((?:(?!https?:\/\/)[^<>|\n])*)<(https?:\/\/[^\s<>"]+)>|\[(https?:\/\/[^\s\[\]<>"]+)\]|https?:\/\/[^\s<>"]+/g

function esc(s) {
    return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;")
}

function count(s, ch) { return s.split(ch).length - 1 }

// The URL without what follows it in the sentence: a full stop, comma and the like at the end, and a closing
// parenthesis or bracket that has no opening one in the URL. Repeated, as ")." and ".)" both end sentences.
function trim(url) {
    for (;;) {
        if (/[.,;:!?'*]$/.test(url)) url = url.slice(0, -1)
        else if (url.endsWith(")") && count(url, ")") > count(url, "(")) url = url.slice(0, -1)
        else if (url.endsWith("]") && count(url, "]") > count(url, "[")) url = url.slice(0, -1)
        else return url
    }
}

// An address as it is shown: without https://, cut at SHORT
function short(url) {
    const s = url.replace(/^https?:\/\//i, "")
    return s.length > SHORT ? s.slice(0, SHORT - 1) + "…" : s
}

function anchor(href, text, accent) {
    return '<a href="' + esc(href) + '" style="color:' + accent + '; text-decoration:none">' + esc(text) + '</a>'
}

// One line with its links as <a>, the rest escaped
function line(l, accent) {
    let out = "", at = 0, m
    LINK.lastIndex = 0
    while ((m = LINK.exec(l)) !== null) {
        out += esc(l.slice(at, m.index))
        if (m[2] !== undefined) {
            out += anchor(m[2], m[1], accent)
            at = m.index + m[0].length
        } else if (m[4] !== undefined) {
            // "Download Teams<https://…>": the words are the link. Spaces before them stay text; none: the address
            const words = m[3].trim()
            out += esc(m[3].match(/^\s*/)[0])    // not trimStart(): Qt's engine has none
            out += words ? anchor(m[4], words, accent) : anchor(m[4], short(m[4]), accent)
            at = m.index + m[0].length
        } else if (m[5] !== undefined) {
            out += anchor(m[5], short(m[5]), accent)
            at = m.index + m[0].length
        } else {
            const url = trim(m[0])
            // "https://." alone is no address: leave it as text
            if (url.length > url.indexOf("//") + 2) out += anchor(url, short(url), accent)
            else out += esc(url)
            at = m.index + url.length
            LINK.lastIndex = at
        }
    }
    return out + esc(l.slice(at))
}

// The whole text: lines joined with <br>, a frame line (_____ or -----) a short rule in the faint colour
function rich(t, accent, faint) {
    return (t || "").replace(/\r/g, "").split("\n").map(l => {
        if (/^\s*([_\-=─])\1{9,}\s*$/.test(l)) return '<span style="color:' + faint + '">' + "─".repeat(12) + '</span>'
        return line(l, accent)
    }).join("<br>")
}
