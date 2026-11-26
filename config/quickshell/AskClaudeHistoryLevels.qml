import QtQuick
import Quickshell

// The launcher's Ask Claude history (Dashboard #2246): the earlier Ask Claude conversations, the newest first, and
// Enter on one brings it back into Ask Claude's toast as it was, its steps, answers and result cards too; what is
// written there then goes on with it. They come from `ask-claude list --json` (hypr/scripts/ask-claude.d/history.sh),
// which keeps a conversation for 7 days after its last turn, so the list stays short. Typing searches the requests.
// Its row is the root's, under Ask Claude's, while there is anything to list. Launcher.qml asks it like its other level
// files (levels, titles, parents, items, activate, footer, entered).
Item {
    id: h
    property var launcher: null
    property var hint: null       // AskClaudeHint: the row shows only with Claude Code installed, as Ask Claude's does
    readonly property var session: AskClaudeSession

    readonly property string script: Quickshell.env("HOME") + "/.config/hypr/scripts/ask-claude"
    property var convs: []        // [{ id, title, started, last, turns, status, results }], times in ms
    property bool loaded: false
    property string refused: ""   // the conversation Enter couldn't open while another one runs (footer says why)

    readonly property var levels: ["askhistory"]
    readonly property var titles: ({ askhistory: "Ask Claude › History" })
    readonly property var parents: ({})

    // The root's row, after Ask Claude's (LauncherMenus.qml): only when there is a conversation to go back to
    function rootRows() {
        if (!hint || !hint.installed || convs.length === 0) return []
        return [{ kind: "nav", name: "Ask Claude History", glyph: "history", target: "askhistory",
                  summary: convs.length + (convs.length === 1 ? " chat" : " chats"),
                  extra: "claude ai assistant earlier recent previous conversations chats requests answers" }]
    }

    function ago(ms) {
        const d = Math.max(0, (Date.now() - ms) / 1000)
        if (d < 60) return "now"
        if (d < 3600) return Math.floor(d / 60) + " min"
        if (d < 86400) return Math.floor(d / 3600) + " h"
        return Math.floor(d / 86400) + " d"
    }
    // What the row says under the request: how it ended when not well, then the follow-ups and the cards it found
    function sub(c) {
        const parts = []
        if (c.status === "error") parts.push("failed")
        else if (c.status === "timeout") parts.push("ran out of time")
        else if (c.status === "cancelled") parts.push("stopped")
        if (c.turns > 1) parts.push(c.turns + " requests")
        if (c.results > 0) parts.push(c.results + (c.results === 1 ? " result" : " results"))
        return parts.join(" · ")
    }
    function glyph(c) {
        if (c.status === "running") return "loader-circle"
        if (c.status === "done") return c.results > 0 ? "message-square-check" : "message-square-text"
        return "message-square-warning"
    }

    function opened() { refused = ""; listProc.running = true }
    function entered(level) { if (level === "askhistory") { refused = ""; listProc.running = true } }
    function shiftActivate(it) {}

    function items(level, q) {
        if (level !== "askhistory") return []
        const words = q.toLowerCase().split(/\s+/).filter(w => w)
        const rows = convs.filter(c => words.every(w => c.title.toLowerCase().indexOf(w) >= 0)).map(c => ({
            kind: "askhist", id: c.id, name: c.title || "(no text)", glyph: glyph(c), sub: sub(c) || undefined,
            summary: c.status === "running" ? "working…" : c.id === session.sessionId ? "open" : ago(c.last) }))
        if (rows.length) return rows
        if (!loaded) return launcher.hint("Reading the conversations…")
        return launcher.hint(words.length ? "No request with those words" : "No Ask Claude conversations in the last 7 days")
    }

    function footer(level, query) {
        if (level !== "askhistory") return ""
        const cur = launcher.results[launcher.selIndex] || {}
        if (cur.kind !== "askhist") return ""
        if (refused === cur.id) return "Claude is working on another request: open this when it's done"
        return cur.id === session.sessionId ? "Enter: open" : "Enter: open, and go on with it"
    }

    // Enter: the toast shows it (the launcher closes under it as for Ask Claude's own row, AskClaudeLevels.activate)
    function activate(it) {
        if (it.kind !== "askhist") return false
        if (!session.open(it.id)) { refused = it.id; return true }
        refused = ""
        session.showRequested("", false)
        return true
    }

    Sh {
        id: listProc
        command: [h.script, "list", "--json"]
        onResult: text => {
            let list = []
            try { list = JSON.parse(text) } catch (e) {}
            h.convs = Array.isArray(list) ? list.filter(c => c && typeof c.id === "string") : []
            h.loaded = true
        }
    }
    // A turn that ends, or a new conversation, changes the list: read again while the launcher shows it
    Connections {
        target: h.session
        function onAnswered() { if (h.launcher && h.launcher.open) listProc.running = true }
    }
}
