import QtQuick
import Quickshell
import Quickshell.Io

// Saving and deleting: lib/edit.py writes the card in the account's folder, then `contacts sync ACCOUNT` takes it to the
// server at once (the sync's own lock keeps it from meeting the timer's). The sync asks the window to read the contacts
// again when it's done, so a change made on the phone meanwhile shows too.
Item {
    id: store
    required property var app           // the window: accounts, say(), saved(), failed()
    readonly property string editor: Quickshell.shellDir + "/../lib/edit.py"
    property var waiting: []             // accounts to sync once the sync running now is done
    property string waitingWhat: ""
    property var forced: []              // [[account]] emptied by a delete, to sync with --force-delete after it

    function accountName(id) { return (app.accounts.find(a => a.id === id) || { name: id }).name }

    function save(draft) {
        saver.account = draft.account
        saver.command = ["python3", editor, "save", JSON.stringify(draft)]
        saver.running = true
    }
    Process {
        id: saver
        property string account: ""
        stdout: StdioCollector { id: savedOut }
        stderr: StdioCollector { id: saveErr }
        onExited: code => {
            if (code !== 0) { store.app.failed(saveErr.text.trim() || "Couldn't save the contact."); return }
            let id = ""
            try { id = JSON.parse(savedOut.text).id } catch (e) {}
            store.app.saved(id)
            store.sync([saver.account], "Saved")
        }
    }

    // ids: the cards to delete, one a person may have in several accounts
    function remove(ids) {
        deleter.accounts = [...new Set(ids.map(i => i.split("/")[0]))]
        deleter.command = ["python3", editor, "delete"].concat(ids)
        deleter.running = true
    }
    Process {
        id: deleter
        property var accounts: []
        stdout: StdioCollector { id: emptied }
        stderr: StdioCollector { id: deleteErr }
        onExited: code => {
            if (code !== 0) { store.app.say(deleteErr.text.trim() || "Couldn't delete the contact."); return }
            store.app.load()
            // The last contact of an address book: the server's is emptied too only when the sync is told so
            const force = emptied.text.split("\n").filter(x => x)
            const rest = deleter.accounts.filter(a => force.indexOf(a) < 0)
            if (force.length) store.sync(force, "Deleted", true)
            if (rest.length) store.sync(rest, "Deleted")
        }
    }

    // The change to the server now; offline, it goes at the next sync (every 30 minutes, or ⌘R's)
    // what: "Saved" or "Deleted", for the line that says how it went
    function sync(accounts, what, force) {
        if (syncer.running && !force) { waiting = [...new Set(waiting.concat(accounts))]; waitingWhat = what; return }
        if (syncer.running) { forced.push(accounts); return }
        syncer.accounts = accounts
        syncer.what = what
        syncer.command = [app.command, "sync"].concat(force ? ["--force-delete"] : []).concat(accounts)
        app.say(what + ". Sending it to " + accounts.map(accountName).join(" and ") + "…", true)
        syncer.running = true
    }
    Process {
        id: syncer
        property var accounts: []
        property string what: ""
        onExited: code => {
            const names = syncer.accounts.map(store.accountName).join(" and ")
            store.app.say(code === 0 ? syncer.what + (syncer.what === "Deleted" ? " from " : " to ") + names
                                     : syncer.what + " here. " + names + " couldn't be reached: it goes there at the next sync.")
            if (store.forced.length) store.sync(store.forced.shift(), "Deleted", true)
            else if (store.waiting.length) { const next = store.waiting; store.waiting = []; store.sync(next, store.waitingWhat) }
        }
    }
}
