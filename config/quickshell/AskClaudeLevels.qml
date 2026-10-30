import QtQuick
import Quickshell

// The launcher's Ask Claude row and level (Dashboard #1893, #1895). The row is the root level's first, and while
// searching it comes after the hits when the search looks like a request (AskClaudeHint.shows), or as one found by its
// name. Enter on it asks what was typed, or with nothing typed opens the level: AskClaudeField.qml stands in for the
// search field, and below it the conversation (AskClaudeThread.qml, kept in AskClaudeSession) shows Claude's steps and answer
// as they come; you can write back. Closing the launcher doesn't stop Claude: the row says it's working or answered.
// The keys Hyprland takes (⌘Enter, which is the terminal here, ⌘⌥Enter, ⌘⌃Enter) come over IPC (askClaude in Launcher.qml) from
// hypr/scripts/ask-claude and terminal-or-claude, to submit() and terminal() here. Only with Claude Code installed.
Item {
    id: a
    property var launcher: null
    property var hint: null       // AskClaudeHint: whether Claude Code is installed, whether a search is a request
    property var field: null      // AskClaudeField: the text written on the level
    readonly property var session: AskClaudeSession

    readonly property string scripts: Quickshell.env("HOME") + "/.config/hypr/scripts"
    readonly property var levels: ["askclaude"]
    readonly property var titles: ({ askclaude: "Ask Claude" })
    readonly property var parents: ({ askclaude: "root" })
    readonly property var row: ({ kind: "askclaude", name: "Ask Claude", glyph: "bot",
                                  extra: "claude ai assistant request question prompt chat",
                                  summary: session.busy ? "working…" : session.unseen ? "answered" : undefined })

    // The conversation is in view while the launcher shows the level (and hasn't stepped aside for a card)
    Binding { target: AskClaudeSession; property: "launcherViewing"; value: a.launcher.open && a.launcher.level === "askclaude" && !a.launcher.stepAside }
    // Back from a card or a password prompt: the keys go to the field again
    Connections {
        target: a.launcher
        function onStepAsideChanged() { if (!a.launcher.stepAside && a.launcher.level === "askclaude") a.field.edit.forceActiveFocus() }
    }

    function opened() {}
    function entered(level) { field.begin(""); session.unseen = false }
    function items(level, q) { return [] }   // the field and the conversation are the whole level
    function footer(level, query) {
        // Shift+Enter (a new line) isn't listed: it's what text fields do
        if (session.pendingCard) return ""   // the card in the conversation has its keys on its buttons
        if (session.busy) return "Ctrl+C: stop  ·  Cmd+Enter: terminal"
        if (session.entries.length) return "Enter: send  ·  Cmd+N: new chat  ·  Cmd+Enter: terminal"
        return "Enter: ask  ·  Cmd+Enter: terminal"
    }

    // The root level's rows: first with nothing typed, the row after the hits for a search that looks like a request
    function rootRows() { return hint && hint.installed ? [row] : [] }
    function tailRows(query, hits) {
        if (!hint || hits.some(r => r.kind === "askclaude") || !hint.shows("root", query, hits)) return []
        return [Object.assign({ tail: true }, row)]
    }

    // Enter on the row: what was typed is asked at once, as ⌘Enter does; with nothing typed it opens the field
    function activate(it) {
        if (it.kind !== "askclaude") return false
        if (launcher.query.trim() !== "") submit(launcher.query)
        else launcher.go("askclaude")
        return true
    }
    // The footer while the row is selected: Enter is the key then, not ⌘Enter (AskClaudeHint's)
    function rowFooter(query) {
        return query.trim() !== "" ? "Enter: ask Claude  ·  Cmd+Enter: in terminal" : "Enter: open"
    }
    // Esc and Backspace on an empty field: back to the search, with what was written in it as one line, so the row is
    // there again to come back with
    function leave(text) {
        launcher.back()
        launcher.field.text = text.trim().replace(/\s*\n\s*/g, " ")
    }

    // A request: the field's Enter, and ⌘Enter / ⌘⌥Enter over IPC. From the search it starts a new conversation (unless
    // one is still running) on the level; there it goes on with the one shown. True when it was taken here, so the key's
    // script doesn't open a terminal instead
    function submit(text) {
        if (launcher.level !== "askclaude") {
            if (text.trim() === "") return false
            if (!session.busy) session.reset()
            launcher.go("askclaude")
        }
        if (session.ask(text)) field.begin("")
        else { field.begin(text); launcher.shakeNow() }   // one is still running: the text waits in the field
        return true
    }
    function fresh() { session.reset(); field.begin("") }

    // Dictation to Claude (⌘⇧ + the dictation key, hypr/scripts/dictate, Dashboard #1908): the level with the dictated
    // text in the field, to check before Enter sends it, as a misheard word could ask for the wrong thing. Over the
    // conversation shown it goes on with it (after what was already written); from elsewhere it starts a new one, as a
    // request from the search does (unless one still runs). Esc closes the launcher, as on a level a key opened.
    function draft(text) {
        const goOn = launcher.open && launcher.level === "askclaude"
        if (!goOn) {
            if (!session.busy) session.reset()
            launcher.open = true
            launcher.go("askclaude")
            launcher.keyLevel = "askclaude"
        }
        const before = goOn ? field.text.trim() : ""
        field.begin(before !== "" ? before + " " + text : text)
    }

    // ⌘⌃Enter: from the level, the conversation goes on in Claude Code in a terminal, with its usual tools (stopped here
    // first: one session can't run in two places); from the search or without one, the text is a new session's prompt
    function terminal(text, goOn) {
        const q = text.trim()
        launcher.open = false
        if (!goOn || session.sessionId === "") {
            Quickshell.execDetached([scripts + "/terminal-or-claude"].concat(q !== "" ? ["--", q] : []))
            return
        }
        if (session.busy) session.stop()
        const home = Quickshell.env("HOME")
        Quickshell.execDetached([scripts + "/terminal", "--dir", home + "/Projects", "--", home + "/.local/bin/claude",
                                 "--resume", session.sessionId].concat(q !== "" ? [q] : []))
    }

    // An answer while the launcher isn't showing it: the row says so, and a notification for now, its click back here
    // (a toast in the top bar may take its place)
    Connections {
        target: a.session
        function onAnswered() {
            if ((a.launcher.open && a.launcher.level === "askclaude") || a.session.toastViewing) return
            a.session.unseen = true
            const last = a.session.entries[a.session.entries.length - 1] || {}
            const body = (last.text || "").slice(0, 200)
            Quickshell.execDetached(["bash", "-c", '[ "$(notify-send -a Claude -i lucide:bot -A default=Open -w -- "$1" "$2")" = default ] && qs ipc call launcher openLevel askclaude',
                                     "_", "Claude answered", body])
        }
    }
}
