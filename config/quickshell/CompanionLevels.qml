import QtQuick
import Quickshell

// The launcher's Settings › Companion: Companion on or off (bin/companion on|off, as `nightdrive companion`), and the
// address to open on the iPad, copied with Enter. Companion is the iPad's web app over Tailscale (docs/companion.md,
// config/companion). Launcher.qml asks it like its other Levels files (levels, titles, parents, items, activate,
// footer, entered); its state is read when the launcher opens (the Settings row's on) and every few seconds while the
// page is open. Modelled on TailscaleLevels.qml.
Item {
    id: s
    property var launcher: null

    readonly property var levels: ["companion"]
    readonly property var titles: ({ companion: "Settings › Companion" })
    readonly property var parents: ({ companion: "settings" })
    readonly property string level: launcher ? launcher.level : ""
    readonly property bool shown: launcher !== null && launcher.open && levels.indexOf(level) >= 0
    readonly property string copied: launcher ? launcher.rowCopy.copied : ""   // a row just copied says so (RowCopy)
    readonly property string bin: Quickshell.env("HOME") + "/.local/bin/companion"

    // bin/companion status --json: { state: on|off, running, url, tailscale }
    property string state: ""
    property bool running: false
    property string url: ""
    property bool tailscale: false
    property string message: ""     // what on or off said when it failed

    function row(r) { return { item: r, text: r.kind === "header" || r.kind === "hint" || r.kind === "note" ? "" : r.name, extra: r.extra || "" } }
    function sel() { if (launcher) launcher.keepSelection() }   // a refresh rebuilds the rows: keep the selected one

    function footer(level, query) {
        const cur = launcher.results[launcher.selIndex] || {}
        if (cur.kind === "systoggle") return "Enter: on/off"
        if (cur.kind === "compurl") return "Enter: copy the address"
        return ""
    }
    function opened() { statusProc.running = true }
    function entered(level) { if (level === "companion") { message = ""; statusProc.running = true } }
    function shiftActivate(item) {}

    function items(level, q) {
        if (level === "companion") return { all: rows().map(row) }
        return []
    }

    function activate(it) {
        if (it.kind === "systoggle" && it.key === "companion") {
            sel()
            message = ""
            toggle.script = "'" + bin + "' " + (state === "on" ? "off" : "on")
            toggle.running = true
            return true
        }
        if (it.kind === "compurl") { launcher.rowCopy.copyText(it.copy); return true }
        return false
    }

    function rows() {
        const on = state === "on"
        const r = [{ kind: "systoggle", key: "companion", name: "Companion", glyph: "tablet-smartphone", switchOn: on }]
        if (message !== "") r.push({ kind: "hint", name: message })
        if (!tailscale) r.push({ kind: "hint", name: "Needs Tailscale, logged in: Settings › Tailscale" })
        if (on && url !== "") {
            r.push({ kind: "header", name: "On the iPad" })
            r.push({ kind: "compurl", name: url, copy: url, glyph: "link", summary: copied === url ? "copied" : (running ? "" : "starting") })
        }
        // one line: off, what it is; on, what to do with the address
        r.push({ kind: "note", name: on ? "In Safari on the iPad, then Share › Add to Home Screen"
                                        : "Your Claude Code sessions and dictation on an iPad, over Tailscale" })
        return r
    }

    Timer { interval: 3000; repeat: true; running: s.shown; onTriggered: statusProc.running = true }
    Sh {
        id: statusProc
        command: [s.bin, "status", "--json"]
        onResult: text => {
            let j
            try { j = JSON.parse(text) } catch (e) { j = {} }
            const st = j.state || "", run = !!j.running, u = j.url || "", ts = !!j.tailscale
            if (st === s.state && run === s.running && u === s.url && ts === s.tailscale) return
            s.sel()
            s.state = st; s.running = run; s.url = u; s.tailscale = ts
        }
    }
    Sh {
        id: toggle
        onResult: text => {
            s.sel()
            if (toggle.exitCode !== 0) s.message = text.trim().split("\n").pop().replace(/^companion: /, "")
            statusProc.running = true
        }
    }
}
