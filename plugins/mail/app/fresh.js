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
