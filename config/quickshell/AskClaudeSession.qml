pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "AskClaudeTools.js" as Tools

// Ask Claude's conversation (Dashboard #1895): one at a time, kept here and shown by Ask Claude's toast below the bar
// (AskClaudeToast.qml). Each request runs hypr/scripts/ask-claude --stream, which sets up Claude Code with Nightdrive's
// tools only and passes its events on as they come; a request after the first goes on with the same session (--resume). The view reads `entries` and `live` (AskClaudeThread.qml).
//   entries: [{ kind: "you", text }, { kind: "step", id, glyph, text, state: run | done | error | stop },
//             { kind: "text", text }, { kind: "error", text }]
Singleton {
    id: s

    // --- Tunables ---
    readonly property int freshAfter: 15 * 60 * 1000   // ms after the last answer when the next request starts anew

    readonly property string script: Quickshell.env("HOME") + "/.config/hypr/scripts/ask-claude"
    readonly property string thinkingGlyph: Tools.THINKING
    property var entries: []
    property string live: ""             // the answer's text as it is being written, added to entries when its block ends
    property string sessionId: ""
    property bool busy: false
    property bool unseen: false          // an answer came while the toast was closed (the launcher's row says so)
    property double lastAt: 0
    // Ask Claude's toast (AskClaudeToast.qml) shows the conversation; the launcher's row and keys (AskClaudeLevels.qml)
    // ask it to through these, as neither knows the other
    signal showRequested(string text, bool send)   // open it: send text as a new request, or leave it in the field
    signal hideRequested()
    signal deleteBackRequested(bool word)          // ⌘⌫ / ⌥⌫ over it, which Hyprland takes (Launcher.qml's IPC)
    property string draft: ""            // what the toast's field has, for ⌘Enter's terminal (Launcher.qml's IPC)
    // The toast shows the conversation now: Claude's confirmation card comes into it, a short one (ClaudeConfirm.qml
    // decides, and sets card); the toast shows it while pendingCard and answers through card.decide()
    property bool toastViewing: false
    readonly property bool viewing: toastViewing
    property var card: null
    readonly property bool pendingCard: !!card && card.open && card.inlined
    signal answered()                    // a request finished (its answer, an error, or stopped)

    // A request: false while one runs or when there's nothing to send. A conversation idle for freshAfter starts anew
    function ask(text) {
        const q = text.trim()
        if (q === "" || busy) return false
        if (sessionId !== "" && Date.now() - lastAt > freshAfter) reset()
        const first = sessionId === ""
        // The session's name (claude -n) is the request's start, to find it again in the Claude menu and /resume
        const line = q.split("\n")[0]
        const name = line.length > 40 ? line.slice(0, 40).replace(/\s+\S*$/, "") + "…" : line
        add({ kind: "you", text: q })
        proc.command = [script, "--stream"].concat(first ? ["--name", name] : ["--resume", sessionId], ["--", q])
        busy = true
        proc.running = true
        return true
    }
    function stop() {
        if (!busy) return
        proc.running = false
        add({ kind: "error", text: "Stopped" })
    }
    function reset() {
        if (busy) proc.running = false
        entries = []; live = ""; sessionId = ""; unseen = false
    }

    function add(e) { entries = entries.concat([e]) }
    function update(pred, change) {
        entries = entries.map(e => pred(e) ? Object.assign({}, e, change(e)) : e)
    }
    function flush() { if (live !== "") { add({ kind: "text", text: live.trim() }); live = "" } }

    // One line of claude's stream-json, or the script's own nightdrive_error
    function read(line) {
        let ev
        try { ev = JSON.parse(line) } catch (e) { return }
        if (ev.type === "system" && ev.subtype === "init" && ev.session_id) sessionId = ev.session_id
        else if (ev.type === "stream_event") {
            const e = ev.event || {}
            const b = e.content_block || {}
            if (e.type === "content_block_start" && b.type === "tool_use")
                add(Object.assign({ kind: "step", id: b.id, name: b.name, state: "run" }, Tools.step(b.name, null)))
            else if (e.type === "content_block_delta" && e.delta && e.delta.type === "text_delta") live += e.delta.text
            else if (e.type === "content_block_stop") flush()
        } else if (ev.type === "assistant") {
            // The whole message once it's done: a step's arguments are known now, to say what it is done on
            for (const c of (ev.message && ev.message.content) || [])
                if (c.type === "tool_use") update(e => e.kind === "step" && e.id === c.id, e => Tools.step(e.name, c.input))
        } else if (ev.type === "user") {
            for (const c of (ev.message && ev.message.content) || [])
                if (c.type === "tool_result") update(e => e.kind === "step" && e.id === c.tool_use_id, e => ({ state: c.is_error ? "error" : "done" }))
        } else if (ev.type === "result" && ev.is_error) add({ kind: "error", text: ev.result || "Claude couldn't answer" })
        else if (ev.type === "nightdrive_error")
            add({ kind: "error", text: ev.message === "notools" ? "Claude Code or Nightdrive's tools aren't set up here: Cmd+Enter opens a terminal"
                                                                : ev.message })
    }

    Process {
        id: proc
        stdout: SplitParser { onRead: line => s.read(line) }
        onExited: {
            s.flush()
            s.update(e => e.kind === "step" && e.state === "run", e => ({ state: "stop" }))
            s.busy = false
            s.lastAt = Date.now()
            s.answered()
        }
    }
}
