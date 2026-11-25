.pragma library

// A thread's messages as Mail shows them (#3622). notmuch show walks the reply tree depth first, so a new reply to an
// older message landed in the middle, folded, while an older message last in the tree showed open as if it were the
// newest. Mail reads a thread by date instead: oldest at the top, the newest last (open, and the one a reply answers).

// A draft deleted in Mail moves to its account's Trash and keeps its draft tag: it was never sent, so it isn't part
// of the conversation. A draft with a file anywhere else (Drafts) still is, and shows with its Resume button.
function deletedDraft(tags, filenames) {
    const files = Array.isArray(filenames) ? filenames : filenames ? [filenames] : []
    return (tags || []).indexOf("draft") >= 0 && files.length > 0 && files.every(f => /\/Trash\/(cur|new|tmp)\//.test(f))
}

// The messages by timestamp, ties in the tree's order (a message and its quick reply in the same second), without the
// deleted drafts, unless nothing else is left (a deleted draft opened in Trash still shows itself). Each message has
// timestamp, and gone when it is a deleted draft; gone is taken off.
function order(list) {
    const kept = list.filter(m => !m.gone)
    const out = (kept.length ? kept : list).map((m, i) => ({ m: m, i: i }))
    out.sort((a, b) => (a.m.timestamp - b.m.timestamp) || (a.i - b.i))
    return out.map(x => { delete x.m.gone; return x.m })
}

// Which message of an ordered thread is the newest one received or sent (not a draft being written): it stays open
// in a long thread, where the read ones before it fold. -1 when there is none.
function newest(list) {
    for (let i = list.length - 1; i >= 0; i--) if (!list[i].draft) return i
    return -1
}
