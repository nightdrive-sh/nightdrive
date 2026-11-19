import QtQuick
import Quickshell
import Quickshell.Io

// The messages as `nightdrive inbox list --json` gives them (config/inbox: newest first, each with its sender's keys,
// and the senders for the sidebar), narrowed there by the view, the sender picked and the search, and the open one
// whole from `show --json`. Nothing about a message is worked out here: the command decides, the window shows. The list
// is read again every few seconds (a session may leave a message at any time, and Quickshell has no folder watcher) and
// at once after a change made here; the same answer again changes nothing, so the rows and their scroll stay.
Item {
    id: store
    // The core's command, by its path from the plugin's app/: the window may start without ~/.local/bin in its PATH
    readonly property string cli: Quickshell.shellDir + "/../../../config/inbox/cli.py"
    readonly property var command: ["python3", cli]

    property string view: "inbox"              // inbox | unread | archive (the sidebar's first rows)
    property string from: ""                   // a sender key ("project:dotfiles", "app:Recorder", "session:…"), "" all
    property string fromLabel: ""              // what the sidebar or the message called it
    property string search: ""                 // the search field's words
    readonly property string scopeName: from ? fromLabel : view === "archive" ? "Archive" : view === "unread" ? "Unread" : "Inbox"

    property var messages: []                  // list's rows: id, title, at, updated, read, from, task, sender, counts
    property var senders: []                   // { key, kind, label, unread, total }
    property int unread: 0                     // in the inbox, whatever is shown
    property bool loaded: false
    property string error: ""
    property string picked: ""
    readonly property int index: messages.findIndex(m => m.id === picked)
    property var message: null                 // the picked one, whole (show --json): body, attachments, actions

    function pickView(v) { view = v; from = ""; fromLabel = ""; reload() }
    function pickFrom(key, label) { from = key; fromLabel = label; reload() }
    function setSearch(words) { if (words !== search) { search = words; reload() } }
    // Another scope: its newest message picked once it has come
    function reload() { picked = ""; message = null; raw = ""; refresh() }
    function step(d) { const n = messages.length; if (n) picked = messages[Math.max(0, Math.min(n - 1, index + d))].id }
    function pickAt(i) { if (messages.length) picked = messages[Math.max(0, Math.min(messages.length - 1, i))].id }
    // Gone from what is shown (archived, deleted): the one below it next, else the one above
    function forget(id) {
        const i = messages.findIndex(m => m.id === id)
        messages = messages.filter(m => m.id !== id)
        if (picked === id) picked = messages.length ? messages[Math.min(Math.max(i, 0), messages.length - 1)].id : ""
        raw = ""
        refresh()
    }
    // Picked (`inbox show ID`): from the inbox, or the archive it is in, every sender shown
    function follow(id, archived) {
        view = archived ? "archive" : "inbox"; from = ""; fromLabel = ""; search = ""
        picked = id; raw = ""; refresh()
    }

    function listArgs() {
        const a = ["list", "--json", "--limit", "0"]
        if (view === "archive") a.push("--archived")
        if (view === "unread") a.push("--unread")
        if (from) a.push("--from", from)
        if (search.trim()) a.push("--search", search.trim())
        return a
    }
    property bool again: false
    property string raw: ""
    function refresh() { if (!lister.running) { lister.command = command.concat(listArgs()); lister.running = true } else again = true }

    Process {
        id: lister
        stdout: StdioCollector {
            onStreamFinished: {
                if (store.again || text === store.raw) return
                store.raw = text
                try {
                    const r = JSON.parse(text)
                    store.messages = r.messages
                    store.senders = r.senders
                    store.unread = r.unread
                    store.error = ""
                    // A sender no longer there (its last message archived): every sender again
                    if (store.from && !r.senders.some(s => s.key === store.from) && !store.from.startsWith("session:")
                        && store.from !== "claude") {
                        store.from = ""; store.fromLabel = ""; store.raw = ""; store.again = true
                    }
                } catch (e) {
                    store.error = "The messages couldn't be read: " + e
                }
                store.loaded = true
                if (store.index < 0) store.picked = store.messages.length ? store.messages[0].id : ""
                else store.load()                   // the open one may have been added to (inbox update)
            }
        }
        stderr: StdioCollector { onStreamFinished: if (text.trim()) store.error = text.trim().split("\n").pop() }
        onExited: if (store.again) { store.again = false; store.refresh() }
    }

    // The picked message, whole; read after it has been open a moment, so stepping past one leaves it unread
    onPickedChanged: { message = null; readTimer.stop(); load() }
    function load() {
        if (!picked) return
        shower.command = command.concat(["show", "--json", picked])
        shower.running = true
    }
    Process {
        id: shower
        stdout: StdioCollector {
            onStreamFinished: {
                let m = null
                try { m = JSON.parse(text) } catch (e) {}
                if (!m || m.id !== store.picked) return
                // The same message as shown (a list read again): left alone, so its images don't load again
                if (store.message && JSON.stringify(store.message) === JSON.stringify(m)) return
                store.message = m
                if (!m.read && !m.archived) readTimer.restart()
            }
        }
    }
    readonly property int readAfter: 1200      // ms: long enough to have looked, short enough not to wait for
    Timer {
        id: readTimer
        interval: store.readAfter
        onTriggered: if (store.message && !store.message.read) store.mark(store.message.id, true)
    }
    function mark(id, read) {
        marker.command = command.concat(["read", "--json", id].concat(read ? [] : ["--unread"]))
        marker.running = true
    }
    Process { id: marker; onExited: { store.raw = ""; store.refresh() } }

    Timer { interval: 4000; running: true; repeat: true; onTriggered: store.refresh() }
    Component.onCompleted: refresh()
}
