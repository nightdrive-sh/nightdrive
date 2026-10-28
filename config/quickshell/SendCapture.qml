import QtQuick
import Quickshell
import Quickshell.Io

// What hypr/scripts/send-capture gathered from the window when a Send key was pressed, for a level that sends it
// somewhere (SendClaudeLevels.qml: a Claude Code session). Nothing here knows the target: it reads the capture, says
// what there is to send and which goes by default, and shows it; the target's level adds where it goes.
// What goes by default: the files selected in a file manager, else text selected in the last minute in that window
// (PrimaryWatch.qml), else the clipboard's picture, else its text. Never on its own: a selection older than that, a
// screenshot, or clipboard text that looks like a password or a code (send-capture marks it), which stays hidden here
// even when chosen; a password manager's copy isn't read at all.
// A source's kind is what a target gets told: files | selection | clipboard | image | screenshot, the file in dir
// being files, primary.txt, clipboard.txt, clipboard.png, window.png.
Item {
    id: c

    readonly property string dir: (Quickshell.env("XDG_RUNTIME_DIR") || "/run/user/" + Quickshell.env("UID")) + "/nightdrive/send"
    readonly property int excerptLines: 4     // lines of text shown in the preview
    readonly property int excerptChars: 140   // each cut at this length
    readonly property int fileNames: 4        // file names shown, then "and N more"

    property var meta: ({})                   // send-capture's meta.json
    property var sources: []                  // what there is to send: ids from info, in their order
    property string source: ""                // the one that goes; "" = nothing
    property var files: []
    property string primaryText: ""
    property string clipText: ""
    readonly property string kind: source !== "" ? info[source].kind : ""

    // Each source: its row's name and glyph, and its kind
    readonly property var info: ({
        files: { name: "The selected files", glyph: "files", kind: "files" },
        selection: { name: "The selected text", glyph: "text-cursor", kind: "selection" },
        oldselection: { name: "Text selected earlier", glyph: "text-cursor", kind: "selection" },
        image: { name: "The picture on the clipboard", glyph: "image", kind: "image" },
        clipboard: { name: "The text on the clipboard", glyph: "clipboard", kind: "clipboard" },
        secret: { name: "The text on the clipboard (hidden)", glyph: "key-round", kind: "clipboard" },
        screenshot: { name: "A screenshot of the window", glyph: "app-window", kind: "screenshot" } })

    FileView { id: metaFile; blockLoading: true; printErrors: false }
    FileView { id: textFile; blockLoading: true; printErrors: false }
    function read(name) { textFile.path = ""; textFile.path = dir + "/" + name; return textFile.text() }

    // Read the capture again (the level's entered)
    function load() {
        metaFile.path = ""; metaFile.path = dir + "/meta.json"
        try { meta = JSON.parse(metaFile.text()) } catch (e) { meta = {}; sources = []; source = ""; return }
        files = meta.files > 0 ? read("files").split("\n").filter(f => f !== "") : []
        primaryText = meta.primary > 0 ? read("primary.txt") : ""
        clipText = meta.clip === "text" ? read("clipboard.txt") : ""
        const fresh = primaryText.trim() !== "" && PrimaryWatch.fresh(meta.addr)
        sources = [files.length ? "files" : "", fresh ? "selection" : "", meta.clip === "image" ? "image" : "",
                   meta.clip === "text" && clipText.trim() !== "" ? "clipboard" : "",
                   !fresh && primaryText.trim() !== "" ? "oldselection" : "",
                   meta.clip === "secret" ? "secret" : "", meta.shot ? "screenshot" : ""].filter(x => x !== "")
        source = sources.find(x => x !== "oldselection" && x !== "secret" && x !== "screenshot") || ""
    }

    function home(p) { const h = Quickshell.env("HOME"); return p.startsWith(h + "/") ? "~" + p.slice(h.length) : p }
    function folderOf(f) { return f.slice(0, f.lastIndexOf("/")) || "/" }
    function plural(n, one, many) { return n + " " + (n === 1 ? one : many) }
    // The text's first lines in a quote (the launcher's darker box; a code's indent kept), and how many more there are
    function excerpt(text) {
        const lines = text.split("\n").map(l => l.replace(/\t/g, "    ").replace(/\s+$/, "")).filter(l => l !== "")
        const out = [{ kind: "quote", name: lines.slice(0, excerptLines).map(l => l.length > excerptChars ? l.slice(0, excerptChars) + "…" : l).join("\n") }]
        if (lines.length > excerptLines) out.push({ kind: "note", name: "and " + plural(lines.length - excerptLines, "more line", "more lines") })
        return out
    }
    // The preview, as launcher rows: a header saying what goes, and a few lines of it in a quote. how: the target's own line
    // after it (how it gets the files: as paths, as attachments), for the kind it's about
    function preview(how) {
        const app = meta.title || meta.class || "the window"
        const tail = how && how[kind] ? [{ kind: "note", name: how[kind] }] : []
        if (source === "files") {
            // Files in one folder by their names under it, else by their paths
            const folders = files.map(f => folderOf(f))
            const one = folders.every(f => f === folders[0])
            const shown = [{ kind: "quote", name: files.slice(0, fileNames).map(f => one ? f.slice(f.lastIndexOf("/") + 1) : home(f)).join("\n") }]
            if (files.length > fileNames) shown.push({ kind: "note", name: "and " + (files.length - fileNames) + " more" })
            return [{ kind: "header", name: plural(files.length, "file", "files") + (one ? " in " + home(folders[0]) : "") }]
                .concat(shown, tail)
        }
        if (source === "selection" || source === "oldselection")
            return [{ kind: "header", name: "Selected text · " + plural(primaryText.length, "character", "characters") }]
                .concat(excerpt(primaryText), [{ kind: "note", name: "From " + app }], tail)
        if (source === "clipboard")
            return [{ kind: "header", name: "Clipboard text · " + plural(clipText.length, "character", "characters") }].concat(excerpt(clipText), tail)
        if (source === "secret")
            return [{ kind: "header", name: "Clipboard text" }, { kind: "quote", name: "••••••••" },
                    { kind: "note", name: "Hidden: it looks like a password or a code" }]
        if (source === "image") return [{ kind: "header", name: "The picture on the clipboard" }].concat(tail)
        if (source === "screenshot") return [{ kind: "header", name: "Screenshot of the window" }, { kind: "note", name: app }].concat(tail)
        return [{ kind: "header", name: "Nothing to send" },
                { kind: "note", name: "Select text or files, or copy a picture, then press the key again. Or send one below" }]
    }
    // The other sources, as rows (kind "sendsrc"): Enter on one is pick(row.value)
    function otherRows() {
        return sources.filter(x => x !== source).map(x => ({ kind: "sendsrc", value: x, name: info[x].name, glyph: info[x].glyph }))
    }
    function pick(id) { if (sources.indexOf(id) >= 0) source = id }
}
