pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "AskClaudeTools.js" as Tools
import "AskClaudeEvents.js" as Events
import "AskClaudeUnsure.js" as Unsure

// Ask Claude's conversation (Dashboard #1895): one at a time, kept here and shown by Ask Claude's toast
// (AskClaudeToast.qml). Each request runs hypr/scripts/ask-claude --start, which starts the turn as a systemd user unit
// with Nightdrive's tools only (#2244) and returns; the turn's events come through the conversation's events.jsonl,
// read here as it grows (AskClaudeEvents.js), so a turn goes on through Quickshell's restart and is picked up again
// (ask-claude --current). A request after the first goes on with the same session (--resume). The view reads
// `entries` and `live` (AskClaudeThread.qml).
//   entries: [{ kind: "you", text }, { kind: "step", id, glyph, text, state: run | done | error | stop },
//             { kind: "text", text }, { kind: "error", text }, { kind: "results", from, to }]
// A turn's result cards (#2245) are the conversation's results.json (config/mcp/results.py), read into `cards`; the
// "results" entry after a turn's answer shows those added while it ran (AskClaudeResults.qml).
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
    // The running or last turn was dictated (say and forget, #3122; its nightdrive_turn says so, AskClaudeEvents.js), and
    // its answer so far begins with Claude's unsure mark (AskClaudeUnsure.js, #3154): Claude couldn't tell what was meant
    // or a tool refused, and asks. The mark itself is left out of the text shown.
    property bool dictated: false
    property bool unsure: false
    // The finished request needs a look (AskClaudeUnsure.look, #3155): "unsure", "error" or "". Ask Claude's toast opens
    // large for it instead of the small card's "answered"
    readonly property string look: busy ? "" : Unsure.look(entries, dictated, unsure)
    property double turnAt: 0            // the running or last turn's start (ms): its cards are those added since
    property var cards: []               // results.json's cards
    property var saved: ({})             // a card's Save, by its file: { name } or { error } (AskClaudeCard.qml)
    readonly property string filesDir: sessionId !== "" ? stateDir + "/" + sessionId + "/files" : ""
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
    property var card: null              // set by ClaudeConfirm as it is made, cleared as it is destroyed (a reload)
    readonly property bool pendingCard: !!card && card.open && card.inlined
    signal answered()                    // a request finished (its answer, an error, or stopped)

    // The changes the last turn made (#3157): its conversation's, since the turn's start, from Claude's change log
    // (ask-claude undo list: config/mcp/undo_turn.py), asked at the turn's end. The small card offers Undo while any
    // is still in place. undoState: "" (not pressed), "run", "done" or "error"; undoNote what it undid, or why not
    property int changesInPlace: 0
    property string undoState: ""
    property string undoNote: ""
    readonly property bool undoable: !busy && changesInPlace > 0 && undoState !== "done"
    signal undoFinished()
    function newTurn() { changesInPlace = 0; undoState = ""; undoNote = ""; checkAgain = checker.running }
    function turnArgs() { return [sessionId, String(Math.floor(turnAt))] }
    // A conversation read again from its start (a restart) ends each of its turns in a row: the last one's asks
    property bool checkAgain: false
    function checkChanges() {
        if (sessionId === "" || !turnAt) return
        if (checker.running) { checkAgain = true; return }
        checker.command = [script, "undo", "list"].concat(turnArgs())
        checker.running = true
    }
    // ask-claude undo undo …: newest first, those still in place, as the user's own Undo
    function undoTurn() {
        if (!undoable || undoer.running) return
        undoState = "run"
        undoer.command = [script, "undo", "undo"].concat(turnArgs())
        undoer.running = true
    }
    Process {
        id: checker
        stdout: StdioCollector {
            onStreamFinished: {
                if (s.checkAgain) { s.checkAgain = false; Qt.callLater(s.checkChanges); return }
                let r = {}
                try { r = JSON.parse(text) } catch (e) {}
                s.changesInPlace = Array.isArray(r.changes) ? r.changes.filter(c => c && c.state === "done").length : 0
            }
        }
    }
    Process {
        id: undoer
        stdout: StdioCollector { id: undoOut }
        stderr: StdioCollector { id: undoErr }
        onExited: code => {
            let r = {}
            try { r = JSON.parse(undoOut.text) } catch (e) {}
            if (code === 0 && Array.isArray(r.undone)) {
                s.undoState = "done"
                const n = r.undone.length
                s.undoNote = n === 0 ? "it was undone already" : n === 1 ? r.undone[0] : n + " changes"
            } else {
                s.undoState = "error"
                s.undoNote = undoErr.text.trim().split("\n").pop() || "Couldn't undo it"
            }
            s.undoFinished()
        }
    }

    // A request: false while one runs or when there's nothing to send. A conversation idle for freshAfter starts anew.
    // dictated: it came from a dictation without a look at it, so Claude gets the dictation's prompt (ask-claude --dictated)
    function ask(text, dictated) {
        const q = text.trim()
        if (q === "" || busy || starter.running) return false
        if (stale()) reset()
        const first = sessionId === ""
        // The session's name (claude -n) is the request's start, to find it again in the Claude menu and /resume
        const line = q.split("\n")[0]
        const name = line.length > 40 ? line.slice(0, 40).replace(/\s+\S*$/, "") + "…" : line
        pending = q
        starter.command = [script, "--start"].concat(dictated ? ["--dictated"] : [],
                                                     first ? ["--name", name] : ["--resume", sessionId], ["--", q])
        busy = true
        starter.running = true
        return true
    }
    // Whether the next request starts anew: the conversation has been idle for freshAfter, unless it was brought back
    // from the history on purpose (reopened), when a request goes on with it however old it is
    property bool reopened: false
    function stale() { return sessionId !== "" && !busy && !reopened && Date.now() - lastAt > freshAfter }
    // The launcher's history (AskClaudeHistoryLevels.qml, #2246): an earlier conversation back in the toast, as it was,
    // its cards too. False while another one runs: there is one conversation at a time, and the running one stays
    function open(id) {
        if (!/^[0-9a-f-]{36}$/.test(id) || ((busy || starter.running) && id !== sessionId)) return false
        watch(id)                        // the one already shown stays as it is
        reopened = true
        unseen = false
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
        entries = []; live = ""; sessionId = ""; unseen = false; busy = false; unsure = false; reopened = false
        cards = []; saved = ({}); cardsText = ""
        newTurn()
    }

    function add(e) { entries = entries.concat([e]) }
    function update(pred, change) {
        entries = entries.map(e => pred(e) ? Object.assign({}, e, change(e)) : e)
    }
    // An answer's block as it ends. Only a dictated request's answer is read for the mark: a typed one is shown as it is
    function flush() {
        if (live === "") return
        const t = live.trim()
        live = ""
        if (dictated) unsure = Unsure.unsure(t)
        add({ kind: "text", text: dictated ? Unsure.strip(t) : t })
    }
    // A turn's end (AskClaudeEvents.js): an earlier one read again after a restart isn't news
    function ended(at) {
        lastAt = at
        if (at >= watchedFrom) answered()
    }

    // results.json again: after a tool's result (results_add's among them) and at a turn's end (AskClaudeEvents.js), as
    // well as on the file's change, which a file swapped in whole (results.py's save) may not report
    function reloadCards() { if (sessionId !== "") resultsFile.reload() }
    property string cardsText: ""        // what `cards` was read from: the same text again changes nothing on screen
    function readCards(text) {
        if (text === cardsText) return
        cardsText = text
        let list = []
        try { const d = JSON.parse(text); if (d && Array.isArray(d.cards)) list = d.cards.filter(c => c && typeof c === "object") } catch (e) {}
        cards = list
    }
    // A card's Save (ask-claude save ID FILE): into Downloads under a free name, with its source (ask-claude.d/save.py)
    function save(file) {
        if (sessionId === "" || !file) return
        const p = saveProc.createObject(s, { file: file, command: [script, "save", sessionId, file] })
        p.running = true
    }
    Component {
        id: saveProc
        Process {
            id: sp
            property string file: ""
            stdout: StdioCollector { id: spOut }
            stderr: StdioCollector { id: spErr }
            onExited: code => {
                let r = {}
                try { r = JSON.parse(spOut.text) } catch (e) {}
                const done = Object.assign({}, s.saved)
                done[sp.file] = code === 0 && r.name ? { name: r.name }
                              : { error: spErr.text.trim().split("\n").pop() || "Couldn't save it" }
                s.saved = done
                sp.destroy()
            }
        }
    }
    FileView {
        id: resultsFile
        path: s.sessionId !== "" ? s.stateDir + "/" + s.sessionId + "/results.json" : ""
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: s.readCards(text())
        onLoadFailed: s.readCards("")
    }

    // Reads the conversation's events from its first line: what a restart lost comes back, and the file's later turns
    // as they're written. -F waits for a file not there yet
    property double watchedFrom: 0
    function watch(id) {
        if (sessionId === id && tail.running) return
        tail.running = false
        entries = []; live = ""; cards = []; saved = ({}); cardsText = ""; reopened = false
        newTurn()
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
