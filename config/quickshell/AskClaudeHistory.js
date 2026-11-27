.pragma library

// What Ask Claude's history says of a conversation (`ask-claude list --json`, #2246), for the launcher's Ask Claude ›
// History (AskClaudeHistoryLevels.qml) and the card's own list (AskClaudeHistory.qml, #3713) alike.

// How long ago its last turn was, short: "now", "12 min", "3 h", "2 d"
function ago(ms) {
    const d = Math.max(0, (Date.now() - ms) / 1000)
    if (d < 60) return "now"
    if (d < 3600) return Math.floor(d / 60) + " min"
    if (d < 86400) return Math.floor(d / 3600) + " h"
    return Math.floor(d / 86400) + " d"
}

// How it ended when not well: "" when it went through (or still runs)
function failure(c) {
    if (c.status === "error") return "failed"
    if (c.status === "timeout") return "ran out of time"
    if (c.status === "cancelled") return "stopped"
    return ""
}

// Its right-hand word: running, the one open in the card now, or its age
function when(c, openId) {
    if (c.status === "running") return "working…"
    return c.id === openId ? "open" : ago(c.last)
}
