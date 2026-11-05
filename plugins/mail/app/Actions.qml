import QtQuick

// What Mail does to threads: move them (archive, delete, spam, a drag onto a folder), delete them for good, read and
// unread, and take a step back with ⌘Z. Apart from shell.qml so the window's file holds its state and layout, and this
// the acting on it; the list's keys, the reading pane's buttons and the message windows call in here.
QtObject {
    id: ops
    required property var win
    required property Item sidebar      // FolderSidebar: which folder lies under a dragged thread
    readonly property var nm: win.mailer
    readonly property var folders: win.folders

    // Delete, archive and spam move the open thread (or the picked ones) to the account's Trash, Archive or Spam
    // folder (on the server too, at the next sync, so a phone sees it the same way and the server's spam filter
    // learns from it) and open the next one. Not spam moves it back to the inbox.
    function moveThread(to, text, which) {
        const ts = which || win.targets()
        if (!ts.length || folders[win.folder].dir === to) return
        // Other threads than the open one (dragged to a folder): the open one stays open
        const openId = win.threads[win.current] ? win.threads[win.current].thread : ""
        const keep = !ts.some(t => t.thread === openId)
        const at = Math.min.apply(null, ts.map(t => win.threads.findIndex(x => x.thread === t.thread)))
        if (ts.length > 1) text += ": " + ts.length + " threads"
        const tq = ts.map(t => "thread:" + t.thread).join(" or ")
        // Only the messages in the folder being looked at: your own replies stay in Sent.
        const q = "(" + tq + ") and (" + win.folderQuery(win.folder) + ")"
        const back = folders[win.folder].dir
        // In the inbox's folder a message shows in Inbox by its inbox tag; anywhere else it loses the tag.
        const inbox = dir => [dir === "INBOX" ? "+inbox" : "-inbox"]
        const from = win.sources(win.folder), there = [win.account.maildir ? win.account.maildir + "/" + to : to]
        nm.move(to, q, from, r => {
            if (r.error) { win.say(r.error); return }
            const ids = (r.ids || []).map(i => "id:\"" + i + "\"").join(" or ")
            if (ids) done({ text: text, undo: () => nm.move(back, ids, there, () => nm.tag(inbox(back), ids, () => win.reload(keep, at))) })
            nm.tag(inbox(to), to === "INBOX" && ids ? ids : tq, () => win.reload(keep, at))
        })
    }
    // d: to Trash, and in Trash deleted for good (after asking)
    function trash() { if (folders[win.folder].dir === "Trash") eraseThreads(); else moveThread("Trash", "Moved to Trash") }

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

    // ⇧U, or ✓ on a folder: every unread message in it read (with a search on, the results only), in the next sync on
    // the server too. ⌘Z makes the same ones unread again: they carry a tag of their own until then (undoTag), so the
    // step doesn't keep thousands of ids.
    readonly property string undoTag: "nightmail-read-"
    function markAllRead(i) {
        const q = "(" + (i === win.folder ? win.query() : win.folderQuery(i)) + ") and tag:unread"
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

    // Threads dragged from the list onto a folder move there, as the keys move them (⌘Z too). Inbox, Archive, Spam
    // and Trash take them; Sent and Drafts hold what you wrote, and the folder being looked at is where they are.
    property var dragged: null          // the threads being dragged (a picked one drags all the picked)
    property int dropFolder: -1         // the folder under it, if it takes it
    function takesDrop(i) { return ["INBOX", "Archive", "Spam", "Trash"].indexOf(folders[i].dir) >= 0 && i !== win.folder }
    property point dragPos              // where the pointer is: the ghost follows it (DragGhost.qml)
    function dragOver(pos) {
        dragPos = pos
        dropFolder = sidebar.dropAt(pos, takesDrop)
    }
    function startDrag(t) { dragged = win.isPicked(t) ? win.targets() : [t] }
    function drop() {
        const t = dragged, i = dropFolder
        dragged = null; dropFolder = -1
        if (!t || i < 0) return
        const to = folders[i].dir
        moveThread(to, to === "Trash" ? "Moved to Trash" : to === "Archive" ? "Archived" : to === "Spam" ? "Marked as spam"
                       : folders[win.folder].dir === "Spam" ? "Not spam: moved to Inbox" : "Moved to Inbox", t)
    }
    function archive() { moveThread("Archive", "Archived") }
    // The reading pane's buttons, for the mouse: what the keys do (a archive, d delete, ! spam, r reply …)
    readonly property var readerActions: {
        const dir = folders[win.folder].dir
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
        if (folders[win.folder].dir === "Spam") moveThread("INBOX", "Not spam: moved to Inbox")
        else moveThread("Spam", "Marked as spam")
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
