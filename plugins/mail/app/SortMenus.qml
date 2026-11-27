import QtQuick
import qs.kit

// Your own folders' menus and questions (#3733): a thread's menu (a right click on a row) and m's, a folder's menu
// (a right click on one of yours), and the name of a new folder. Moving into one of your folders sorts the sender
// there from now on, as a drag does (Actions.sortInto); there is no "always move" of its own. Apart from Actions.qml,
// which does the moving, and shell.qml, which holds the menu and the prompt (menu, prompt).
QtObject {
    id: menus
    required property var win
    required property var ops
    required property Item menu         // the kit's AppMenu
    required property Item prompt       // the kit's AppPrompt
    readonly property var sorter: win.sorter

    // The address of the newest message in msgs that isn't from you
    function senderOf(msgs) {
        const mine = win.accounts.map(a => (a.address || "").toLowerCase())
        const theirs = msgs.slice().sort((a, b) => b.timestamp - a.timestamp)
            .map(m => (win.address(m.from) || m.from).trim().toLowerCase())
            .filter(a => a.indexOf("@") > 0 && mine.indexOf(a) < 0)
        return theirs.length ? theirs[0] : ""
    }

    // ts: the threads it acts on (the picked ones, or the one under the pointer); home: the folder they are in. The
    // thread is read for its sender without being opened, so nothing is marked read.
    function threadMenu(anchor, ts) {
        if (!ts.length) return
        const home = win.homeOf(ts[0])
        win.mailer.show(ts[0].thread, msgs => {
            const items = []
            const inOwn = win.folders[home] && win.folders[home].own
            // Back to the inbox from one of your folders: its sender's rule ends, as a drag there ends it
            if (inOwn) items.push({ text: "Inbox", section: "Move to", run: () => ops.unsort(ts) })
            win.folders.forEach((f, i) => {
                if (f.own && i !== home) items.push({ text: f.name, section: "Move to", run: () => ops.sortInto(i, ts) })
            })
            const addr = senderOf(msgs), rule = addr ? sorter.ruleFor(win.account.id, addr) : null
            const domain = addr.split("@")[1] || ""
            if (inOwn && addr && ts.length === 1) {
                if (!(rule && rule.domain) && sorter.publicDomains.indexOf(domain) < 0)
                    items.push({ text: "All mail from " + domain + " here", section: win.folders[home].name, run: () => ops.sortInto(home, ts, true) })
                if (rule)
                    items.push({ text: "Stop sorting " + sorter.describe(rule), section: win.folders[home].name, run: () => ops.stopSorting(rule) })
            }
            items.push({ text: "New folder…", detail: "and move there", section: " ", run: () => newFolder(i => ops.sortInto(i, ts)) })
            menu.title = ts.length > 1 ? ts.length + " threads" : ts[0].subject
            menu.hint = "The sender's later mail goes the same way"
            menu.open(anchor, items)
        })
    }
    // m: the open thread's (or the picked ones') menu, at its row
    function moveMenu() {
        const ts = win.targets()
        if (!ts.length) return
        threadMenu(win.list.itemAtIndex(win.current) || win.list, ts)
    }

    // A right click on one of your folders
    function folderMenu(anchor, i) {
        const f = win.folders[i]
        if (!f || !f.own) return
        menu.title = f.name
        menu.hint = ""
        menu.open(anchor, [{ text: "Delete folder…", run: () => askDelete(i) },
                           { text: "New folder…", run: () => newFolder() }])
    }
    function askDelete(i) {
        const f = win.folders[i], acc = win.account
        const rules = sorter.rules.filter(r => r.account === acc.id && r.folder === f.dir)
        win.mailer.run(["count", "--output=threads", "--exclude=false", win.folderQuery(i)], out => {
            const n = parseInt(out) || 0
            win.confirm = {
                title: "Delete the folder " + f.name + "?",
                detail: (n ? (n === 1 ? "Its thread goes" : "Its " + n + " threads go") + " back to the inbox, unannounced. " : "")
                        + (rules.length ? "Mail from " + rules.map(r => sorter.describe(r)).join(", ") + " comes to the inbox again. " : "")
                        + "The folder is deleted on the server (" + acc.address + ") too. This can't be undone.",
                action: "Delete folder",
                run: () => {
                    win.say("Deleting " + f.name + "…", { sticky: true })
                    sorter.remove(acc.id, f.dir, r => {
                        if (r.error) { win.say(r.error, { danger: true }); return }
                        win.reload(false)       // the folder on show is still there, or it is Inbox (shell.qml)
                        win.say("Deleted " + f.name + (r.moved ? ": " + r.moved + " messages back in the inbox" : ""))
                    })
                }
            }
        })
    }

    // The name of a new folder in the account shown; then(i) once it is among the folders (a move into it)
    function newFolder(then) {
        const acc = win.account
        prompt.ask("New folder (" + acc.address + ")", "", name => {
            if (!name) return
            sorter.create(acc.id, name, r => {
                if (r.error) { win.say(r.error, { danger: true }); return }
                win.say("Made " + r.folder + ": mail dragged into it brings its sender's mail there from now on")
                // The folders have been read again (Sorting.create), so it is among them
                const i = win.folders.findIndex(f => f.own && f.dir === r.folder)
                win.reload(true)
                if (then && i >= 0) then(i)
            })
        })
    }
}
