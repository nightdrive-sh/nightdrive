import QtQuick
import Quickshell

// The launcher's Ask Claude row (Dashboard #1893, #1895). The row is the root level's first, and while searching it
// comes after the hits when the search looks like a request (AskClaudeHint.shows), or as one found by its name. Enter on
// it asks what was typed, or with nothing typed opens Ask Claude's toast in the launcher's place (AskClaudeToast.qml),
// where the conversation is: the launcher closes, and the toast shows Claude's steps and answer as they come. The row
// says when Claude is working or has answered.
// The keys Hyprland takes (⌘Enter, which is the terminal here, ⌘⌥Enter, ⌘⌃Enter) come over IPC (askClaude in
// Launcher.qml) from hypr/scripts/ask-claude and terminal-or-claude, to submit() and terminal() here. Only with Claude
// Code installed.
Item {
    id: a
    property var launcher: null
    property var hint: null       // AskClaudeHint: whether Claude Code is installed, whether a search is a request
    readonly property var session: AskClaudeSession

    readonly property string scripts: Quickshell.env("HOME") + "/.config/hypr/scripts"
    // No level of its own: the conversation is in the toast
    readonly property var levels: []
    readonly property var titles: ({})
    readonly property var parents: ({})
    readonly property var row: ({ kind: "askclaude", name: "Ask Claude", glyph: "bot",
                                  extra: "claude ai assistant request question prompt chat",
                                  summary: session.busy ? "working…" : session.unseen ? "answered" : undefined })

    function opened() {}
    function entered(level) {}
    function items(level, q) { return [] }
    function footer(level, query) { return "" }

    // The root level's rows: first with nothing typed, the row after the hits for a search that looks like a request
    function rootRows() { return hint && hint.installed ? [row] : [] }
    function tailRows(query, hits) {
        if (!hint || hits.some(r => r.kind === "askclaude") || !hint.shows("root", query, hits)) return []
        return [Object.assign({ tail: true }, row)]
    }

    // Enter on the row: what was typed is asked at once, as ⌘Enter does; with nothing typed the toast opens to write in
    function activate(it) {
        if (it.kind !== "askclaude") return false
        if (!submit(launcher.query)) {
            launcher.open = false
            session.showRequested("", false)
        }
        return true
    }
    // The footer while the row is selected: Enter is the key then, not ⌘Enter (AskClaudeHint's)
    function rowFooter(query) {
        return query.trim() !== "" ? "Enter: ask Claude  ·  Cmd+Enter: in terminal" : "Enter: open"
    }

    // A request from the search (Enter on the row, ⌘Enter / ⌘⌥Enter over IPC): the launcher closes and the toast starts
    // a new conversation with it (unless one still runs: then the text waits in its field). True when it was taken
    // here, so the key's script doesn't open a terminal instead
    function submit(text) {
        if (text.trim() === "") return false
        launcher.open = false
        session.showRequested(text, true)
        return true
    }

    // ⌘⌃Enter: over the toast, its conversation goes on in Claude Code in a terminal, with its usual tools (stopped here
    // first: one session can't run in two places); from the search or without one, the text is a new session's prompt
    function terminal(text, goOn) {
        const q = text.trim()
        launcher.open = false
        if (goOn) session.hideRequested()
        if (!goOn || session.sessionId === "") {
            Quickshell.execDetached([scripts + "/terminal-or-claude"].concat(q !== "" ? ["--", q] : []))
            return
        }
        if (session.busy) session.stop()
        const home = Quickshell.env("HOME")
        Quickshell.execDetached([scripts + "/terminal", "--dir", home + "/Projects", "--", home + "/.local/bin/claude",
                                 "--resume", session.sessionId].concat(q !== "" ? [q] : []))
    }

    // An answer while the toast is closed: the row says so (the toast's small card does too, for a while)
    Connections {
        target: a.session
        function onAnswered() { if (!a.session.toastViewing) a.session.unseen = true }
    }
}
