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
