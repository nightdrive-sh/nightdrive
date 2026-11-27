.pragma library

// Whether the open thread's messages have to be read again after the list was (#3612). A reload that keeps the
// thread open doesn't open it again (that would mark it read and reset its view), so a reply just sent or a message a
// sync brought stayed out of sight until the thread was opened anew. was and now are the thread's rows in notmuch
// search's JSON before and after: a message more or less (total), or a newer one (timestamp), changes it. Tags alone
// (read, replied) don't: the messages on show are the same.
function changed(was, now) {
    if (!was || !now || was.thread !== now.thread) return false
    return was.total !== now.total || was.timestamp !== now.timestamp
}

// The messages a refresh brought into the thread on show that are still unread (#3615), by id: was and now are the
// thread's messages before and after (Notmuch.qml's show()). Only the new ones: a message the user marked unread
// again stays so, and the open() that put the thread on show has already marked the rest read.
function arrived(was, now) {
    const before = {}
    for (const m of was || []) before[m.id] = true
    return (now || []).filter(m => !before[m.id] && (m.tags || []).indexOf("unread") >= 0).map(m => m.id)
}
