import QtQuick

// What the search (/ or ⌘F) looks in, and where each thread it found is (#3655). By default it looks in the whole
// account shown, every folder but Spam and Trash (their mail is what you didn't want); ⌥F, or the switch under the
// search, keeps it to the folder picked, as before, which is also how Spam and Trash are searched. Picking a folder
// clears the search and sets it back to all folders.
//
// Each thread found in all folders gets home: the index in win.folders of the folder its matched messages are in, which
// the list shows by the subject and which the keys act on (Actions.qml), as if that folder were picked. Apart from
// shell.qml, which holds the rest of the window's state.
QtObject {
    id: finder
    required property var win
    readonly property var nm: win.mailer

    readonly property string text: win.search ? win.search.text.trim() : ""
    readonly property bool on: text !== ""
    property bool all: true             // the scope: the account's folders, or only the one picked
    readonly property bool wide: on && all
    onOnChanged: if (!on) all = true

    // The folders all folders means, and which one a thread found in several shows as: a received message in the inbox
    // or Archive before your reply to it in Sent. Their queries together hold every one of Mail's folders but Spam and
    // Trash, so a message in a folder of the server's that Mail doesn't show isn't found either.
    readonly property var homes: ["INBOX", "Archive", "Drafts", "Sent"].map(d => win.folders.findIndex(f => f.dir === d))

    function scope() {
        return wide ? "(" + homes.map(i => win.folderQuery(i)).join(" or ") + ")" : win.folderQuery(win.folder)
    }
    function query() { return on ? "(" + scope() + ") and (" + text + ")" : win.folderQuery(win.folder) }

    function toggle() {
        if (!on) return
        all = !all
        win.reload(false)
    }
    // ⌥F with a Mac layout's level-3 ⌥ (kit/AppOption.qml), which the window's Alt+F never sees: from the search field
    // and the list's keys (ThreadList.qml, ListKeys.qml). True when it took the key
    function optionKey(e) {
        if (!on || !win.option.level3(e) || win.option.key(e) !== Qt.Key_F) return false
        toggle()
        e.accepted = true
        return true
    }

    // The threads of query(), each with its home when the search is wide. One count per folder (4 more notmuch runs,
    // each only the threads' ids), so a list of hundreds costs the same as one of ten. A thread none of them names (a sync
    // moved it in between) keeps the folder picked: the next reload puts it right.
    function threads(done) {
        const q = query()
        nm.search(q, list => {
            if (!wide || !list.length) { done(list); return }
            const found = {}
            let left = homes.length
            for (const i of homes) {
                const f = i
                nm.run(["search", "--output=threads", "(" + q + ") and " + win.folderQuery(f)], out => {
                    found[f] = out.split("\n").filter(x => x).map(x => x.replace(/^thread:/, ""))
                    if (--left) return
                    for (const t of list) {
                        const h = homes.find(n => found[n].indexOf(t.thread) >= 0)
                        t.home = h === undefined ? win.folder : h
                    }
                    done(list)
                })
            }
        })
    }

    // The folder a thread in the list is in: its home in a wide search, else the one picked
    function homeOf(t) { return wide && t && t.home !== undefined ? t.home : win.folder }
}
