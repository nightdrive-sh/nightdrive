import QtQuick
import Quickshell
import qs.kit

// The launcher's Settings › Hub: Nightdrive Hub, which carries Tasks between the person's computers (#3391, #3397;
// docs/hub.md, config/hub). What a person wants to know here: which Hub, whether the sync works (when it last went
// through, what the last try met), what each app's last sync did, and a way to sync now. Joining and leaving stay on
// the command line (`nightdrive hub join URL`): a Hub's address comes from setting one up, in a terminal anyway.
// Launcher.qml asks it like its other Levels files; its state (`nightdrive hub status --json`) is read when the
// launcher opens (the Settings row's summary) and every few seconds while the page is open. Modelled on CompanionLevels.
Item {
    id: s
    property var launcher: null

    readonly property var levels: ["hub"]
    readonly property var titles: ({ hub: "Settings › Hub" })
    readonly property var parents: ({ hub: "settings" })
    readonly property string level: launcher ? launcher.level : ""
    readonly property bool shown: launcher !== null && launcher.open && levels.indexOf(level) >= 0
    readonly property string copied: launcher ? launcher.rowCopy.copied : ""
    readonly property string bin: Quickshell.env("HOME") + "/.local/bin/nightdrive"

    // nightdrive hub status --json: { joined, url, state: ok|offline|error, error, last_ok, last_try, lines: {app: text} }
    property var st: ({})
    property bool syncing: false
    property string message: ""     // what Sync now said when it didn't go through
    property date now: new Date()   // for "3 min ago", moved on by the timer

    readonly property bool joined: st.joined === true
    // The Settings row's summary: the state at a glance, nothing while not joined
    readonly property string summary: !joined ? "" : syncing ? "syncing…" : st.state === "error" ? "failed"
                                      : st.state === "offline" ? "out of reach" : st.last_ok ? ago(st.last_ok) : ""

    function row(r) { return { item: r, text: r.kind === "header" || r.kind === "hint" || r.kind === "note" ? "" : r.name, extra: r.extra || "" } }
    function sel() { if (launcher) launcher.keepSelection() }

    // "2026-11-23T18:38:06+0200" (cli.now) as a Date: JavaScript wants the offset's colon
    function parse(t) { return new Date(String(t).replace(/([+-]\d\d)(\d\d)$/, "$1:$2")) }
    function ago(t) {
        const d = parse(t)
        if (isNaN(d)) return ""
        const min = Math.floor((now - d) / 60000)
        if (min < 1) return "just now"
        if (min < 60) return min + " min ago"
        const sameDay = d.toDateString() === now.toDateString()
        return (sameDay ? "today" : Regional.format(d, "day")) + " " + Regional.format(d, "time")
    }

    function footer(level, query) {
        const cur = launcher.results[launcher.selIndex] || {}
        if (cur.kind === "hubsync") return syncing ? "" : "Enter: sync now"
        if (cur.kind === "stat" && cur.copy !== undefined) return "Enter: copy"
        return ""
    }
    function opened() { statusProc.running = true }
    function entered(level) { if (level === "hub") { message = ""; now = new Date(); statusProc.running = true } }
    function shiftActivate(item) {}

    function items(level, q) {
        if (level === "hub") return { all: rows().map(row) }
        return []
    }

    function activate(it) {
        if (it.kind !== "hubsync") return false
        if (!syncing) {
            sel()
            message = ""
            syncing = true
            syncProc.running = true
        }
        return true
    }

    function rows() {
        if (!joined) return [
            { kind: "note", name: "Not joined to a Hub. Tasks stays on this computer only." },
            { kind: "stat", name: "In a terminal", glyph: "terminal", copy: "nightdrive hub join URL",
              summary: copied === "nightdrive hub join URL" ? "copied" : "nightdrive hub join URL" },
            { kind: "note", name: "The Hub carries your apps' data between your computers (docs: Hub)" }
        ]
        // What the last try met, and what each app's sync did, go in a row's second line (`sub`), which wraps on a
        // narrow card where a name or a hint would be cut
        const trouble = st.state === "offline" ? "Out of reach: the changes wait here and go with the next sync"
                      : st.state === "error" ? "The last try failed: " + (st.error || "unknown") : ""
        const r = [
            // The address on its own line, which wraps: a tailnet name with its port is cut beside the name on a
            // small screen. Enter copies it.
            { kind: "stat", name: "Hub", glyph: "server", copy: st.url, sub: st.url, summary: copied === st.url ? "copied" : "" },
            Object.assign({ kind: "stat", name: "Last sync", summary: st.last_ok ? ago(st.last_ok) : "never",
                            glyph: st.state === "error" ? "circle-alert" : st.state === "offline" ? "cloud-off" : "circle-check" },
                          trouble !== "" ? { sub: trouble } : {}),
            Object.assign({ kind: "hubsync", name: "Sync now", glyph: "refresh-cw", summary: syncing ? "syncing…" : "" },
                          message !== "" ? { sub: message } : {})
        ]
        const lines = st.lines || {}
        const apps = Object.keys(lines)
        if (apps.length) {
            r.push({ kind: "header", name: "Apps" })
            apps.forEach(a => r.push({ kind: "stat", name: a.charAt(0).toUpperCase() + a.slice(1), glyph: a === "tasks" ? "list-checks" : "folder-sync",
                                       sub: lines[a] }))
        }
        r.push({ kind: "note", name: "Syncs every few minutes. Leave: nightdrive hub leave" })
        return r
    }

    Timer { interval: 5000; repeat: true; running: s.shown; onTriggered: { s.now = new Date(); statusProc.running = true } }
    Sh {
        id: statusProc
        command: [s.bin, "hub", "status", "--json"]
        onResult: text => {
            let j
            try { j = JSON.parse(text) } catch (e) { j = {} }
            if (JSON.stringify(j) === JSON.stringify(s.st)) return
            s.sel()
            s.st = j
        }
    }
    Sh {
        id: syncProc
        script: "'" + s.bin + "' hub sync --json"
        onResult: text => {
            s.sel()
            s.syncing = false
            let j
            try { j = JSON.parse(text) } catch (e) { j = null }
            // Offline isn't a failure (the status says it); anything the command said on its own is
            if (!j) s.message = text.trim().split("\n").pop() || "The sync didn't run"
            s.now = new Date()
            statusProc.running = true
        }
    }
}
