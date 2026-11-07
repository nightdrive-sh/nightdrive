pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "AskClaudeTools.js" as Tools
import "AskClaudeEvents.js" as Events

// Ask Claude's conversation (Dashboard #1895): one at a time, kept here and shown by Ask Claude's toast
// (AskClaudeToast.qml). Each request runs hypr/scripts/ask-claude --start, which starts the turn as a systemd user unit
// with Nightdrive's tools only (#2244) and returns; the turn's events come through the conversation's events.jsonl,
// read here as it grows (AskClaudeEvents.js), so a turn goes on through Quickshell's restart and is picked up again
// (ask-claude --current). A request after the first goes on with the same session (--resume). The view reads
// `entries` and `live` (AskClaudeThread.qml).
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
        if (q === "" || busy || starter.running) return false
        if (sessionId !== "" && Date.now() - lastAt > freshAfter) reset()
        const first = sessionId === ""
        // The session's name (claude -n) is the request's start, to find it again in the Claude menu and /resume
        const line = q.split("\n")[0]
        const name = line.length > 40 ? line.slice(0, 40).replace(/\s+\S*$/, "") + "…" : line
        pending = q
        starter.command = [script, "--start"].concat(first ? ["--name", name] : ["--resume", sessionId], ["--", q])
        busy = true
        starter.running = true
        return true
    }
    // ⌃C, the small card's Cancel: the unit stops, and its end comes through the events (or now, when it never started)
    function stop() {
        if (!busy) return
        Quickshell.execDetached([script, "--cancel"])
    }
    function reset() {
        if (busy) stop()
        tail.running = false
        entries = []; live = ""; sessionId = ""; unseen = false; busy = false
    }

    function add(e) { entries = entries.concat([e]) }
    function update(pred, change) {
        entries = entries.map(e => pred(e) ? Object.assign({}, e, change(e)) : e)
    }
    function flush() { if (live !== "") { add({ kind: "text", text: live.trim() }); live = "" } }
    // A turn's end (AskClaudeEvents.js): an earlier one read again after a restart isn't news
    function ended(at) {
        lastAt = at
        if (at >= watchedFrom) answered()
    }

    // Reads the conversation's events from its first line: what a restart lost comes back, and the file's later turns
    // as they're written. -F waits for a file not there yet
    property double watchedFrom: 0
    function watch(id) {
        if (sessionId === id && tail.running) return
        tail.running = false
        entries = []; live = ""
        sessionId = id
        watchedFrom = Date.now() - 2000   // a turn that ends as this starts still counts as news
        tail.command = ["tail", "-n", "+1", "-F", stateDir + "/" + id + "/events.jsonl"]
        tail.running = true
    }

    readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/nightdrive/ask"
    property string pending: ""          // the request being started, shown with the error when it can't start

    // --start: {"id"} once the turn runs, or {"error"}
    Process {
        id: starter
        stdout: StdioCollector {
            onStreamFinished: {
                let r = {}
                try { r = JSON.parse(text) } catch (e) {}
                if (r.id) { s.watch(r.id); return }
                s.busy = false
                s.add({ kind: "you", text: s.pending })
                s.add({ kind: "error", text: r.error === "notools" ? Events.NOTOOLS
                                           : r.error === "busy" ? "Claude is still working on another request"
                                           : r.error || "Claude couldn't start" })
                s.answered()
            }
        }
    }
    Process {
        id: tail
        stdout: SplitParser { onRead: line => Events.read(s, line) }
    }
    // After Quickshell's restart: the conversation that runs, or a recent one, comes back as it was
    Process {
        id: current
        command: [s.script, "--current"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                let r = {}
                try { r = JSON.parse(text) } catch (e) {}
                if (!r.id || s.sessionId !== "") return
                if (r.running || Date.now() - r.last < s.freshAfter) { s.watch(r.id); s.lastAt = r.last }
            }
        }
    }
}
