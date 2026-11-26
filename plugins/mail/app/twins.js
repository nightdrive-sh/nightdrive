.pragma library

// One reply, one send (#3625). A thread had two drafts answering the same message: the user sent one, and the other,
// left in the thread, looked like their own unfinished reply, so it went too and the sender got two versions. So Mail
// says when a draft has a twin: another draft answering the same message, or a reply to it already sent.
//
// Each message of a thread (Notmuch.qml) has parent, the id of the message it answers in notmuch's reply tree (its
// In-Reply-To), draft (a file in Drafts) and sent (a file in Sent: the user's own). A message being written has no id
// in the thread yet: twins() takes the message it answers and the draft it was saved as ("" for none).

// The other drafts answering parent, and the newest reply to it already sent (null when none).
function twins(list, parent, self) {
    if (!parent) return { drafts: [], sent: null }
    const same = (list || []).filter(m => m.parent === parent && m.id !== self)
    const sent = same.filter(m => m.sent && !m.draft)
    return {
        drafts: same.filter(m => m.draft),
        sent: sent.length ? sent.reduce((a, b) => b.timestamp > a.timestamp ? b : a) : null
    }
}

// What to say of a draft, or of a reply being written, given its twins and a date formatter: "" when nothing.
// A reply already sent matters most: sending this one too answers twice.
function warning(t, when) {
    if (t.sent) return "You already answered this message, " + when(t.sent.timestamp) + ": sending this answers it again"
    const n = t.drafts.length
    if (n) return n === 1 ? "Another draft answers the same message: send only one"
                          : n + " other drafts answer the same message: send only one"
    return ""
}
