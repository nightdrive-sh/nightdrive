.pragma library

// Files' small pure helpers: sizes in words, a row's glyph, the list's order and paths as file URLs and back.

// Bytes as GNOME and macOS give them (1000s, not 1024s): 812 B, 3 kB, 2.4 MB
function size(n) {
    if (n === undefined || n === null || n < 0) return ""
    if (n < 1000) return n + " B"
    const units = ["kB", "MB", "GB", "TB"]
    let v = n / 1000, i = 0
    while (v >= 1000 && i < units.length - 1) { v /= 1000; i++ }
    return (v < 10 ? v.toFixed(1) : Math.round(v)) + " " + units[i]
}

const IMAGE = ["png", "jpg", "jpeg", "gif", "webp", "bmp", "svg", "avif", "heic", "tif", "tiff", "ico"]
const KINDS = [
    [IMAGE, "file-image"],
    [["mp3", "flac", "ogg", "opus", "wav", "m4a", "aac"], "file-audio"],
    [["mp4", "mkv", "webm", "mov", "avi", "mpeg", "ogv"], "file-video"],
    [["zip", "tar", "gz", "tgz", "xz", "bz2", "zst", "7z", "rar"], "file-archive"],
    [["pdf", "md", "txt", "doc", "docx", "odt", "rtf", "epub"], "file-text"],
    [["xls", "xlsx", "ods", "csv"], "file-spreadsheet"],
    [["json"], "file-json"],
    [["py", "js", "ts", "qml", "sh", "lua", "c", "h", "cpp", "rs", "go", "php", "rb", "java", "css", "html", "xml", "yml", "yaml", "toml"], "file-code"]
]
function suffix(name) {
    const i = name.lastIndexOf(".")
    return i > 0 ? name.slice(i + 1).toLowerCase() : ""
}
function isImage(name) { return IMAGE.indexOf(suffix(name)) >= 0 }
function glyph(row) {
    if (row.dir) return "folder"
    const s = suffix(row.name)
    for (const k of KINDS) if (k[0].indexOf(s) >= 0) return k[1]
    return "file"
}

// Names in the order people count: "img2" before "img10", case left aside
function natural(a, b) {
    const re = /(\d+)|(\D+)/g
    const x = a.toLowerCase().match(re) || [], y = b.toLowerCase().match(re) || []
    for (let i = 0; i < Math.min(x.length, y.length); i++) {
        const p = x[i], q = y[i]
        if (p === q) continue
        const dp = /^\d/.test(p), dq = /^\d/.test(q)
        if (dp && dq) {
            const d = parseInt(p, 10) - parseInt(q, 10)
            if (d !== 0) return d
            continue
        }
        return p < q ? -1 : 1
    }
    return x.length - y.length || (a < b ? -1 : a > b ? 1 : 0)
}

// The list's order: folders first, then by the field (name, modified, size, type), the name breaking ties.
// Newest and largest come first, as one looks for those; reversed turns any of them round.
function order(rows, by, reversed) {
    const dir = reversed ? -1 : 1
    return rows.slice().sort((a, b) => {
        if (a.dir !== b.dir) return a.dir ? -1 : 1
        let d = 0
        if (by === "modified") d = b.modified - a.modified
        else if (by === "size") d = a.dir ? 0 : b.size - a.size
        else if (by === "type") d = natural(suffix(a.name), suffix(b.name))
        return dir * (d || natural(a.name, b.name))
    })
}

// A path as a file URL, each part escaped ("#" and "?" are a file name's too), and back
function url(path) { return "file://" + path.split("/").map(encodeURIComponent).join("/") }
function path(u) {
    const s = String(u)
    if (!s.startsWith("file://")) return ""
    let p = s.slice(7)
    if (!p.startsWith("/")) p = p.slice(p.indexOf("/"))     // file://host/path
    try { return decodeURIComponent(p) } catch (e) { return "" }
}
function parent(p) {
    if (p === "/") return "/"
    const i = p.lastIndexOf("/")
    return i <= 0 ? "/" : p.slice(0, i)
}
function base(p) { return p === "/" ? "/" : p.slice(p.lastIndexOf("/") + 1) }
function join(dir, name) { return dir === "/" ? "/" + name : dir + "/" + name }
