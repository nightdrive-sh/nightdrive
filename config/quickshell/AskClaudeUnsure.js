.pragma library
// The sign that Claude wasn't sure (Dashboard #3154): a dictated request's answer begins with MARK when Claude couldn't
// tell what was meant, or a tool refused, instead of a guess. This is the one place it is defined: hypr/scripts/ask-claude
// reads MARK from this line into the dictation's prompt (hypr/scripts/ask-claude-dictated.txt, its @MARK@), and
// AskClaudeSession tells such an answer by it. Keep the line as it is: `var MARK = "…"`, plain ASCII.
var MARK = "[?]"

// Whether an answer (or its first text block) is marked unsure: MARK first, before any other text
function unsure(text) {
    return String(text || "").replace(/^\s+/, "").indexOf(MARK) === 0
}

// The answer without the mark, to show
function strip(text) {
    const t = String(text || "")
    return unsure(t) ? t.replace(/^\s+/, "").slice(MARK.length).replace(/^\s+/, "") : t
}

// Whether a finished request needs the user's look (Dashboard #3155): "unsure" when Claude marked its answer, "error"
// when the last request ended in an error (Claude couldn't answer, the tools aren't there), "" otherwise. Only a
// dictated request counts: it was sent without a look at the text, so the toast opens large to show what was heard
// (AskClaudeToast.qml); a typed one was seen as it was written and keeps the small card. A tool's failed step alone
// doesn't count: Claude may go on and do it another way, and says so with the mark when it can't.
function look(entries, dictated, unsure) {
    if (!dictated) return ""
    if (unsure) return "unsure"
    const list = entries || []
    let i = list.length - 1
    while (i >= 0 && list[i].kind !== "you") i--
    return list.slice(i + 1).some(e => e.kind === "error") ? "error" : ""
}
