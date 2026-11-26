.pragma library
.import "AskClaudeTools.js" as Tools

// One line of a conversation's events.jsonl (hypr/scripts/ask-claude.d/unit.sh) into AskClaudeSession's entries:
// Claude Code's stream-json, and Nightdrive's own lines around each turn. `s` is the session (AskClaudeSession.qml):
// add(), update(), flush(), live, busy, lastAt and ended(), which it gives here so the parsing stays out of the view.
//   nightdrive_turn {prompt, at, dictated?}           a request: "you", and the turn runs
//   nightdrive_end {status, message, at}              how it ended: done, error, timeout, cancelled; the turn's result
//                                                     cards (#2245) under its answer

var NOTOOLS = "Claude Code or Nightdrive's tools aren't set up here: Cmd+Enter opens a terminal"

function read(s, line) {
    var ev
    try { ev = JSON.parse(line) } catch (e) { return }
    if (!ev || typeof ev !== "object") return
    if (ev.type === "nightdrive_turn") {
        // heard: dictated, so the conversation says it is what was heard (AskClaudeThread)
        s.add({ kind: "you", text: String(ev.prompt || ""), heard: ev.dictated === true })
        s.busy = true
        s.turnAt = Number(ev.at) || Date.now()
        s.dictated = ev.dictated === true   // its answer's unsure mark is read and left out (AskClaudeSession.flush)
        s.unsure = false
        s.newTurn()                         // the last turn's changes, and its card's Undo, go
    } else if (ev.type === "nightdrive_end") end(s, ev)
    else if (ev.type === "stream_event") {
        var e = ev.event || {}
        var b = e.content_block || {}
        if (e.type === "content_block_start" && b.type === "tool_use")
            s.add(Object.assign({ kind: "step", id: b.id, name: b.name, state: "run" }, Tools.step(b.name, null)))
        else if (e.type === "content_block_delta" && e.delta && e.delta.type === "text_delta") s.live += e.delta.text
        else if (e.type === "content_block_stop") s.flush()
    } else if (ev.type === "assistant") {
        // The whole message once it's done: a step's arguments are known now, to say what it is done on
        for (const c of (ev.message && ev.message.content) || [])
            if (c.type === "tool_use") s.update(x => x.kind === "step" && x.id === c.id, x => Tools.step(x.name, c.input))
    } else if (ev.type === "user") {
        var results = false
        for (const c of (ev.message && ev.message.content) || [])
            if (c.type === "tool_result") {
                results = true
                s.update(x => x.kind === "step" && x.id === c.tool_use_id, x => ({ state: c.is_error ? "error" : "done" }))
            }
        if (results) s.reloadCards()   // a card may have come with it
    }
    // A failed result says so in nightdrive_end, which has the message too
}

// The turn's end: steps still running stopped, and what went wrong as an error entry
function end(s, ev) {
    s.flush()
    s.update(x => x.kind === "step" && x.state === "run", x => ({ state: "stop" }))
    var at = Number(ev.at) || Date.now()
    s.add({ kind: "results", from: s.turnAt, to: at })   // shows nothing when the turn added no card
    s.reloadCards()
    var text = ev.status === "cancelled" ? "Stopped"
             : ev.status === "timeout" ? (ev.message || "Ran out of time")
             : ev.status === "error" ? (ev.message === "notools" ? NOTOOLS : ev.message || "Claude couldn't answer")
             : ""
    if (text !== "") s.add({ kind: "error", text: String(text) })
    s.busy = false
    s.checkChanges()   // what the turn changed, for the small card's Undo (#3157)
    s.ended(at)
}
