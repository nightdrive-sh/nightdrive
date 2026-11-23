.pragma library

// What Ask Claude's result cards (AskClaudeResults.qml, #2245) say about a card of results.json (config/mcp/results.py):
// where it came from, its licence's tone, its size and length, and which turn it belongs to. Kept out of the cards so
// askclaude_cards_test.py can run it.

// Licences that ask nothing of the user: the chip says so in the "ok" colour. Others (CC BY, a site's own licence) are
// usable on their terms, and "unknown" is the warning: nobody said it may be used
var FREE = /^(cc0|cc-?0|public domain|pd|cc pdm|unlicense)\b/i

// The page's host without "www.", as the card shows it ("freesound.org"); "" for what isn't an http(s) address
function domain(url) {
    var m = /^https?:\/\/(?:[^@\/?#]*@)?([^\/?#:]+)/i.exec(String(url || ""))
    return m ? m[1].toLowerCase().replace(/^www\./, "") : ""
}

// "free" | "terms" | "unknown"
function licenceTone(licence) {
    var l = String(licence || "").trim()
    if (l === "" || l.toLowerCase() === "unknown") return "unknown"
    return FREE.test(l) ? "free" : "terms"
}

// 52113 → "51 KB", as Files says it (1024s, one decimal under 10)
function size(bytes) {
    if (bytes === null || bytes === undefined || bytes === "") return ""   // Number() would make them 0
    var n = Number(bytes)
    if (!(n >= 0)) return ""
    var units = ["B", "KB", "MB", "GB"]
    var i = 0
    while (n >= 1024 && i < units.length - 1) { n /= 1024; i++ }
    return (i === 0 || n >= 10 ? Math.round(n) : Math.round(n * 10) / 10) + " " + units[i]
}

// 75.4 → "1:15"; an hour or more "1:02:03"; "" while unknown
function duration(seconds) {
    if (seconds === null || seconds === undefined || seconds === "") return ""
    var s = Math.round(Number(seconds))
    if (!(s >= 0) || !isFinite(s)) return ""
    var h = Math.floor(s / 3600), m = Math.floor(s % 3600 / 60), r = s % 60
    var mm = h > 0 && m < 10 ? "0" + m : String(m)
    return (h > 0 ? h + ":" : "") + mm + ":" + (r < 10 ? "0" : "") + r
}

// The file type's short name for a file card: "PDF", "ZIP", "OGG"
function kind(card) {
    var mime = String(card.mime || "")
    var sub = mime.split("/")[1] || ""
    var names = { "pdf": "PDF", "zip": "ZIP", "mpeg": "MP3", "x-wav": "WAV", "wav": "WAV", "jpeg": "JPEG" }
    if (names[sub]) return names[sub]
    var ext = /\.([a-z0-9]{1,5})$/i.exec(String(card.file || ""))
    return ext ? ext[1].toUpperCase() : sub.toUpperCase()
}

// The cards added during a turn: from its start (ms) up to its end (ms; Infinity while it runs). results.py dates a
// card to the second, so the window starts at its second
function during(cards, from, to) {
    var start = Math.floor(from / 1000) * 1000
    return (cards || []).filter(function (c) {
        var t = Date.parse(c.added)
        return t >= start && t <= to
    })
}
