import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs
import qs.kit
import "sender.js" as Sender
import "links.js" as Links
import "fresh.js" as Fresh

// Nightdrive Mail: folders, thread list and the open thread, over notmuch.
// This file holds the window's state (account, folder, threads, the open and picked ones), reading them over notmuch
// and laying the parts out. The parts are files of their own: FolderSidebar, ThreadList (ThreadRow, ListKeys),
// PickedPane, the panels (SettingsPanel, ConfirmPanel, SetupPanel), ComposeWindow and MessageWindow; acting on threads
// is Actions.qml, writing Writing.qml, IPC MailIpc.qml.
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
        onClosed: { outbox.jobs = outbox.jobs.filter(j => j.state === "sending"); writer.composeEnded() }
        // Started for a new message alone (`nightmail new` or a mailto: link with Mail closed), only the writing window
        // shows, and Mail quits when it closes (composeEnded); `nightmail open` shows this one over IPC (reveal).
        visible: Quickshell.env("NIGHTMAIL_COMPOSE_ONLY") !== "1"

        // The look, as Deck's: the apps' kit (kit/AppLook.qml)
        AppLook { id: c }
        AppOption { id: optionKeys }

        Notmuch { id: nm }
        // The sidebar's spinner while mail is fetched (FetchWatch.qml); what came in shows at once, not at the timer
        FetchWatch { id: fetchWatch; onEnded: win.needsAccount ? win.loadAccounts() : win.reload(true) }
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
                const composer = writer.composer
                composer.start(job.heading, job.f)
                composer.replyId = job.replyId; composer.forwardId = job.forwardId
                composer.failed = true; composer.status = job.error
                writer.showCompose()
            }
            onIdle: writer.composeEnded()
        }
        // Nightdrive Contacts' people, when it is installed: addresses to complete, a sender's card (ContactBook.qml)
        readonly property ContactBook book: ContactBook {}
        // The calendar an invitation goes in (Invitation.qml): the one picked last, for the next one
        property string inviteCalendar: ""
        // For components in their own files, which don't see this file's ids.
        readonly property QtObject look: c
        readonly property QtObject option: optionKeys      // ⌥ + a character with a Mac layout (Search.optionKey)
        readonly property QtObject mailer: nm
        // The thread list and its search (ThreadList.qml), which most of what is below moves and reads
        readonly property ListView list: threadList.list
        readonly property Item search: threadList.search

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

        MailIpc { win: win; writer: writer; fetchWatch: fetchWatch }

        // @NAME in a query is the account's folder NAME (folderQuery)
        readonly property var folders: [
            { name: "Inbox", dir: "INBOX", glyph: "inbox", query: "@INBOX and tag:inbox" },
            { name: "Sent", dir: "Sent", glyph: "send", query: "@Sent" },
            // Drafts are read: the sidebar counts them all, as Apple Mail does, where the others count the unread (all)
            { name: "Drafts", dir: "Drafts", glyph: "file-pen", query: "@Drafts", all: true },
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
        property var allCounts: ({})        // the messages in the folders marked all (Drafts), by index

        // The search: all the account's folders but Spam and Trash, or only the one picked (Search.qml, #3655)
        Search { id: finder; win: win }
        readonly property QtObject searcher: finder     // for the parts in their own files
        function query() { return finder.query() }
        function homeOf(t) { return finder.homeOf(t) }

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
        // After each reload's list: the message windows look whether their thread has grown (MessageWindow.qml)
        signal reloaded()
        function reload(keep, at) {
            const was = keep && current >= 0 ? threads[current] : undefined
            const id = was ? was.thread : ""
            finder.threads(list => {
                win.reloaded()
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
                else if (Fresh.changed(was, list[i])) refresh(i)
            })
            for (let f = 0; f < folders.length; f++) {
                const n = f
                nm.run(["count", "--output=threads", "(" + folderQuery(f) + ") and tag:unread"], t => {
                    const u = Object.assign({}, unreadCounts); u[n] = parseInt(t) || 0; unreadCounts = u
                })
                // Messages, not threads: a draft is one message, and two replies drafted in one thread are two
                if (folders[f].all)
                    nm.run(["count", "--output=messages", folderQuery(f)], t => {
                        const u = Object.assign({}, allCounts); u[n] = parseInt(t) || 0; allCounts = u
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
            picked = []; anchorId = ""; marking = false
            seen.forget()
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
                    finder.threads(list => {
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


        // The open thread's messages read again where it stays open (a reply sent, a message a sync brought: fresh.js),
        // without open()'s marking read and view reset.
        function refresh(i) {
            if (listOnly || i < 0) return
            const id = threads[i].thread
            nm.show(id, m => {
                if (!m.length || !threads[current] || threads[current].thread !== id) return
                const was = messages
                messages = m
                seen.arrived(was, m)
            })
        }
        // What a refresh brought is marked read once the thread can be seen in the active window (SeenOnShow.qml)
        SeenOnShow { id: seen; nm: nm; shown: reader.visible && reader.Window.active; onMarked: win.reload(true) }

        // Writing (Writing.qml) and its window (ComposeWindow.qml). compose and mailtoFields stay callable here: the
        // keys, IPC and Thread.qml's links (app.compose) ask for them on the window.
        Writing { id: writer; win: win; composeWin: composeWin; outbox: outbox }
        function compose(mode, msgs, fields) { writer.compose(mode, msgs, fields) }
        function mailtoFields(url) { return writer.mailtoFields(url) }

        // A thread in a window of its own (a double click or Enter in the list): it floats or tiles like the writing
        // window, and keeps its own keys.
        function openWindow(i) {
            const t = threads[i]
            if (!t) return
            nm.show(t.thread, m => { if (m.length) messageWindow.createObject(shell, { msgs: m, threadId: t.thread, win: win, ops: ops }) })
        }

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
        // Saving goes straight to the downloads folder, without asking (#3627); the toast says where, with Open and Show
        // in folder, and no folder opens by itself
        function savePart(msg, f) { nm.part("save", msg.id, f.part, f.name, r => saved(r.error, r.path ? [r.path] : [])) }
        function saveAll(msg) { nm.saveAll(msg.id, msg.files, r => saved(r.error, r.paths || [])) }
        function saved(error, paths) {
            if (error || !paths.length) { say(error || "Nothing was saved", { danger: true }); return }
            const home = Quickshell.env("HOME")
            const dir = paths[0].replace(/\/[^\/]*$/, "").replace(home, "~")
            const show = { label: "Show in folder", run: () => nm.showSaved(paths) }
            if (paths.length === 1)
                say("Saved " + paths[0].replace(/^.*\//, "") + " to " + dir,
                    { actions: [{ label: "Open", run: () => Qt.openUrlExternally("file://" + paths[0].split("/").map(encodeURIComponent).join("/")) }, show] })
            else say("Saved " + paths.length + " attachments to " + dir, { actions: [show] })
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
            current = i; marking = false
        }
        // v marks the thread the keyboard is on (or unmarks it) and goes on to the next, as in Files. While marking,
        // j k move the keyboard and keep the marks (ListKeys.qml); any other way of opening a thread drops them. With
        // the last mark gone the next thread opens, so the keys never act on one that isn't shown.
        property bool marking: false
        function markNext() {
            const t = threads[current]
            if (!t) return
            const next = Math.min(current + 1, threads.length - 1)
            picked = isPicked(t) ? picked.filter(p => p !== t.thread) : picked.concat([t.thread])
            if (!picked.length) { open(next); return }
            anchorId = t.thread; marking = true; current = next
        }
        function moveMarking(i) { if (i >= 0 && i < threads.length) current = i }
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

        // Moving, deleting, read and unread, ⌘Z and dragging to a folder (Actions.qml)
        Actions { id: ops; win: win; sidebar: sidebar; outDrag: outDrag }
        // Deleting for good asks first (ConfirmPanel.qml): { title, detail, action, run }
        property var confirm: null
        onConfirmChanged: if (confirm) confirmPanel.forceActiveFocus(); else list.forceActiveFocus()

        // What just happened, in the kit's toast at the top of the window (a line under the list went unnoticed);
        // say("") takes it away; opts are AppToast.show's (danger: a failure, which stays longer)
        function say(t, opts) { toast.show(t, opts) }

        // Opens the thread of a message in the inbox (or wherever it is now, if it has left it), then calls then().
        function openMessage(id, then) {
            const q = "id:\"" + id + "\""
            nm.run(["search", "--output=files", "--exclude=false", q], files => {
                // …/<account>/<folder>/cur/<file>: the account shown becomes the message's (the one whose inbox has it,
                // when it was mailed between two of your accounts)
                // (paths, not list: that name is the thread list's id, which forceActiveFocus() below needs)
                const paths = files.split("\n").filter(f => f !== "")
                const m = (paths.find(f => /\/INBOX\/(cur|new)\//.test(f)) || paths[0] || "").match(/([^\/]+)\/([^\/]+)\/(cur|new)\/[^\/]+$/)
                if (!m) { say("That message is gone"); return }
                const a = accounts.findIndex(x => x.maildir === m[1])
                if (a >= 0 && a !== acct) { acct = a; setting("account", accounts[a].id) }
                nm.run(["search", "--output=threads", "--exclude=false", q], t => {
                    const thread = t.trim().replace(/^thread:/, "")
                    folder = 0
                    search.text = ""
                    finder.threads(list => {
                        let i = list.findIndex(x => x.thread === thread)
                        if (i < 0) {
                            // Not in the inbox any more: its thread, searched for in the folder the message is in now
                            // (the inbox's folder without the inbox tag is Archive).
                            const f = folders.findIndex((x, n) => n > 0 && x.dir === (m[2] === "INBOX" ? "Archive" : m[2]))
                            folder = f >= 0 ? f : folders.findIndex(x => x.name === "Archive")
                            // in that folder alone, as Spam and Trash aren't in a search of all folders
                            search.text = "thread:" + thread
                            finder.all = false
                            finder.threads(l2 => { threads = l2; open(l2.length ? 0 : -1, then) })
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

        // The region's way (Settings › Region): 9:30 today, Yesterday, Tue, 28.10.; in full in the read view
        function when(ts) { return Regional.relative(new Date(ts * 1000)) }
        function fullDate(ts) {
            const d = new Date(ts * 1000)
            return Regional.format(d, "long") + ", " + Regional.format(d, "time")
        }
        // A sender's name and address (sender.js: a name may hold text that looks like a tag)
        function name(from) { return Sender.name(from) }
        function address(from) { return Sender.address(from) }
        // Plain text to rich text: links clickable, quoted lines quiet (links.js)
        function rich(t) { return Links.rich(t, c.accent, c.faint) }

        Component.onCompleted: {
            // Marks of mark-all-read steps that can't be undone any more (the last run's)
            nm.run(["search", "--output=tags", "tag:/^" + ops.undoTag + "/"], t => {
                const old = t.split("\n").filter(x => x.indexOf(ops.undoTag) === 0)
                if (old.length) nm.tag(old.map(x => "-" + x), old.map(x => "tag:" + x).join(" or "))
            })
            loadAccounts()
            fetchWatch.check()
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
        Shortcut { sequences: ["/", "Ctrl+F"]; onActivated: win.search.forceActiveFocus() }
        // ⌥F: the search in all folders, or only the one picked (Search.qml)
        Shortcut { sequence: "Alt+F"; enabled: finder.on; onActivated: finder.toggle() }
        Shortcut { sequences: ["Meta+Shift+C", "Ctrl+Shift+C"]; onActivated: win.compose("claude") }
        // ⌘R fetches new mail now (`nightmail sync`, which shows it once indexed), as Mac Mail's Get New Mail
        Shortcut { sequence: "Ctrl+R"; onActivated: { win.reload(true); nm.nightmail(["sync"]) } }
        Shortcut { sequences: ["Ctrl+N", "Meta+N"]; onActivated: win.compose("new") }
        Shortcut { sequence: "Ctrl+Q"; onActivated: Qt.quit() }
        Shortcut { sequences: ["Meta+,", "Ctrl+,"]; onActivated: win.showSettings = !win.showSettings }
        Shortcut { sequence: "Ctrl+Z"; onActivated: ops.undo() }
        Shortcut { sequences: ["Ctrl+B", "Meta+B"]; onActivated: win.foldersChoice = !win.showFolders }

        RowLayout {
            id: content          // what a panel turns off while it shows (AppPanel.behind)
            anchors.fill: parent
            // ? and Ctrl+? show the keys (KeySheet.qml)
            Keys.onPressed: e => sheet.pressed(e)
            AppPointer { c: win.look }      // the pointer hides the keys' frame
            spacing: 0

            FolderSidebar {
                id: sidebar
                win: win; ops: ops; panes: panes; outbox: outbox
                fetching: fetchWatch.fetching
                onSettings: win.showSettings = true
            }

            ThreadList { id: threadList; win: win; ops: ops; writer: writer; panes: panes; sheet: sheet; reader: reader }

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
                    onGoBack: { win.readerOpen = false; win.list.forceActiveFocus() }
                    app: win; c: app.look; nm: app.mailer
                    messages: win.messages
                    htmlMode: win.htmlMode
                    onCycleHtml: win.htmlMode = (win.htmlMode + 1) % 3
                    onOpenBrowser: win.openBrowser()
                    onResumeDraft: draftId => win.compose("resume", null, { id: draftId })
                    onTrashDraft: draftId => ops.trashDraft(draftId)
                    actions: ops.readerActions
                    onAct: id => ops.act(id)
                }
                PickedPane { win: win; ops: ops }
            }
        }

        DragGhost { ops: ops; c: win.look }
        // Threads dragged out of the window, as a line Claude reads them by (OutDrag.qml, #3611)
        OutDrag { id: outDrag; c: win.look }

        // Settings (SettingsPanel.qml), confirming a delete for good (ConfirmPanel.qml) and the first start (SetupPanel.qml)
        property bool showSettings: false
        onShowSettingsChanged: if (showSettings) settingsPanel.forceActiveFocus(); else list.forceActiveFocus()
        SettingsPanel { id: settingsPanel; behind: content; win: win }
        ConfirmPanel { id: confirmPanel; behind: content; win: win }
        SetupPanel { id: setupPanel; behind: content; win: win }
        AppToast { id: toast; c: win.look }

        property alias cheats: sheet.shown

        readonly property var keyHelp: [
            { title: "Read", keys: [["↑ ↓  j k", "Previous, next"], ["⏎  o  l", "Open in a window"], ["Esc  ←", "Back to the list (narrow window)"], ["PgUp PgDn", "In the list alone: a page in it"], ["↑ ↓", "In the thread alone: scroll it"], ["Space ⇧Space  PgDn PgUp", "Page down, up"], ["h", "HTML or text"], ["⇧H", "HTML in the browser"],
                                    ["⌘F  /", "Search all folders but Spam, Trash"], ["⌥F  Tab", "Search only this folder, or all"], ["Esc", "Clear the search"]] },
            { title: "Act", keys: [["a", "Archive"], ["d  ⌫  ⌘⌫", "Move to Trash (in Trash: delete)"], ["!", "Spam (in Spam: not spam)"], ["⌘Z", "Undo"], ["u", "Unread (again: read)"], ["⇧U", "Mark all read"], ["⌘R", "Fetch new mail"],
                                   ["v", "Select, and on to the next"], ["⇧↑ ⇧↓  ⇧-click", "Select several"], ["Ctrl-click", "Select or leave out"], ["⌘A", "Select all"]] },
            { title: "Write", keys: [["⌘N  c  n", "New message"], ["r", "Reply to all"], ["⇧R", "Reply to the sender only"], ["f", "Forward"],
                                     ["⏎", "Continue a draft (in Drafts)"], ["⌘⇧C", "Claude writes the reply"], ["⌘⇧C", "…from the selected text"],
                                     ["⌘⇧A", "Attach files"], ["⌘V", "Paste: copied files are attached"],
                                     ["Ctrl ⏎", "Send"], ["⌘S", "Save in Drafts"], ["Esc", "Close (Esc Esc: throw away)"]] },
            { title: "Folders", keys: [["Ctrl ↑ ↓", "Previous, next"], ["1 – 6", "Go to a folder"], ["↑ ↓", "In the folders: previous, next"], ["Tab ⇧Tab", "To the folders, and back"], ["Ctrl Tab  Ctrl ⇧Tab", "Next, previous account"], ["⌘⇧⌫", "Empty Trash (in Spam: Spam)"], ["⌘B", "Hide or show"], ["⌘,", "Settings"]] }
        ]

        KeySheet { id: sheet; c: win.look; groups: win.keyHelp }
    }

    ComposeWindow { id: composeWin; win: win; writer: writer }

    // win and ops are given as it opens (openWindow): bound here, they came out undefined in the window
    Component { id: messageWindow; MessageWindow {} }
}
