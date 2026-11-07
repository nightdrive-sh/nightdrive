.pragma library
.import "AskClaudeTools.js" as Tools

// One line of a conversation's events.jsonl (hypr/scripts/ask-claude.d/unit.sh) into AskClaudeSession's entries:
// Claude Code's stream-json, and Nightdrive's own lines around each turn. `s` is the session (AskClaudeSession.qml):
// add(), update(), flush(), live, busy, lastAt and ended(), which it gives here so the parsing stays out of the view.
//   nightdrive_turn {prompt, at}                      a request: "you", and the turn runs
//   nightdrive_end {status, message, at}              how it ended: done, error, timeout, cancelled

var NOTOOLS = "Claude Code or Nightdrive's tools aren't set up here: Cmd+Enter opens a terminal"

function read(s, line) {
    var ev
    try { ev = JSON.parse(line) } catch (e) { return }
    if (!ev || typeof ev !== "object") return
    if (ev.type === "nightdrive_turn") {
        s.add({ kind: "you", text: String(ev.prompt || "") })
        s.busy = true
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
        for (const c of (ev.message && ev.message.content) || [])
            if (c.type === "tool_result")
                s.update(x => x.kind === "step" && x.id === c.tool_use_id, x => ({ state: c.is_error ? "error" : "done" }))
    }
    // A failed result says so in nightdrive_end, which has the message too
}

// The turn's end: steps still running stopped, and what went wrong as an error entry
function end(s, ev) {
    s.flush()
    s.update(x => x.kind === "step" && x.state === "run", x => ({ state: "stop" }))
    var text = ev.status === "cancelled" ? "Stopped"
             : ev.status === "timeout" ? (ev.message || "Ran out of time")
             : ev.status === "error" ? (ev.message === "notools" ? NOTOOLS : ev.message || "Claude couldn't answer")
             : ""
    if (text !== "") s.add({ kind: "error", text: String(text) })
    s.busy = false
    s.ended(Number(ev.at) || Date.now())
}
