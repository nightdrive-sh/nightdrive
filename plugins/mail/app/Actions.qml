import QtQuick

// What Mail does to threads: move them (archive, delete, spam, a drag onto a folder), delete them for good, read and
// unread, and take a step back with ⌘Z. Apart from shell.qml so the window's file holds its state and layout, and this
// the acting on it; the list's keys, the reading pane's buttons and the message windows call in here.
QtObject {
    id: ops
    required property var win
    required property Item sidebar      // FolderSidebar: which folder lies under a dragged thread
    required property Item outDrag      // OutDrag.qml: the threads as text, once the drag leaves the window
    readonly property var nm: win.mailer
    readonly property var folders: win.folders
    readonly property var sorter: win.sorter    // Sorting.qml: your own folders and their rules

    // The folder a thread is in: the one picked, or in a search of all folders the one it was found in (Search.qml).
    // What the keys and buttons do follows it: a thread found in Archive has no Archive button.
    function dirOf(t) { return folders[win.homeOf(t)].dir }
    // The open thread's (or the first picked one's), for the buttons and d ! in Trash and Spam
    function hereDir() { const ts = win.targets(); return ts.length ? dirOf(ts[0]) : folders[win.folder].dir }

    // Delete, archive and spam move the open thread (or the picked ones) to the account's Trash, Archive or Spam
    // folder (on the server too, at the next sync, so a phone sees it the same way and the server's spam filter
    // learns from it) and open the next one. Not spam moves it back to the inbox. Threads a search found in several
    // folders move a folder at a time, and one ⌘Z takes them all back.
    // then(finish): more to do once they have moved (sortInto's rules); finish({ text, undo }) or finish(null)
    function moveThread(to, text, which, then) {
        const ts = (which || win.targets()).filter(t => dirOf(t) !== to)
        if (!ts.length) {
            if (then) then(more => { if (more && more.undo) done(more); win.reload(true) })
            return
        }
        // Other threads than the open one (dragged to a folder): the open one stays open
        const openId = win.threads[win.current] ? win.threads[win.current].thread : ""
        const keep = !ts.some(t => t.thread === openId)
        const at = Math.min.apply(null, ts.map(t => win.threads.findIndex(x => x.thread === t.thread)))
        if (ts.length > 1) text += ": " + ts.length + " threads"
        const groups = []
        for (const t of ts) {
            const h = win.homeOf(t), g = groups.find(x => x.home === h)
            if (g) g.threads.push(t); else groups.push({ home: h, threads: [t] })
        }
        const undos = []
        let left = groups.length
        const moved = () => {
            if (--left) return
            const finish = more => {
                if (more) { text = more.text || text; if (more.undo) undos.push(more.undo) }
                if (undos.length) done({ text: text, undo: () => undos.forEach(u => u()) })
                win.reload(keep, at)
            }
            if (then) then(finish); else finish(null)
        }
        for (const g of groups) moveGroup(to, g, undos, moved)
    }
    // In the inbox's folder a message shows in Inbox by its inbox tag; anywhere else it loses the tag.
    function inboxTag(dir) { return [dir === "INBOX" ? "+inbox" : "-inbox"] }
    function moveGroup(to, g, undos, moved) {
        const tq = g.threads.map(t => "thread:" + t.thread).join(" or ")
        // Only the messages in the thread's folder: your own replies stay in Sent.
        const q = "(" + tq + ") and (" + win.folderQuery(g.home) + ")"
        const back = folders[g.home].dir
        const from = win.sources(g.home), there = [win.account.maildir ? win.account.maildir + "/" + to : to]
        nm.move(to, q, from, r => {
            if (r.error) { win.say(r.error); moved(); return }
            const ids = (r.ids || []).map(i => "id:\"" + i + "\"").join(" or ")
            if (ids) undos.push(() => nm.move(back, ids, there, () => nm.tag(inboxTag(back), ids, () => win.reload(true))))
            nm.tag(inboxTag(to), to === "INBOX" && ids ? ids : tq, moved)
        })
    }
    // d: to Trash, and in Trash deleted for good (after asking)
    function trash() { if (hereDir() === "Trash") eraseThreads(); else moveThread("Trash", "Moved to Trash") }

    // Deleting for good, in Trash (or Spam, emptied): the files go, and the next sync deletes them on the server. There
    // is no ⌘Z, so it asks first (the confirm panel: Enter deletes, Esc doesn't).
    function erase(query, n, dir) {
        const d = dir || "Trash"
        nm.erase(query, win.sources(folders.findIndex(f => f.dir === d)), r => {
            if (r.error) { win.say(r.error); return }
            win.say(r.erased ? "Deleted for good: " + n + (n === 1 ? " thread" : " threads") : "Nothing deleted")
            win.reload(false, win.current)
        }, d)
    }
    function eraseThreads() {
        const ts = win.targets()
        if (!ts.length) return
        const n = ts.length
        const q = "(" + ts.map(t => "thread:" + t.thread).join(" or ") + ") and (" + win.folderQuery(win.folder) + ")"
        win.confirm = { title: n === 1 ? "Delete this thread for good?" : "Delete " + n + " threads for good?",
                    detail: (n === 1 ? "It is" : "They are") + " deleted here and, at the next sync, on the server. This can't be undone.",
                    action: "Delete", run: () => erase(q, n) }
    }
    // ⌘⇧⌫: in Spam it empties Spam, anywhere else Trash. Both ask first, with the count.
    function emptyFolder() { emptyDir(folders[win.folder].dir === "Spam" ? "Spam" : "Trash") }
    function emptyDir(dir) {
        const t = folders.findIndex(f => f.dir === dir), q = win.folderQuery(t)
        nm.run(["count", "--output=threads", "--exclude=false", q], out => {
            const n = parseInt(out) || 0
            if (!n) { win.say(dir + " is empty"); return }
            win.confirm = { title: "Empty " + dir + "?", detail: (n === 1 ? "The thread" : "All " + n + " threads") + " in " + dir + " (" + win.account.address
                            + (n === 1 ? ") is" : ") are") + " deleted here and, at the next sync, on the server. This can't be undone.",
                        action: "Empty " + dir, run: () => erase(q, n, dir) }
        })
    }
    // u: read threads (or a mix) become unread, and unread ones read
    function toggleRead() {
        const ts = win.targets()
        if (!ts.length) return
        const read = ts.every(t => t.tags.indexOf("unread") >= 0)
        nm.tag([read ? "-unread" : "+unread"], ts.map(t => "thread:" + t.thread).join(" or "), () => win.reload(true))
    }

    // ⇧U (here), or ✓ on a folder: every unread message in it read (⇧U with a search on: what it found, in all folders
    // or the one picked; ✓ always the whole folder), in the next sync on the server too. ⌘Z makes the same ones unread again: they carry a tag of their own until then (undoTag), so the
    // step doesn't keep thousands of ids.
    readonly property string undoTag: "nightmail-read-"
    function markAllRead(i, here) {
        const q = "(" + (here ? win.query() : win.folderQuery(i)) + ") and tag:unread"
        nm.run(["count", "--output=threads", q], t => {
            const n = parseInt(t) || 0
            if (!n) { win.say("Nothing unread here"); return }
            const mark = undoTag + Date.now()
            nm.tag(["-unread", "+" + mark], q, () => {
                done({ text: "Marked " + n + (n === 1 ? " thread" : " threads") + " read",
                       undo: () => nm.tag(["+unread", "-" + mark], "tag:" + mark, () => win.reload(true)) })
                win.reload(true)
            })
        })
    }

    // Threads dragged from the list onto a folder move there, as the keys move them (⌘Z too). Inbox, Archive, Spam,
    // Trash and your own folders take them; Sent and Drafts hold what you wrote, and the folder being looked at is
    // where they are.
    property var dragged: null          // the threads being dragged (a picked one drags all the picked)
    property int dropFolder: -1         // the folder under it, if it takes it; -2: New folder (made, then sorted into)
    function takesDrop(i) { return i === -2 || (folders[i].own || ["INBOX", "Archive", "Spam", "Trash"].indexOf(folders[i].dir) >= 0) && (win.searcher.wide || i !== win.folder) }
    property point dragPos              // where the pointer is: the ghost follows it (DragGhost.qml)
    property Item dragFrom: null        // the row dragged from: the drag out is released with it
    // Out of the window, the drag goes on as the desktop's (OutDrag.qml): the threads as a line each, into a
    // terminal or another app. It starts only there, so the drag to a folder stays Mail's own, with its ghost; the
    // pointer held down still reaches the window outside its edges, and Wayland lets the drag start then.
    function dragOver(pos) {
        dragPos = pos
        if (dragged && (pos.x < 0 || pos.y < 0 || pos.x >= win.width || pos.y >= win.height)) {
            const t = dragged
            dragged = null; dropFolder = -1
            outDrag.threads(dragFrom, t)
            return
        }
        dropFolder = sidebar.dropAt(pos, takesDrop)
    }
    function startDrag(t, row) {
        dragged = win.isPicked(t) ? win.targets() : [t]
        dragFrom = row
        outDrag.prepare(dragged.length > 1 ? dragged.length + " threads" : dragged[0].subject, dragged.length > 1)
    }
    function drop() {
        outDrag.release(dragFrom)
        dragFrom = null
        const t = dragged, i = dropFolder
        dragged = null; dropFolder = -1
        if (!t || i === -1) return
        // On New folder: its name asked for, then the threads sorted into it, as m's New folder… does
        if (i === -2) { win.menus.newFolder(j => sortInto(j, t)); return }
        const to = folders[i].dir
        if (folders[i].own) { sortInto(i, t); return }
        if (to === "INBOX" && t.some(x => folders[win.homeOf(x)].own)) { unsort(t); return }
        moveThread(to, to === "Trash" ? "Moved to Trash" : to === "Archive" ? "Archived" : to === "Spam" ? "Marked as spam"
                       : dirOf(t[0]) === "Spam" ? "Not spam: moved to Inbox" : "Moved to Inbox", t)
    }
    function archive() { moveThread("Archive", "Archived") }

    // Your own folders sort by sender (#3733): threads dropped into one (or sent there with m or the menu) move as any
    // drag moves them, then their senders' mail goes there from now on, with what of theirs is in the inbox now
    // (sorting.py learn; domain: the senders' whole domains, from the menu). Dragged back to the inbox, their senders'
    // rules end (forget). One ⌘Z takes back the move and the rules.
    function sortInto(i, ts, domain) {
        const to = folders[i].dir, acc = win.account.id
        moveThread(to, "Moved to " + to, ts, finish => sorter.learn(acc, to, ts.map(t => "thread:" + t.thread), domain, r => {
            if (r.error) { finish(null); win.say(r.error, { danger: true }); return }
            const who = domain ? "all of " + r.added.concat(r.removed).map(x => x.domain).filter(x => x).join(", ")
                               : r.senders.length === 1 ? r.senders[0] : r.senders.length + " senders"
            const more = r.moved.length ? " (" + r.moved.length + " from the inbox too)" : ""
            finish({ text: "Mail from " + who + " goes to " + to + " from now on" + more,
                     undo: () => sorter.undo(r, () => win.reload(true)) })
        }))
    }
    function unsort(ts) {
        moveThread("INBOX", "Moved to Inbox", ts, finish => sorter.forget(win.account.id, ts.map(t => "thread:" + t.thread), r => {
            if (r.error || !r.removed.length) { finish(null); return }
            finish({ text: "Moved to Inbox: mail from " + r.removed.map(x => sorter.describe(x)).join(", ") + " comes to the inbox again",
                     undo: () => sorter.undo(r) })
        }))
    }
    // The open thread's sender stops being sorted (the thread's Stop, the menu): the mail stays where it is
    function stopSorting(rule) {
        sorter.removeRule(rule, r => {
            if (r.error) { win.say(r.error, { danger: true }); return }
            done({ text: "Mail from " + sorter.describe(rule) + " comes to the inbox again", undo: () => sorter.undo({ added: [], removed: r.removed }) })
        })
    }
    // The reading pane's buttons, for the mouse: what the keys do (a archive, d delete, ! spam, r reply …)
    readonly property var readerActions: {
        // (win.current and win.threads read here, so the buttons follow the thread opened in a search of all folders)
        const dir = win.current >= 0 && win.threads[win.current] ? dirOf(win.threads[win.current]) : folders[win.folder].dir
        return [{ id: "reply", icon: "reply", text: "Reply", tip: "Reply to all", keys: "r" },
                { id: "claude", icon: "sparkles", text: "Reply with Claude", short: "Claude", tip: "Claude writes the reply", keys: "⌘⇧C" },
                { id: "forward", icon: "forward", text: "Forward", tip: "Forward with the attachments", keys: "f" }]
            .concat(dir === "Archive" ? [] : [{ id: "archive", icon: "archive", text: "Archive", tip: "Archive", keys: "a" }])
            .concat([{ id: "trash", icon: "trash-2", text: dir === "Trash" ? "Delete for good" : "Delete", short: "Delete",
                       tip: dir === "Trash" ? "Delete for good (asks first)" : "Move to Trash", keys: "d" },
                     { id: "spam", icon: dir === "Spam" ? "inbox" : "ban", text: dir === "Spam" ? "Not spam" : "Spam",
                       tip: dir === "Spam" ? "Not spam: back to the Inbox" : "Mark as spam", keys: "!" }])
    }
    readonly property var windowActions: readerActions.slice(0, 3)
    function act(id, msgs) {
        if (id === "reply") win.compose("all", msgs)
        else if (id === "claude") win.compose("claude", msgs)
        else if (id === "forward") win.compose("forward", msgs)
        else if (id === "archive") archive()
        else if (id === "trash") trash()
        else if (id === "spam") spam()
        else if (id === "unread") toggleRead()
        else if (id === "single") win.open(win.current)
    }
    // ! marks the thread as spam, or in Spam as not spam.
    function spam() {
        if (hereDir() === "Spam") moveThread("INBOX", "Not spam: moved to Inbox")
        else moveThread("Spam", "Marked as spam")
    }

    // A draft left beside its twin (DraftBar.qml, #3625) to Trash, as a thrown-away draft goes: the thread leaves it
    // out (order.js), the next sync takes it off the server, and ⌘Z brings it back to Drafts. after(): the window's
    // own update (a message window's thread is its own copy).
    function trashDraft(draftId, after) {
        const q = "id:\"" + draftId.replace(/"/g, "\"\"") + "\""
        nm.move("Trash", q, [], r => {
            if (r.error) { win.say(r.error); return }
            done({ text: "Draft moved to Trash", undo: () => nm.move("Drafts", q, ["Trash"], () => win.reload(true)) })
            win.reload(true)
            if (after) after()
        })
    }

    // ⌘Z (Ctrl+Z) takes back archive, delete and spam, newest first.
    property var undoStack: []
    function done(step) { undoStack = undoStack.concat([step]).slice(-win.undoDepth); win.say(step.text + "   ⌘Z undoes") }
    function undo() {
        if (undoStack.length === 0) { win.say("Nothing to undo"); return }
        const step = undoStack[undoStack.length - 1]
        undoStack = undoStack.slice(0, -1)
        step.undo()
        win.say("Undone: " + step.text.toLowerCase())
    }
}
