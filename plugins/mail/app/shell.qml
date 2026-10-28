import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs
import qs.kit

// Nightdrive Mail: folders, thread list and the open thread, over notmuch.
ShellRoot {
    id: shell
    FloatingWindow {
        id: win
        title: "Mail"
        implicitWidth: 1440
        implicitHeight: 900
        color: c.bg
        // Closing the window (⌘W) quits Mail: a process left without its window would only look open to `nightmail`.
        // A message still going is let finish first, and one that failed waits in Drafts.
        onClosed: { outbox.jobs = outbox.jobs.filter(j => j.state === "sending"); composeEnded() }
        // Started for a new message alone (`nightmail new` or a mailto: link with Mail closed), only the writing window
        // shows, and Mail quits when it closes (composeEnded); `nightmail open` shows this one over IPC (reveal).
        visible: Quickshell.env("NIGHTMAIL_COMPOSE_ONLY") !== "1"

        // The look, as Deck's: the apps' kit (kit/AppLook.qml)
        AppLook { id: c }

        Notmuch { id: nm }
        Outbox {
            id: outbox
            nm: nm
            notifyFailures: !win.visible
            // The answered or forwarded message gets the flag phones and webmail show too (after the next sync).
            onSent: job => {
                if (job.replyId) nm.tag(["+replied"], "id:\"" + job.replyId + "\"")
                if (job.forwardId) nm.tag(["+passed"], "id:\"" + job.forwardId + "\"")
                win.reload(true)
            }
            onReopen: job => {
                if (composeWin.visible) { win.say("Not sent: it is in Drafts"); return }
                composer.start(job.heading, job.f)
                composer.replyId = job.replyId; composer.forwardId = job.forwardId
                composer.failed = true; composer.status = job.error
                win.showCompose()
            }
            onIdle: win.composeEnded()
        }
        // Nightdrive Contacts' people, when it is installed: addresses to complete, a sender's card (ContactBook.qml)
        readonly property ContactBook book: ContactBook {}
        // For components in their own files, which don't see this file's ids.
        readonly property QtObject look: c
        readonly property QtObject mailer: nm

        // Settings (⌘,), kept in ~/.config/nightmail/settings.json.
        property var settings: ({ composeFloats: true, view: 0 })
        FileView {
            id: settingsFile
            path: Quickshell.env("HOME") + "/.config/nightmail/settings.json"
            watchChanges: true
            onFileChanged: reload()
            onLoaded: { try { win.settings = Object.assign({ composeFloats: true, view: 0 }, JSON.parse(text())) } catch (e) {} }
        }
        function setting(key, value) {
            const s = Object.assign({}, settings); s[key] = value; settings = s
            settingsFile.setText(JSON.stringify(s, null, 2) + "\n")
            if (key === "view") htmlMode = value     // the open thread shows the change at once
        }

        // `nightmail sync` asks for a reload once new mail is indexed; `nightmail new` opens an empty message.
        IpcHandler {
            target: "mail"
            function refresh(): void { win.reload(true) }
            function compose(): void { win.compose("new") }
            // Settings › Apps › Mail (`nightmail settings`)
            function openSettings(): void { win.showSettings = true }
            // "shown" when the window was hidden (see visible), for `nightmail`: the kit's focus() wouldn't find it and
            // would start Mail again, losing the message being written.
            function reveal(): string { if (win.visible) return ""; win.visible = true; return "shown" }
            // A mailto: link (`nightmail mailto:…`, when Mail is the email app: launcher › Settings › Apps › Default apps)
            function mailto(url: string): void { win.compose("new", null, win.mailtoFields(url)) }
            // A notification's click and Reply button (lib/notify.py, through `nightmail show` and `reply`).
            // (Not "show": `qs ipc call` takes that word for its own command.)
            function openMessage(id: string): void { win.openMessage(id, null) }
            function replyTo(id: string): void { win.openMessage(id, () => win.compose("all")) }
            function claudeReply(id: string): void { win.openMessage(id, () => win.compose("claude")) }
            // The Claude writes card's Enter and Esc (`nightmail claude-reply`, `claude-cancel`)
            function claudeAnswer(json: string): void { const a = JSON.parse(json); composer.answered(a.gen, a.text, a.read) }
            function claudeCancel(gen: string): void { if (parseInt(gen) === composer.gen) composer.bodyEdit.forceActiveFocus() }
        }

        // @NAME in a query is the account's folder NAME (folderQuery)
        readonly property var folders: [
            { name: "Inbox", dir: "INBOX", glyph: "inbox", query: "@INBOX and tag:inbox" },
            { name: "Sent", dir: "Sent", glyph: "send", query: "@Sent" },
            { name: "Drafts", dir: "Drafts", glyph: "file-pen", query: "@Drafts" },
            // Archived before archive moved mail to the Archive folder: in the inbox's folder without the inbox tag. Gmail's
            // Archive (All Mail) holds the inbox's messages too, and Trash and Spam lose theirs only at the next sync.
            { name: "Archive", dir: "Archive", glyph: "archive", query: "(@Archive and not @INBOX and not @Trash and not @Spam) or (@INBOX and not tag:inbox)" },
            { name: "Spam", dir: "Spam", glyph: "ban", query: "@Spam" },
            { name: "Trash", dir: "Trash", glyph: "trash-2", query: "@Trash" }
        ]
        readonly property int arrowStep: 80     // px an arrow key scrolls the message
        readonly property int headerHeight: 22  // the folders' title line and the list's search line
        readonly property int headerGap: 30     // from them to the first folder and the first message
        readonly property int undoDepth: 20     // steps ⌘Z can take back
        property int folder: 0
        // Narrow windows: the folders hide below foldersMin (⌘B shows them all the same), and below twoPanes the list
        // and the open thread take turns: a click or Enter opens the thread, Esc or ← goes back to the list
        readonly property int foldersMin: 960
        readonly property int twoPanes: 720
        property var foldersChoice: null    // ⌘B's, over what the width says
        readonly property bool showFolders: foldersChoice !== null ? foldersChoice : width >= foldersMin
        readonly property bool onePane: width < twoPanes
        property bool readerOpen: false     // in one pane: the thread shows instead of the list
        // Only the list on show: moving in it points at a thread without opening it, so passing one by doesn't mark it
        // read; Enter, → or a click opens it
        readonly property bool listOnly: onePane && !readerOpen
        function openReader() { if (onePane && current >= 0) { readerOpen = true; reader.contentY = 0; open(current) } }
        onOnePaneChanged: readerOpen = false
        property int htmlMode: 0            // h cycles: 0 text, 1 HTML on the dark page, 2 HTML on light paper; each thread opens in settings.view
        // The accounts (compose.py accounts: { id, name, address, maildir, signature }), each with its own folders: Mail
        // shows one at a time, its mail being what lies under its folder in ~/Mail. Tab changes it.
        property var accounts: []
        property int acct: 0
        readonly property var account: accounts[acct] || { id: "", address: "", maildir: "", signature: "" }
        property var inboxUnread: ({})      // unread threads in each account's inbox, by id
        function pickAccount(i, stay) {
            if (i === acct || i < 0 || i >= accounts.length) return
            acct = i
            setting("account", accounts[i].id)
            pickFolder(0, stay)
        }
        // A folder's query in the account shown (or another one). The account and the folder are one path term: notmuch
        // matches each term against any of a message's files, so "path:account/** and folder:INBOX" would also take a
        // message mailed between two of your accounts, from the other one's inbox.
        function folderQuery(i, a) {
            return "(" + folders[i].query.replace(/@(\w+)/g, (m, d) => folderTerm(d, a)) + ")"
        }
        function folderTerm(dir, a) {
            const m = (a || account).maildir
            return m ? "path:\"" + m + "/" + dir + "/**\"" : "folder:/" + dir + "$/"
        }
        // Where the files of the folder being looked at are, for move.py and erase.py: only those move
        function sources(i) {
            const m = account.maildir, d = folders[i].dir
            return (d === "Archive" ? ["Archive", "INBOX"] : [d]).map(x => m ? m + "/" + x : x)
        }
        property var threads: []
        property int current: -1
        property var messages: []
        property var unreadCounts: ({})

        function query() {
            const q = search.text.trim()
            return q === "" ? folderQuery(folder) : "(" + folderQuery(folder) + ") and (" + q + ")"
        }

        // A new array is a new model: the ListView starts again at the top with its currentIndex at 0, and current, often
        // unchanged (the thread after an archived one has its index), doesn't set it back. stay: the same folder read
        // anew (a sync, a move, read), so the list keeps its place; a folder or a search of its own starts at the top.
        function setThreads(l, stay) {
            const y = list.contentY
            threads = l
            if (!stay) return
            list.currentIndex = Qt.binding(() => current)
            list.contentY = Math.max(list.originY - list.topMargin,
                                     Math.min(y, list.originY + list.contentHeight + list.bottomMargin - list.height))
        }

        // keep: the open thread stays open; at: where to open one when it has gone (the one after a moved thread)
        function reload(keep, at) {
            const id = keep && current >= 0 && threads[current] ? threads[current].thread : ""
            nm.search(query(), list => {
                setThreads(list, keep || at !== undefined)
                let i = list.findIndex(t => t.thread === id)
                if (i < 0) i = list.length > 0 ? Math.min(at || 0, list.length - 1) : -1
                // Threads picked stay picked through the sync's reload, and nothing opens (it would mark one read)
                if (keep && picked.length) {
                    picked = picked.filter(p => list.some(t => t.thread === p))
                    if (picked.length > 1) { current = i; return }
                    open(i); return
                }
                if (!keep || i !== current) open(i)
            })
            for (let f = 0; f < folders.length; f++) {
                const n = f
                nm.run(["count", "--output=threads", "(" + folderQuery(f) + ") and tag:unread"], t => {
                    const u = Object.assign({}, unreadCounts); u[n] = parseInt(t) || 0; unreadCounts = u
                })
            }
            for (const a of accounts) {
                nm.run(["count", "--output=threads", "(" + folderQuery(0, a) + ") and tag:unread"], t => {
                    const u = Object.assign({}, inboxUnread); u[a.id] = parseInt(t) || 0; inboxUnread = u
                })
            }
        }

        // again: the second try, after the list was read anew
        function open(i, then, again) {
            // Something to do on the thread (a notification's Reply) needs it on show
            if (then && onePane) readerOpen = true
            current = i
            picked = []; anchorId = ""
            if (listOnly) return
            htmlMode = settings.view
            if (i < 0) { messages = []; return }
            const t = threads[i]
            // By id: marking it read reloads the list (new objects) before a long thread has come back
            nm.show(t.thread, m => {
                if (!threads[current] || threads[current].thread !== t.thread) return
                // Nothing in it: indexing a sync has joined the thread to another one under a new id since the list was
                // read. The list is read again, and the thread with the same subject and date opens.
                if (m.length === 0 && !again) {
                    nm.search(query(), list => {
                        setThreads(list, true)
                        const j =list.findIndex(x => x.subject === t.subject && x.timestamp === t.timestamp)
                        open(j >= 0 ? j : Math.min(i, list.length - 1), then, true)
                    })
                    return
                }
                messages = m
                if (then) then()
            })
            if (t.tags.indexOf("unread") >= 0)
                nm.tag(["-unread"], "thread:" + t.thread, () => reload(true))
        }

        // Writing: mode "new", "reply" (to the sender), "all", "claude" (a reply Claude drafts) or "forward", all on the
        // thread's last message, or "resume" to write on the thread's draft. The thread is the open one, or msgs (a
        // message window's).
        function compose(mode, msgs, fields) {
            const all = msgs || messages
            if (composeWin.visible) return
            if (mode === "new") {
                // From the account shown, with its signature under the text
                const f = Object.assign({}, fields || {}, { account: account.id })
                if (account.signature) f.body = (f.body || "") + "\n\n" + account.signature
                composer.start("New message", f); showCompose(); return
            }
            if (mode === "resume") {
                const d = draft(all)
                if (!d) return
                nm.compose(["resume", d.id], r => {
                    if (r.error) { say(r.error); return }
                    composer.start("Draft", r)
                    // A reply's draft keeps ⌘⇧C, when the message it answers is here.
                    const answers = r.in_reply_to.replace(/[<>\s]/g, "")
                    if (answers && all.some(m => m.id === answers)) composer.replyId = answers
                    showCompose()
                })
                return
            }
            const last = all.filter(m => !m.draft).pop()
            if (!last) return
            if (mode === "forward") {
                nm.compose(["forward", last.id], r => {
                    if (r.error) { say(r.error); return }
                    composer.start("Forward", r)
                    composer.forwardId = last.id
                    showCompose()
                })
                return
            }
            nm.compose(["reply", last.id].concat(mode === "reply" ? [] : ["all"]), r => {
                if (r.error) { say(r.error); return }
                composer.start(mode === "reply" ? "Reply to sender" : "Reply", r)
                composer.replyId = last.id
                showCompose()
                if (mode === "claude") composer.rewrite()
            })
        }
        // mailto:a@b?cc=…&subject=…&body=… as the writing window's fields (RFC 6068)
        function mailtoFields(url) {
            const m = url.replace(/^mailto:/i, "").split("?")
            const f = { to: decodeURIComponent(m[0] || "") }
            for (const kv of (m[1] || "").split("&")) {
                const i = kv.indexOf("="), k = kv.slice(0, i).toLowerCase()
                if (i > 0 && ["to", "cc", "subject", "body"].indexOf(k) >= 0) {
                    const v = decodeURIComponent(kv.slice(i + 1).replace(/\+/g, " "))
                    f[k] = k === "to" && f.to ? f.to + ", " + v : v
                }
            }
            return f
        }
        // The addresses to complete from are read again each time, so the newest are there.
        function showCompose() {
            composeWin.opening = true; composeWin.visible = true
            win.book.load()
            nm.addresses(list => composer.book = win.book.merge(list.filter(a => !accounts.some(x => x.address === a.address))))
        }
        // The open thread's draft, newest first, if it has one.
        function draft(msgs) { return (msgs || messages).filter(m => m.draft).pop() }

        // A thread in a window of its own (a double click or Enter in the list): it floats or tiles like the writing
        // window, and keeps its own keys.
        function openWindow(i) {
            const t = threads[i]
            if (!t) return
            nm.show(t.thread, m => { if (m.length) messageWindow.createObject(shell, { msgs: m }) })
        }

        // Claude writes the reply (Compose.qml asks): the desktop's Claude writes card opens in the middle of the writing
        // window and runs compose.py through `nightmail claude-draft`: the thread up to the message answered with the
        // draft, or the selected text alone. Its Enter comes back through claudeAnswer().
        function suggest(request) {
            nm.nightmail(["ask-claude", composeWin.title, JSON.stringify(request)],
                         t => { if (t.trim()) { try { composer.failed = true; composer.status = JSON.parse(t).error } catch (e) {} } })
        }

        // Send closes the writing window at once; the message goes in the background (Outbox.qml).
        function sendMail(f) {
            outbox.send(f, composer.heading, composer.replyId, composer.forwardId)
            composeWin.done = true; composeWin.visible = false
        }

        // ⌘S, or closing a message saved before: the copy in Drafts is replaced with this one.
        function saveDraft(f, close) {
            if (close) { composeWin.done = true; composeWin.visible = false }
            nm.compose(["draft", JSON.stringify(f)], r => {
                if (r.error) { composer.failed = true; composer.status = r.error; if (close) composeWin.visible = true; return }
                if (!close) { composer.draftId = r.id; composer.failed = false; composer.status = "Saved in Drafts" }
                reload(true)
                if (close) composeEnded()
            })
        }
        function dismissCompose() { composeWin.done = true; composeWin.visible = false; composeEnded() }
        // The writing window is closed, and its draft saved: Mail started for it alone quits with it, once what it
        // sends has gone (or failed and waits in Drafts).
        function composeEnded() { if (!win.visible && !composeWin.visible && !outbox.jobs.length) Qt.quit() }

        // An attachment opens in the app the desktop picks for it, or is saved in the downloads folder.
        function openPart(msg, f) {
            say("Opening " + f.name + "…")
            nm.part("open", msg.id, f.part, f.name, r => {
                if (r.error) { say(r.error); return }
                Qt.openUrlExternally("file://" + r.path)
                say("")
            })
        }
        // The newest message with HTML, as a page in the browser (lib/parts.py html)
        function openBrowser(msgs) {
            const m = (msgs || win.messages).slice().reverse().find(x => x.html !== "")
            if (!m) { say("This thread has no HTML version"); return }
            nm.page(m.id, r => {
                if (r.error) { say(r.error); return }
                Qt.openUrlExternally("file://" + r.path)
            })
        }
        function savePart(msg, f) {
            nm.part("save", msg.id, f.part, f.name, r => say(r.error || "Saved to " + r.path.replace(Quickshell.env("HOME"), "~")))
        }
        function saveAll(msg) {
            nm.saveAll(msg.id, msg.files, r => {
                if (r.error) { say(r.error); return }
                const dir = r.paths.length ? r.paths[0].replace(/\/[^\/]*$/, "").replace(Quickshell.env("HOME"), "~") : ""
                say("Saved " + r.paths.length + " attachments to " + dir)
            })
        }
        function size(n) {
            if (n < 0) return ""
            if (n < 1024) return n + " B"
            if (n < 1024 * 1024) return Math.round(n / 1024) + " kB"
            return (n / 1024 / 1024).toFixed(1) + " MB"
        }

        function scrollMessage(dy) {
            reader.cancelFlick()
            reader.contentY = Math.max(0, Math.min(reader.contentHeight - reader.height, reader.contentY + dy))
        }

        // Several threads picked (⇧-click, Ctrl-click, ⇧↑ ⇧↓, ⌘A): archive, delete, spam, u and a drag act on them all,
        // and the reading pane says how many. Without any, they act on the open thread. current is then where the
        // keyboard is, and the open thread's messages stay as they were (opening one would mark it read).
        property var picked: []             // the picked threads' ids; empty: only the open thread
        property string anchorId: ""        // the thread a ⇧ range starts from
        function isPicked(t) { return picked.indexOf(t.thread) >= 0 }
        function targets() { return picked.length ? threads.filter(isPicked) : threads[current] ? [threads[current]] : [] }
        function pickRange(i) {
            if (i < 0 || i >= threads.length) return
            let a = threads.findIndex(t => t.thread === anchorId)
            if (a < 0) a = current
            if (a === i) { open(i); return }
            picked = threads.slice(Math.min(a, i), Math.max(a, i) + 1).map(t => t.thread)
            anchorId = threads[a].thread
            current = i
        }
        function togglePick(i) {
            const id = threads[i].thread
            const base = picked.length ? picked : threads[current] ? [threads[current].thread] : []
            const next = base.indexOf(id) >= 0 ? base.filter(p => p !== id) : base.concat([id])
            if (next.length <= 1) { open(next.length ? threads.findIndex(t => t.thread === next[0]) : i); return }
            picked = next; anchorId = id; current = i
        }
        function pickAll() {
            if (threads.length < 2) return
            picked = threads.map(t => t.thread); anchorId = threads[0].thread
        }

        // Delete, archive and spam move the open thread (or the picked ones) to the account's Trash, Archive or Spam
        // folder (on the server too, at the next sync, so a phone sees it the same way and the server's spam filter
        // learns from it) and open the next one. Not spam moves it back to the inbox.
        function moveThread(to, text, which) {
            const ts = which || targets()
            if (!ts.length || folders[folder].dir === to) return
            // Other threads than the open one (dragged to a folder): the open one stays open
            const openId = threads[current] ? threads[current].thread : ""
            const keep = !ts.some(t => t.thread === openId)
            const at = Math.min.apply(null, ts.map(t => threads.findIndex(x => x.thread === t.thread)))
            if (ts.length > 1) text += ": " + ts.length + " threads"
            const tq = ts.map(t => "thread:" + t.thread).join(" or ")
            // Only the messages in the folder being looked at: your own replies stay in Sent.
            const q = "(" + tq + ") and (" + folderQuery(folder) + ")"
            const back = folders[folder].dir
            // In the inbox's folder a message shows in Inbox by its inbox tag; anywhere else it loses the tag.
            const inbox = dir => [dir === "INBOX" ? "+inbox" : "-inbox"]
            const from = sources(folder), there = [account.maildir ? account.maildir + "/" + to : to]
            nm.move(to, q, from, r => {
                if (r.error) { say(r.error); return }
                const ids = (r.ids || []).map(i => "id:\"" + i + "\"").join(" or ")
                if (ids) done({ text: text, undo: () => nm.move(back, ids, there, () => nm.tag(inbox(back), ids, () => reload(keep, at))) })
                nm.tag(inbox(to), to === "INBOX" && ids ? ids : tq, () => reload(keep, at))
            })
        }
        // d: to Trash, and in Trash deleted for good (after asking)
        function trash() { if (folders[folder].dir === "Trash") eraseThreads(); else moveThread("Trash", "Moved to Trash") }

        // Deleting for good, in Trash: the files go, and the next sync deletes them on the server. There is no ⌘Z, so it
        // asks first (the confirm panel: Enter deletes, Esc doesn't).
        property var confirm: null          // { title, detail, action, run }
        onConfirmChanged: if (confirm) confirmPanel.forceActiveFocus(); else list.forceActiveFocus()
        function erase(query, n) {
            nm.erase(query, sources(folders.findIndex(f => f.dir === "Trash")), r => {
                if (r.error) { say(r.error); return }
                say(r.erased ? "Deleted for good: " + n + (n === 1 ? " thread" : " threads") : "Nothing deleted")
                reload(false, current)
            })
        }
        function eraseThreads() {
            const ts = targets()
            if (!ts.length) return
            const n = ts.length
            const q = "(" + ts.map(t => "thread:" + t.thread).join(" or ") + ") and (" + folderQuery(folder) + ")"
            confirm = { title: n === 1 ? "Delete this thread for good?" : "Delete " + n + " threads for good?",
                        detail: (n === 1 ? "It is" : "They are") + " deleted here and, at the next sync, on the server. This can't be undone.",
                        action: "Delete", run: () => erase(q, n) }
        }
        function emptyTrash() {
            const t = folders.findIndex(f => f.dir === "Trash"), q = folderQuery(t)
            nm.run(["count", "--output=threads", "--exclude=false", q], out => {
                const n = parseInt(out) || 0
                if (!n) { say("Trash is empty"); return }
                confirm = { title: "Empty Trash?", detail: (n === 1 ? "The thread" : "All " + n + " threads") + " in Trash (" + account.address
                                + (n === 1 ? ") is" : ") are") + " deleted here and, at the next sync, on the server. This can't be undone.",
                            action: "Empty Trash", run: () => erase(q, n) }
            })
        }
        // u: read threads (or a mix) become unread, and unread ones read
        function toggleRead() {
            const ts = targets()
            if (!ts.length) return
            const read = ts.every(t => t.tags.indexOf("unread") >= 0)
            nm.tag([read ? "-unread" : "+unread"], ts.map(t => "thread:" + t.thread).join(" or "), () => reload(true))
        }

        // ⇧U, or ✓ on a folder: every unread message in it read (with a search on, the results only), in the next sync on
        // the server too. ⌘Z makes the same ones unread again: they carry a tag of their own until then (undoTag), so the
        // step doesn't keep thousands of ids.
        readonly property string undoTag: "nightmail-read-"
        function markAllRead(i) {
            const q = "(" + (i === folder ? query() : folderQuery(i)) + ") and tag:unread"
            nm.run(["count", "--output=threads", q], t => {
                const n = parseInt(t) || 0
                if (!n) { say("Nothing unread here"); return }
                const mark = undoTag + Date.now()
                nm.tag(["-unread", "+" + mark], q, () => {
                    done({ text: "Marked " + n + (n === 1 ? " thread" : " threads") + " read",
                           undo: () => nm.tag(["+unread", "-" + mark], "tag:" + mark, () => reload(true)) })
                    reload(true)
                })
            })
        }

        // Threads dragged from the list onto a folder move there, as the keys move them (⌘Z too). Inbox, Archive, Spam
        // and Trash take them; Sent and Drafts hold what you wrote, and the folder being looked at is where they are.
        property var dragged: null          // the threads being dragged (a picked one drags all the picked)
        property int dropFolder: -1         // the folder under it, if it takes it
        function takesDrop(i) { return ["INBOX", "Archive", "Spam", "Trash"].indexOf(folders[i].dir) >= 0 && i !== folder }
        function dragOver(pos) {
            ghost.x = pos.x + 12; ghost.y = pos.y - ghost.height / 2
            dropFolder = -1
            for (let i = 0; i < folders.length; i++) {
                const f = folderRows.itemAt(i)
                if (f && takesDrop(i) && f.contains(f.mapFromItem(null, pos.x, pos.y))) dropFolder = i
            }
        }
        function startDrag(t) { dragged = isPicked(t) ? targets() : [t] }
        function drop() {
            const t = dragged, i = dropFolder
            dragged = null; dropFolder = -1
            if (!t || i < 0) return
            const to = folders[i].dir
            moveThread(to, to === "Trash" ? "Moved to Trash" : to === "Archive" ? "Archived" : to === "Spam" ? "Marked as spam"
                           : folders[folder].dir === "Spam" ? "Not spam: moved to Inbox" : "Moved to Inbox", t)
        }
        function archive() { moveThread("Archive", "Archived") }
        // The reading pane's buttons, for the mouse: what the keys do (a archive, d delete, ! spam, r reply …)
        readonly property var readerActions: {
            const dir = folders[folder].dir
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
            if (id === "reply") compose("all", msgs)
            else if (id === "claude") compose("claude", msgs)
            else if (id === "forward") compose("forward", msgs)
            else if (id === "archive") archive()
            else if (id === "trash") trash()
            else if (id === "spam") spam()
            else if (id === "unread") toggleRead()
            else if (id === "single") open(current)
        }
        // ! marks the thread as spam, or in Spam as not spam.
        function spam() {
            if (folders[folder].dir === "Spam") moveThread("INBOX", "Not spam: moved to Inbox")
            else moveThread("Spam", "Marked as spam")
        }

        // ⌘Z (Ctrl+Z) takes back archive, delete and spam, newest first.
        property var undoStack: []
        function done(step) { undoStack = undoStack.concat([step]).slice(-undoDepth); say(step.text + "   ⌘Z undoes") }
        function undo() {
            if (undoStack.length === 0) { say("Nothing to undo"); return }
            const step = undoStack[undoStack.length - 1]
            undoStack = undoStack.slice(0, -1)
            step.undo()
            say("Undone: " + step.text.toLowerCase())
        }

        // A quiet line under the list for what just happened.
        property string note: ""
        function say(t) { note = t; noteTimer.restart() }
        Timer { id: noteTimer; interval: 4000; onTriggered: win.note = "" }

        // Opens the thread of a message in the inbox (or wherever it is now, if it has left it), then calls then().
        function openMessage(id, then) {
            const q = "id:\"" + id + "\""
            nm.run(["search", "--output=files", "--exclude=false", q], files => {
                // …/<account>/<folder>/cur/<file>: the account shown becomes the message's (the one whose inbox has it,
                // when it was mailed between two of your accounts)
                const list = files.split("\n").filter(f => f !== "")
                const m = (list.find(f => /\/INBOX\/(cur|new)\//.test(f)) || list[0] || "").match(/([^\/]+)\/([^\/]+)\/(cur|new)\/[^\/]+$/)
                if (!m) { say("That message is gone"); return }
                const a = accounts.findIndex(x => x.maildir === m[1])
                if (a >= 0 && a !== acct) { acct = a; setting("account", accounts[a].id) }
                nm.run(["search", "--output=threads", "--exclude=false", q], t => {
                    const thread = t.trim().replace(/^thread:/, "")
                    folder = 0
                    search.text = ""
                    nm.search(query(), list => {
                        let i = list.findIndex(x => x.thread === thread)
                        if (i < 0) {
                            // Not in the inbox any more: its thread, searched for in the folder the message is in now
                            // (the inbox's folder without the inbox tag is Archive).
                            const f = folders.findIndex((x, n) => n > 0 && x.dir === (m[2] === "INBOX" ? "Archive" : m[2]))
                            folder = f >= 0 ? f : folders.findIndex(x => x.name === "Archive")
                            search.text = "thread:" + thread
                            nm.search(query(), l2 => { threads = l2; open(l2.length ? 0 : -1, then) })
                            return
                        }
                        threads = list
                        open(i, then)
                    })
                    list.forceActiveFocus()
                })
            })
        }

        // stay: picked from the keyboard in the folders (Panes.qml), which keep it; a click goes back to the list
        function pickFolder(i, stay) { folder = i; search.text = ""; reload(false); if (!stay) panes.pane = "list"; list.forceActiveFocus() }
        Panes { id: panes; win: win }

        function when(ts) {
            const d = new Date(ts * 1000), now = new Date()
            if (d.toDateString() === now.toDateString()) return Qt.formatTime(d, "HH:mm")
            if (now - d < 6 * 86400000) return Qt.formatDate(d, "ddd")
            if (d.getFullYear() === now.getFullYear()) return Qt.formatDate(d, "d MMM")
            return Qt.formatDate(d, "d MMM yyyy")
        }
        function fullDate(ts) { return Qt.formatDateTime(new Date(ts * 1000), "ddd d MMM yyyy, HH:mm") }
        function name(from) { const m = from.match(/^\s*"?([^"<]*?)"?\s*</); return m && m[1] !== "" ? m[1] : from.replace(/[<>]/g, "") }
        function address(from) { const m = from.match(/<([^>]+)>/); return m ? m[1] : "" }
        // Plain text to rich text: links clickable, quoted lines quiet.
        function rich(t) {
            const esc = s => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
            return t.replace(/\r/g, "").split("\n").map(l => {
                let h = esc(l).replace(/(https?:\/\/[^\s<]+)/g, '<a href="$1" style="color:' + c.accent + '">$1</a>')
                return /^\s*&gt;/.test(h) ? '<span style="color:' + c.faint + '">' + h + '</span>' : h
            }).join("<br>")
        }

        Component.onCompleted: {
            // Marks of mark-all-read steps that can't be undone any more (the last run's)
            nm.run(["search", "--output=tags", "tag:/^" + undoTag + "/"], t => {
                const old = t.split("\n").filter(x => x.indexOf(undoTag) === 0)
                if (old.length) nm.tag(old.map(x => "-" + x), old.map(x => "tag:" + x).join(" or "))
            })
            loadAccounts()
            book.load()
            list.forceActiveFocus()
        }
        // Without an account yet (no account.conf), Mail offers to set one up (setupPanel), and looks again with each
        // round of the timer below, so the inbox shows once the setup has written it.
        property bool needsAccount: false
        function loadAccounts() {
            nm.compose(["accounts"], r => {
                if (r.error) { needsAccount = true; reload(false); return }
                needsAccount = false
                accounts = r.accounts
                acct = Math.max(0, accounts.findIndex(a => a.id === settings.account))
                reload(false)
            })
        }
        onNeedsAccountChanged: if (needsAccount) setupPanel.forceActiveFocus(); else list.forceActiveFocus()

        // Picks up what the mail sync brought in.
        Timer { interval: 30000; running: true; repeat: true; onTriggered: win.needsAccount ? win.loadAccounts() : win.reload(true) }

        // Mac Mail's keys, with ⌘⇧C (Ctrl+Shift+C) for Claude's reply. Nightdrive sends ⌘Z ⌘R ⌘F to apps as Ctrl+…, which are also the PC mail apps' keys;
        // ⌘N, ⌘B and ⌘⇧C arrive as Super (Meta) + the key. ⌘⏎ opens a terminal, so sending stays Ctrl+⏎.
        Shortcut { sequences: ["/", "Ctrl+F"]; onActivated: search.forceActiveFocus() }
        Shortcut { sequences: ["Meta+Shift+C", "Ctrl+Shift+C"]; onActivated: win.compose("claude") }
        Shortcut { sequence: "Ctrl+R"; onActivated: win.reload(true) }
        Shortcut { sequences: ["Ctrl+N", "Meta+N"]; onActivated: win.compose("new") }
        Shortcut { sequence: "Ctrl+Q"; onActivated: Qt.quit() }
        Shortcut { sequences: ["Meta+,", "Ctrl+,"]; onActivated: win.showSettings = !win.showSettings }
        Shortcut { sequence: "Ctrl+Z"; onActivated: win.undo() }
        Shortcut { sequences: ["Ctrl+B", "Meta+B"]; onActivated: win.foldersChoice = !win.showFolders }

        RowLayout {
            id: content          // what a panel turns off while it shows (AppPanel.behind)
            anchors.fill: parent
            // ? and Ctrl+? show the keys (KeySheet.qml)
            Keys.onPressed: e => sheet.pressed(e)
            AppPointer { c: win.look }      // the pointer hides the keys' frame
            spacing: 0

            // Folders. The title's line and the search's are as high (headerHeight) and as far from the top, so the first
            // folder and the first message line up.
            AppSidebar {
                id: sidebar
                Layout.preferredWidth: win.width < 900 ? 168 : 208
                z: 1        // a folder's tip lies over the list
                visible: win.showFolders
                c: win.look
                title: "Mail"
                headerHeight: 2 * 18 + win.headerHeight
                contentTop: 18 + win.headerHeight + win.headerGap
                bottomMargin: 0     // the account bar's line reaches the foot (AccountBar.qml)
                Repeater {
                    id: folderRows
                    model: win.folders
                    // The same glyphs as the reading pane's buttons
                    delegate: AppNavRow {
                        id: folderRow
                        required property var modelData
                        required property int index
                        c: win.look
                        glyph: modelData.glyph
                        label: modelData.name
                        selected: index === win.folder
                        dropTarget: index === win.dropFolder
                        count: !readButton.visible && win.unreadCounts[index] > 0 ? win.unreadCounts[index] : ""
                        countColor: c.dim
                        active: panes.at === "folders"     // Tab's (Panes.qml)
                        onClicked: win.pickFolder(index)
                        // Under the pointer, the unread count gives way to ✓: mark all read
                        AppIconButton {
                            id: readButton
                            visible: folderRow.hovered && win.unreadCounts[folderRow.index] > 0
                            anchors.right: parent.right; anchors.rightMargin: 6; anchors.verticalCenter: parent.verticalCenter
                            c: win.look
                            glyph: "check-check"
                            hoverColor: c.sel
                            tip: "Mark all read"; keys: "⇧U"; tipSide: "right"
                            onClicked: { win.markAllRead(folderRow.index); list.forceActiveFocus() }
                        }
                    }
                }
                Item { Layout.fillHeight: true }
                AccountBar {
                    c: win.look
                    accounts: win.accounts
                    current: win.acct
                    unread: win.inboxUnread
                    onPicked: i => { win.pickAccount(i); list.forceActiveFocus() }
                }
                SidebarHead {
                    parent: sidebar     // over the sidebar's title, outside its column
                    c: win.look; outbox: outbox
                    headerHeight: sidebar.headerHeight
                    onSettings: win.showSettings = true
                }
            }

            // Thread list. In one pane it fills the window, and while the thread shows it is there at no width: it keeps
            // the keyboard, so j k and the rest go on working from the thread
            Rectangle {
                Layout.preferredWidth: win.onePane ? (win.readerOpen ? 0 : -1) : Math.max(250, Math.min(370, win.width * 0.3 - 30))
                Layout.fillWidth: win.onePane && !win.readerOpen
                Layout.fillHeight: true
                clip: true
                color: "transparent"
                ColumnLayout {
                    anchors.fill: parent
                    spacing: 0
                    AppSearchField {
                        id: search
                        Layout.fillWidth: true
                        Layout.margins: 28
                        Layout.topMargin: 16    // centred between the window's top and the line below
                        // Held to the line's height, so the glyph doesn't push the list down
                        Layout.preferredHeight: win.headerHeight
                        Layout.bottomMargin: 0
                        c: win.look
                        pixelSize: 13
                        onEdited: searchDelay.restart()
                        onEscapePressed: { text = ""; win.reload(false); list.forceActiveFocus() }
                        onReturnPressed: list.forceActiveFocus()
                        onDownPressed: list.forceActiveFocus()
                        Timer { id: searchDelay; interval: 150; onTriggered: win.reload(false) }
                    }
                    // Under the search, level with the line under the thread's buttons (the last pixel of Thread.barHeight)
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.topMargin: reader.barHeight - 1 - search.Layout.topMargin - win.headerHeight
                        Layout.preferredHeight: 1
                        color: c.divider
                    }
                    ListView {
                        id: list
                        Layout.fillWidth: true
                        // The view itself is inset: ListView places its delegates at x 0.
                        Layout.leftMargin: 12
                        Layout.rightMargin: 12
                        Layout.fillHeight: true
                        clip: true
                        model: win.threads
                        currentIndex: win.current
                        boundsBehavior: Flickable.StopAtBounds
                        highlightMoveDuration: 0
                        TouchScroll { view: list }
                        spacing: 2
                        // The rest of the gap under the search, so the first message is level with the first folder
                        topMargin: 18 + win.headerHeight + win.headerGap - reader.barHeight
                        bottomMargin: 12
                        focus: true
                        Keys.onPressed: e => {
                            const k = e.key
                            win.look.moved(e)              // Tab and the arrows show the keys' frame (AppPointer)
                            // The list takes most keys before they reach the sheet: any but ? closes it here.
                            if (win.cheats && k !== Qt.Key_Question && sheet.modifierKeys.indexOf(k) < 0) win.cheats = false
                            if (panes.pressed(e)) { e.accepted = true; return }
                            const ctrl = e.modifiers & Qt.ControlModifier
                            const alt = e.modifiers & Qt.AltModifier
                            const shift = e.modifiers & Qt.ShiftModifier
                            // ⇧↑ ⇧↓ (⇧K ⇧J) pick threads from the open one on; ⌘A (Ctrl+A) picks them all, Esc none
                            if (shift && (k === Qt.Key_Down || k === Qt.Key_J)) win.pickRange(win.current + 1)
                            else if (shift && (k === Qt.Key_Up || k === Qt.Key_K)) win.pickRange(win.current - 1)
                            else if ((ctrl || e.modifiers & Qt.MetaModifier) && k === Qt.Key_A) win.pickAll()
                            else if (k === Qt.Key_Escape && win.picked.length) win.open(win.current)
                            else if ((k === Qt.Key_Escape || k === Qt.Key_Left) && win.readerOpen) win.readerOpen = false
                            else if (k === Qt.Key_Right && win.onePane && !win.readerOpen) win.openReader()
                            else if (ctrl && k === Qt.Key_Down && win.folder < win.folders.length - 1) win.pickFolder(win.folder + 1)
                            else if (ctrl && k === Qt.Key_Up && win.folder > 0) win.pickFolder(win.folder - 1)
                            else if (ctrl && (k === Qt.Key_Up || k === Qt.Key_Down)) {}
                            // The arrows move in the list, as in Mac Mail (Space pages through the message); with the thread
                            // alone on show they scroll it, and j k or ⌥ arrows move on. Only the list on show: PgUp PgDn too
                            else if (win.listOnly && (k === Qt.Key_Down || k === Qt.Key_J)) win.open(Math.min(win.current + 1, win.threads.length - 1))
                            else if (win.listOnly && (k === Qt.Key_Up || k === Qt.Key_K)) win.open(Math.max(win.current - 1, 0))
                            else if (win.listOnly && k === Qt.Key_PageDown) win.open(Math.min(win.current + 10, win.threads.length - 1))
                            else if (win.listOnly && k === Qt.Key_PageUp) win.open(Math.max(win.current - 10, 0))
                            else if ((k === Qt.Key_J || (alt || !win.readerOpen) && k === Qt.Key_Down) && win.current < win.threads.length - 1) win.open(win.current + 1)
                            else if ((k === Qt.Key_K || (alt || !win.readerOpen) && k === Qt.Key_Up) && win.current > 0) win.open(win.current - 1)
                            else if ((alt || !win.readerOpen) && (k === Qt.Key_Up || k === Qt.Key_Down)) {}
                            else if (k === Qt.Key_Down) win.scrollMessage(win.arrowStep)
                            else if (k === Qt.Key_Up) win.scrollMessage(-win.arrowStep)
                            else if (k === Qt.Key_Question) win.cheats = !win.cheats
                            else if (k === Qt.Key_H && shift) win.openBrowser()
                            else if (k === Qt.Key_H) win.htmlMode = (win.htmlMode + 1) % 3
                            // ⌘C copies the text selected in the message (Thread.copy), and never starts a new message
                            else if (reader.isCopy(e)) reader.copy()
                            else if (k === Qt.Key_C) win.compose("new")
                            else if (k === Qt.Key_F) win.compose("forward")
                            // Enter opens the thread in a window of its own; in one pane, first in the window
                            else if (k === Qt.Key_Return || k === Qt.Key_Enter) { if (win.draft()) win.compose("resume"); else if (win.onePane && !win.readerOpen) win.openReader(); else win.openWindow(win.current) }
                            // r answers everyone, ⇧R only the sender; ⌘⇧C (Ctrl+Shift+C) has Claude write the reply.
                            else if (k === Qt.Key_R && !alt) win.compose(e.modifiers & Qt.ShiftModifier ? "reply" : "all")
                            else if (k === Qt.Key_A || k === Qt.Key_E) win.archive()
                            else if ((k === Qt.Key_Backspace || k === Qt.Key_Delete) && shift && (ctrl || e.modifiers & Qt.MetaModifier)) win.emptyTrash()
                            else if (k === Qt.Key_D || k === Qt.Key_NumberSign || k === Qt.Key_Backspace || k === Qt.Key_Delete) win.trash()
                            else if (k === Qt.Key_Exclam) win.spam()
                            else if (k === Qt.Key_U && shift) win.markAllRead(win.folder)
                            else if (k === Qt.Key_U) win.toggleRead()
                            else if (k >= Qt.Key_1 && k < Qt.Key_1 + win.folders.length) win.pickFolder(k - Qt.Key_1)
                            else if (k === Qt.Key_PageDown || k === Qt.Key_PageUp) win.scrollMessage((k === Qt.Key_PageUp ? -1 : 1) * (reader.height - 80))
                            else if (k === Qt.Key_Space) win.scrollMessage((e.modifiers & Qt.ShiftModifier ? -1 : 1) * (reader.height - 80))
                            else return
                            e.accepted = true
                        }
                        delegate: AppRow {
                            id: row
                            required property var modelData
                            required property int index
                            readonly property bool unread: modelData.tags.indexOf("unread") >= 0
                            readonly property bool picked: win.picked.indexOf(modelData.thread) >= 0
                            implicitHeight: col.implicitHeight + 28
                            c: win.look
                            // With Tab in the folders (Panes.qml), the open one is only marked
                            selected: picked || index === win.current && !win.picked.length && panes.at === "list"
                            marked: index === win.current
                            active: panes.at === "list" && !win.picked.length
                            // With threads picked, the keyboard's place among them
                            border.color: index === win.current && win.picked.length ? c.line : selected && active ? c.frame : "transparent"
                            // Dragged sideways (towards the folders) it moves; up and down the list scrolls as before.
                            DragHandler {
                                target: null
                                grabPermissions: PointerHandler.TakeOverForbidden
                                cursorShape: Qt.ClosedHandCursor
                                onActiveChanged: if (active) win.startDrag(row.modelData); else win.drop()
                                onCentroidChanged: if (active) win.dragOver(centroid.scenePosition)
                            }
                            TapHandler {
                                acceptedModifiers: Qt.NoModifier
                                onTapped: { win.open(row.index); panes.pane = "list"; list.forceActiveFocus(); win.openReader() }   // in one pane: point, then open
                                onDoubleTapped: if (win.draft()) win.compose("resume"); else win.openWindow(row.index)
                            }
                            // ⇧-click picks the threads from the open one to this; Ctrl-click picks this one or leaves it
                            // out (⌘-click is the desktop's: it moves the window)
                            TapHandler { acceptedModifiers: Qt.ShiftModifier; onTapped: { win.pickRange(row.index); list.forceActiveFocus() } }
                            TapHandler { acceptedModifiers: Qt.ControlModifier; onTapped: { win.togglePick(row.index); list.forceActiveFocus() } }
                            Column {
                                id: col
                                anchors.left: parent.left; anchors.right: parent.right
                                anchors.leftMargin: 16; anchors.rightMargin: 16
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 6
                                Item {
                                    width: parent.width; height: who.implicitHeight
                                    // The names take what the count and the date leave, so only they elide and the
                                    // count always shows right after them.
                                    Text {
                                        id: who
                                        anchors.left: parent.left
                                        width: Math.max(0, Math.min(implicitWidth, date.x - 16 - (count.visible ? count.implicitWidth : 0)))
                                        elide: Text.ElideRight
                                        text: row.modelData.authors
                                        font.family: c.font; font.pixelSize: 13
                                        font.weight: row.unread ? Font.Medium : Font.Normal
                                        color: c.title
                                    }
                                    Text {
                                        id: count
                                        visible: row.modelData.total > 1
                                        anchors.left: who.right; anchors.baseline: who.baseline
                                        text: "  " + row.modelData.total
                                        font: who.font; color: who.color
                                    }
                                    // Unread: a dot in the row's left padding, in the accent of the cursor by the name.
                                    Rectangle {
                                        visible: row.unread
                                        width: 6; height: 6; radius: 3
                                        x: -11; anchors.verticalCenter: who.verticalCenter
                                        color: c.primary
                                    }
                                    Text {
                                        id: date
                                        anchors.right: parent.right; anchors.baseline: who.baseline
                                        text: win.when(row.modelData.timestamp)
                                        font.family: c.font; font.pixelSize: 11; color: row.unread ? c.title : c.faint
                                    }
                                }
                                Text {
                                    width: parent.width; elide: Text.ElideRight
                                    text: row.modelData.subject || "(no subject)"
                                    font.family: c.font; font.pixelSize: 12
                                    color: row.unread ? c.title : c.dim
                                }
                            }
                        }
                        Text {
                            visible: win.threads.length === 0
                            anchors.centerIn: parent
                            text: "Nothing here"; color: c.faint; font.family: c.font; font.pixelSize: 12
                        }
                    }
                    // In Trash: emptying it, which asks first
                    AppKeyAction {
                        Layout.leftMargin: 28
                        Layout.topMargin: 8
                        Layout.bottomMargin: win.note === "" ? 24 : 0
                        visible: win.folders[win.folder].dir === "Trash" && win.threads.length > 0
                        c: win.look
                        keys: "⌘⇧⌫"; label: "Empty Trash"; hoverColor: c.danger
                        onClicked: win.emptyTrash()
                    }
                    Text {
                        Layout.fillWidth: true
                        Layout.margins: 28
                        Layout.topMargin: 8
                        visible: win.note !== ""
                        elide: Text.ElideRight
                        text: win.note; color: c.dim; font.family: c.font; font.pixelSize: 11
                    }
                }
                Rectangle { visible: !win.onePane; anchors.right: parent.right; width: 1; height: parent.height; color: c.divider }
            }

            // The open thread, or how many are picked and what can be done to them
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: !win.onePane || win.readerOpen
                Thread {
                    id: reader
                    anchors.fill: parent
                    visible: win.picked.length === 0
                    back: win.onePane
                    onGoBack: { win.readerOpen = false; list.forceActiveFocus() }
                    app: win; c: app.look; nm: app.mailer
                    messages: win.messages
                    htmlMode: win.htmlMode
                    onCycleHtml: win.htmlMode = (win.htmlMode + 1) % 3
                    onOpenBrowser: win.openBrowser()
                    onResumeDraft: win.compose("resume")
                    actions: win.readerActions
                    onAct: id => win.act(id)
                }
                Column {
                    anchors.centerIn: parent
                    visible: win.picked.length > 0
                    spacing: 28
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: win.picked.length + " threads selected"
                        color: c.title; font.family: c.font; font.pixelSize: 22; font.weight: Font.Medium
                    }
                    Column {
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 2
                        Repeater {
                            // A click does what the key does
                            model: [["a", "Archive", "archive"], ["d", win.folders[win.folder].dir === "Trash" ? "Delete for good" : "Move to Trash", "trash"],
                                    ["!", win.folders[win.folder].dir === "Spam" ? "Not spam" : "Spam", "spam"],
                                    ["u", "Read or unread", "unread"], ["Esc", "Select only one", "single"]]
                            delegate: Rectangle {
                                required property var modelData
                                implicitWidth: pickRow.implicitWidth + 24; implicitHeight: 32
                                radius: 8
                                color: ph.hovered ? c.hover : "transparent"
                                HoverHandler { id: ph; cursorShape: Qt.PointingHandCursor }
                                TapHandler { onTapped: { win.act(modelData[2]); list.forceActiveFocus() } }
                                Row {
                                    id: pickRow
                                    x: 12; anchors.verticalCenter: parent.verticalCenter
                                    spacing: 14
                                    Item {
                                        width: 44; height: cap.implicitHeight
                                        KeyCap { id: cap; anchors.right: parent.right; c: win.look; keys: modelData[0]; tint: win.look.faint }
                                    }
                                    Text { anchors.verticalCenter: parent.verticalCenter; text: modelData[1]; color: ph.hovered ? c.text : c.dim; font.family: c.font; font.pixelSize: 13 }
                                }
                            }
                        }
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "Or drag them to a folder"
                        color: c.faint; font.family: c.font; font.pixelSize: 12
                    }
                }
            }
        }

        // What is being dragged: the thread's subject, by the pointer
        Rectangle {
            id: ghost
            visible: win.dragged !== null
            width: Math.min(320, ghostText.implicitWidth + 28); height: 34
            radius: 8
            color: c.solid
            border.color: win.dropFolder >= 0 ? c.primary : c.line
            Text {
                id: ghostText
                anchors.fill: parent; anchors.leftMargin: 14; anchors.rightMargin: 14
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
                text: !win.dragged ? "" : win.dragged.length > 1 ? win.dragged.length + " threads" : win.dragged[0].subject || "(no subject)"
                color: c.title; font.family: c.font; font.pixelSize: 12
            }
        }

        // Settings: one row per choice; ←/→ or a click changes it, Esc or ⌘, closes.
        property bool showSettings: false
        onShowSettingsChanged: if (showSettings) settingsPanel.forceActiveFocus(); else list.forceActiveFocus()
        readonly property var settingRows: [
            { key: "composeFloats", title: "New windows", choices: [[true, "Floating"], [false, "In the grid"]],
              hint: "Where writing and message windows open" },
            { key: "view", title: "Messages open as", choices: [[0, "Text"], [1, "HTML, dark"], [2, "HTML as sent"]],
              hint: "How a message shows first, when it has HTML (h changes it)" },
            { key: "claudeReads", title: "Claude reads", choices: [["thread", "The whole thread"], ["selection", "Only what I select"]],
              hint: "What is sent to Claude when it writes a reply (⌘⇧C)" }
        ]
        AppPanel {
            behind: content
            id: settingsPanel
            visible: win.showSettings
            c: win.look
            spacing: 28
            property int row: 0
            onOutsideTapped: win.showSettings = false
            Keys.onPressed: e => {
                const r = win.settingRows[row]
                const i = r.choices.findIndex(ch => ch[0] === win.settings[r.key])
                if (e.key === Qt.Key_Escape) win.showSettings = false
                else if (e.key === Qt.Key_Down) row = Math.min(row + 1, win.settingRows.length - 1)
                else if (e.key === Qt.Key_Up) row = Math.max(row - 1, 0)
                else if (e.key === Qt.Key_Left && i > 0) win.setting(r.key, r.choices[i - 1][0])
                else if (e.key === Qt.Key_Right && i < r.choices.length - 1) win.setting(r.key, r.choices[i + 1][0])
                else return
                e.accepted = true
            }
            Row {
                width: parent.width
                Text { anchors.verticalCenter: parent.verticalCenter; text: "Settings"; color: c.title; font.family: c.font; font.pixelSize: 15; font.weight: Font.Medium; width: parent.width - escHint.width }
                KeyCap { id: escHint; anchors.verticalCenter: parent.verticalCenter; c: win.look; keys: "esc"; tint: win.look.faint }
            }
            Repeater {
                model: win.settingRows
                delegate: Column {
                    id: settingRow
                    required property var modelData
                    required property int index
                    width: parent.width
                    spacing: 10
                    Text { text: modelData.title; color: index === settingsPanel.row ? c.title : c.text; font.family: c.font; font.pixelSize: 13 }
                    Row {
                        spacing: 8
                        Repeater {
                            model: settingRow.modelData.choices
                            delegate: Rectangle {
                                id: choice
                                required property var modelData
                                readonly property bool on: win.settings[settingRow.modelData.key] === modelData[0]
                                implicitWidth: choiceText.implicitWidth + 32
                                implicitHeight: 34
                                radius: 8
                                color: on ? c.sel : chh.hovered ? c.hover : "transparent"
                                border.color: on ? c.primary : c.line
                                HoverHandler { id: chh; cursorShape: Qt.PointingHandCursor }
                                TapHandler { onTapped: { settingsPanel.row = settingRow.index; win.setting(settingRow.modelData.key, choice.modelData[0]) } }
                                Text { id: choiceText; anchors.centerIn: parent; text: choice.modelData[1]; color: choice.on ? c.title : c.dim; font.family: c.font; font.pixelSize: 12 }
                            }
                        }
                    }
                    Text { text: settingRow.modelData.hint; color: c.faint; font.family: c.font; font.pixelSize: 11 }
                }
            }
        }

        // Asks before what can't be undone (deleting for good): Enter does it, Esc or a click outside doesn't.
        AppPanel {
            behind: content
            id: confirmPanel
            visible: win.confirm !== null
            c: win.look
            cardWidth: 520
            onOutsideTapped: win.confirm = null
            Keys.onPressed: e => {
                if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { const run = win.confirm.run; win.confirm = null; run() }
                else if (e.key === Qt.Key_Escape) win.confirm = null
                e.accepted = true
            }
            Text { text: win.confirm ? win.confirm.title : ""; color: c.title; font.family: c.font; font.pixelSize: 15; font.weight: Font.Medium }
            Text { width: parent.width; wrapMode: Text.Wrap; lineHeight: 1.2; text: win.confirm ? win.confirm.detail : ""; color: c.text; font.family: c.font; font.pixelSize: 12 }
            Row {
                spacing: 18
                AppKeyAction {
                    c: win.look
                    keys: "⏎"; label: win.confirm ? win.confirm.action : ""; color: c.danger; hoverColor: c.title
                    onClicked: { const run = win.confirm.run; win.confirm = null; run() }
                }
                AppKeyAction { c: win.look; keys: "esc"; label: "Cancel"; onClicked: win.confirm = null }
            }
        }

        // Mail's first start, before an account: Enter (or the button) opens Claude Code in a terminal, which sets it up
        // with you by README.md (`nightmail setup`).
        property bool setupStarted: false
        function startSetup() { setupStarted = true; nm.nightmail(["setup"], () => {}) }
        AppPanel {
            behind: content
            id: setupPanel
            visible: win.needsAccount
            c: win.look
            Keys.onPressed: e => {
                if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) win.startSetup()
                e.accepted = true
            }
            Text { text: "Set up your email account"; color: c.title; font.family: c.font; font.pixelSize: 15; font.weight: Font.Medium }
            Text {
                width: parent.width; wrapMode: Text.Wrap; lineHeight: 1.2; color: c.text; font.family: c.font; font.pixelSize: 12
                text: win.setupStarted
                    ? "Claude opens in a terminal and goes through it with you. When it's done, your inbox shows here."
                    : "Mail keeps your mail on this computer, fetched from your provider. Claude can set up the account with you in a terminal, a step at a time: it asks your address and writes the settings. Your password goes only into the login keyring, never to Claude."
            }
            AppKeyAction {
                c: win.look
                keys: "⏎"; label: win.setupStarted ? "Open Claude again" : "Set up with Claude"; color: c.primary; hoverColor: c.title
                onClicked: win.startSetup()
            }
            Text {
                width: parent.width; wrapMode: Text.Wrap; color: c.faint; font.family: c.font; font.pixelSize: 11
                text: "To do it yourself: Mail's README has the steps (plugins/mail/README.md in Nightdrive)."
            }
        }

        property alias cheats: sheet.shown

        readonly property var keyHelp: [
            { title: "Read", keys: [["↑ ↓  j k", "Previous, next"], ["⏎", "Open in a window"], ["Esc  ←", "Back to the list (narrow window)"], ["PgUp PgDn", "In the list alone: a page in it"], ["↑ ↓", "In the thread alone: scroll it"], ["Space ⇧Space  PgDn PgUp", "Page down, up"], ["h", "HTML or text"], ["⇧H", "HTML in the browser"],
                                    ["⌘F  /", "Search"], ["Esc", "Clear the search"]] },
            { title: "Act", keys: [["a", "Archive"], ["d  ⌫", "Move to Trash (in Trash: delete)"], ["!", "Spam (in Spam: not spam)"], ["⌘Z", "Undo"], ["u", "Unread (again: read)"], ["⇧U", "Mark all read"], ["⌘R", "Refresh"],
                                   ["⇧↑ ⇧↓  ⇧-click", "Select several"], ["Ctrl-click", "Select or leave out"], ["⌘A", "Select all"]] },
            { title: "Write", keys: [["⌘N  c", "New message"], ["r", "Reply to all"], ["⇧R", "Reply to the sender only"], ["f", "Forward"],
                                     ["⏎", "Continue a draft (in Drafts)"], ["⌘⇧C", "Claude writes the reply"], ["⌘⇧C", "…from the selected text"],
                                     ["⌘⇧A", "Attach files"], ["Ctrl ⏎", "Send"], ["⌘S", "Save in Drafts"], ["Esc", "Close (Esc Esc: throw away)"]] },
            { title: "Folders", keys: [["Ctrl ↑ ↓", "Previous, next"], ["1 – 6", "Go to a folder"], ["↑ ↓", "In the folders: previous, next"], ["Tab ⇧Tab", "To the folders, and back"], ["Ctrl Tab  Ctrl ⇧Tab", "Next, previous account"], ["⌘⇧⌫", "Empty Trash"], ["⌘B", "Hide or show"], ["⌘,", "Settings"]] }
        ]

        KeySheet { id: sheet; c: win.look; groups: win.keyHelp }
    }

    // Writing opens in a window of its own. To float (the default), its size is fixed while it opens, which tiling
    // compositors (Hyprland, Sway) take as a dialog and float; then it is freed so the window can be resized. Set to open
    // in the grid, its size is free from the start and the compositor tiles it.
    FloatingWindow {
        id: composeWin
        property bool done: false
        property bool opening: false
        onOpeningChanged: if (opening && !win.settings.composeFloats) opening = false
        visible: false
        minimumSize: opening ? Qt.size(implicitWidth, implicitHeight) : Qt.size(360, 400)
        maximumSize: opening ? Qt.size(implicitWidth, implicitHeight) : Qt.size(0, 0)
        Timer { id: release; interval: 400; onTriggered: composeWin.opening = false }
        title: composer.heading
        implicitWidth: 760
        implicitHeight: 720
        color: c.bg
        onVisibleChanged: {
            if (visible) { done = false; release.restart() }
            // Closed by the compositor (⌘W): nothing written is lost, so anything written goes to Drafts.
            else if (!done && (composer.draftId !== "" || !composer.untouched())) win.saveDraft(composer.fields(), true)
            else if (!done) win.composeEnded()
        }
        Compose {
            id: composer
            anchors.fill: parent
            c: c
            onSend: f => win.sendMail(f)
            onSuggest: request => win.suggest(request)
            claudeReads: win.settings.claudeReads || ""
            accounts: win.accounts
            onChooseReads: v => win.setting("claudeReads", v)
            onSave: (f, close) => win.saveDraft(f, close)
            onDismiss: win.dismissCompose()
            onPickFiles: nm.pick(paths => composer.attach(paths))
        }
    }

    // A message window: the thread, with the reading keys and replies of its own. Esc or ⌘W closes it.
    Component {
        id: messageWindow
        FloatingWindow {
            id: mw
            property var msgs: []
            property int htmlMode: win.settings.view
            property bool opening: win.settings.composeFloats
            title: msgs.length ? msgs[0].subject || "(no subject)" : "Message"
            implicitWidth: 820
            implicitHeight: 900
            minimumSize: opening ? Qt.size(implicitWidth, implicitHeight) : Qt.size(360, 300)
            maximumSize: opening ? Qt.size(implicitWidth, implicitHeight) : Qt.size(0, 0)
            Timer { running: true; interval: 400; onTriggered: mw.opening = false }
            color: c.bg
            visible: true
            onClosed: destroy()
            function scroll(dy) { thread.cancelFlick(); thread.contentY = Math.max(0, Math.min(thread.contentHeight - thread.height, thread.contentY + dy)) }

            Thread {
                id: thread
                anchors.fill: parent
                app: win; c: app.look; nm: app.mailer
                messages: mw.msgs
                htmlMode: mw.htmlMode
                onCycleHtml: mw.htmlMode = (mw.htmlMode + 1) % 3
                onOpenBrowser: win.openBrowser(mw.msgs)
                onResumeDraft: win.compose("resume", mw.msgs)
                actions: win.windowActions
                onAct: id => win.act(id, mw.msgs)
                focus: true
                Keys.onPressed: e => {
                    const k = e.key
                    keys.pressed(e)             // ? and Ctrl+? show and hide the keys
                    if (k === Qt.Key_Question) {}
                    else if (thread.isCopy(e)) thread.copy()
                    else if (k === Qt.Key_Escape) mw.visible = false
                    else if (k === Qt.Key_Down) mw.scroll(win.arrowStep)
                    else if (k === Qt.Key_Up) mw.scroll(-win.arrowStep)
                    else if (k === Qt.Key_Space) mw.scroll((e.modifiers & Qt.ShiftModifier ? -1 : 1) * (thread.height - 80))
                    else if (k === Qt.Key_H && e.modifiers & Qt.ShiftModifier) win.openBrowser(mw.msgs)
                    else if (k === Qt.Key_H) mw.htmlMode = (mw.htmlMode + 1) % 3
                    else if (k === Qt.Key_R) win.compose(e.modifiers & Qt.ShiftModifier ? "reply" : "all", mw.msgs)
                    else if (k === Qt.Key_F) win.compose("forward", mw.msgs)
                    else return
                    e.accepted = true
                }
            }
            Shortcut { sequences: ["Meta+Shift+C", "Ctrl+Shift+C"]; onActivated: win.compose("claude", mw.msgs) }
            KeySheet {
                id: keys
                c: win.look
                groups: [
                    { title: "Read", keys: [["↑ ↓", "Scroll"], ["Space ⇧Space", "Page down, up"], ["h", "HTML or text"], ["⇧H", "HTML in the browser"], ["Esc  ⌘W", "Close the window"]] },
                    { title: "Write", keys: [["r", "Reply to all"], ["⇧R", "Reply to the sender only"], ["f", "Forward"], ["⌘⇧C", "Claude writes the reply"]] }
                ]
            }
            onVisibleChanged: if (!visible) destroy()
        }
    }
}
