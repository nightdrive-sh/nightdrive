import QtQuick
import Quickshell

// The launcher's Sessions (Dashboard #3120): Claude Code's sessions, the running ones first (Enter goes to the window),
// then the closed ones, the newest first (Enter opens a terminal in its folder and goes on with the conversation).
// Typing searches the names, folders and task numbers (#3120 or 3120). The running ones are Claude.qml's, live; the
// closed ones come from topbar/scripts/claude-history (`nightdrive sessions`), which reads Claude Code's transcripts and
// keeps what it found in a cache, so even hundreds list at once. Launcher.qml asks it like its other level files
// (levels, titles, parents, items, activate, footer, entered).
Item {
    id: s
    property var launcher: null

    readonly property string cmdPath: Quickshell.env("HOME") + "/.config/topbar/scripts/claude-history"
    readonly property int readMax: 1000   // closed sessions read: older ones are a search in `nightdrive sessions` away
    readonly property int shownMax: 60    // rows shown without a search: the list is built again on every key
    property var closed: []               // claude-history --no-running: [{ id, name, dir, account, accountDefault, last, task, prompt }]
    property bool loaded: false

    readonly property var levels: ["sessions"]
    readonly property var titles: ({ sessions: "Sessions" })
    readonly property var parents: ({})
    // The root's row (LauncherMenus.qml), with how many run
    readonly property var rootRow: ({ kind: "nav", name: "Sessions", glyph: "messages-square", target: "sessions",
                                      summary: Claude.sessions.length ? Claude.sessions.length + " running" : undefined,
                                      extra: "claude code conversation resume continue history chat agent" })

    function home(dir) { const h = Quickshell.env("HOME"); return dir.startsWith(h) ? "~" + dir.slice(h.length) : dir }
    function ago(sec) {
        const d = Math.max(0, Date.now() / 1000 - sec)
        if (d < 60) return "now"
        if (d < 3600) return Math.floor(d / 60) + " min"
        if (d < 86400) return Math.floor(d / 3600) + " h"
        if (d < 7 * 86400) return Math.floor(d / 86400) + " d"
        return Qt.formatDate(new Date(sec * 1000), "d.M.yyyy")
    }
    // Every word in its name, folder or task number, as claude-history's matches(): #312 finds #3120 too
    function matches(name, dir, task, words) {
        const hay = (name + " " + dir + (task ? " #" + task : "")).toLowerCase()
        return words.every(w => hay.indexOf(w.startsWith("#") ? w.slice(1) : w) >= 0)
    }
    // The running sessions' ids, by their transcript's name (claude-sessions): they're left out of the closed ones
    function runningIds() {
        const ids = {}
        for (const f of Claude.found) {
            const m = String(f.transcript || "").match(/([0-9a-f-]{36})\.jsonl$/)
            if (m) ids[m[1]] = true
        }
        return ids
    }

    function footer(level, query) {
        if (level !== "sessions") return ""
        const cur = launcher.results[launcher.selIndex] || {}
        if (cur.kind === "sessionlive") return "Enter: go to its window"
        if (cur.kind === "sessionold") return "Enter: continue in a terminal, in " + home(cur.dir)
        return ""
    }
    function opened() { listProc.running = true }
    function entered(level) { if (level === "sessions") listProc.running = true }
    function shiftActivate(it) {}

    function items(level, q) {
        if (level !== "sessions") return []
        const words = q.split(/\s+/).filter(w => w)
        const live = Claude.sessions.filter(r => matches(r.name || r.topic || "", r.dir, null, words)).map(r => ({
            kind: "sessionlive", address: r.address, name: r.name || r.topic || r.project, glyph: r.asking ? "message-circle-question" : "bot",
            sub: home(r.dir) + (r.accountDefault ? "" : " · " + r.account), summary: r.asking ? "asks you" : r.state === "working" ? "working" : "idle" }))
        const ids = runningIds()
        const old = closed.filter(c => !ids[c.id] && matches(c.name, c.dir, c.task, words))
        const shown = words.length ? old : old.slice(0, shownMax)
        const rows = []
        if (live.length) rows.push({ kind: "header", name: "Running" }, ...live)
        if (shown.length) rows.push({ kind: "header", name: "Closed" }, ...shown.map(c => ({
            kind: "sessionold", id: c.id, dir: c.dir, name: c.name || c.prompt || c.dir.split("/").pop() || "/",
            dimmed: !c.name, glyph: "history", sub: home(c.dir) + (c.accountDefault ? "" : " · " + c.account),
            summary: ago(c.last) })))
        if (rows.length) return rows
        if (!loaded) return launcher.hint("Reading the sessions…")
        return launcher.hint(words.length ? "No session with that name, folder or task number" : "No Claude Code sessions yet")
    }

    function activate(it) {
        if (it.kind === "sessionlive") {
            launcher.open = false
            Claude.focus({ address: it.address })
            return true
        }
        if (it.kind === "sessionold") {
            launcher.open = false
            Quickshell.execDetached([cmdPath, "resume", it.id])
            return true
        }
        return false
    }

    Sh {
        id: listProc
        command: [s.cmdPath, "--json", "--no-running", "--limit", String(s.readMax)]
        onResult: text => {
            try { s.closed = JSON.parse(text) } catch (e) { s.closed = [] }
            s.loaded = true
        }
    }
}
