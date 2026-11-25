.pragma library

// Sizes, counts and times as Disk Usage writes them: decimal units as Files (and the disk's maker) count them, three
// figures at most ("182 GB", "4.6 GB", "812 kB")
function bytes(n) {
    const units = ["B", "kB", "MB", "GB", "TB", "PB"]
    let i = 0
    n = Math.max(0, n || 0)
    while (n >= 1000 && i < units.length - 1) { n /= 1000; i++ }
    return (i === 0 || n >= 100 ? Math.round(n) : n.toFixed(1)) + " " + units[i]
}

// 1234567 → "1,234,567"
function count(n) {
    return String(Math.round(n || 0)).replace(/\B(?=(\d{3})+(?!\d))/g, ",")
}

function plural(n, one, many) {
    return count(n) + " " + (n === 1 ? one : many)
}

// A share as a percentage: "38 %", "0.4 %", "< 0.1 %"
function percent(part, whole) {
    if (!whole) return ""
    const p = 100 * part / whole
    return p >= 10 ? Math.round(p) + " %" : p >= 0.1 ? p.toFixed(1) + " %" : part > 0 ? "< 0.1 %" : "0 %"
}

// Seconds since the epoch → "just now", "5 min ago", "3 h ago", "2 days ago"
function ago(t) {
    const s = Date.now() / 1000 - t
    if (s < 60) return "just now"
    if (s < 3600) return Math.floor(s / 60) + " min ago"
    if (s < 86400) return Math.floor(s / 3600) + " h ago"
    const d = Math.floor(s / 86400)
    return d === 1 ? "yesterday" : d + " days ago"
}

// A path for a file: URL, each part encoded (a ' too, as it ends a GVariant string in ShowItems' argument)
function fileUrl(path) {
    return "file://" + path.split("/").map(p => encodeURIComponent(p).replace(/'/g, "%27")).join("/")
}
