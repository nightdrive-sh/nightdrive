import QtQuick
import Quickshell
import Quickshell.Io

// Your own folders and their sorting by sender, for the window: each account's folders (lib/folders.py), the rules
// (rules.json, read again when it changes: the sync's hook, Claude's tools and `nightmail sort` change it too) and the
// commands Actions.qml, the menus and Settings call (sorting.py, rules.py). Apart from Notmuch.qml, the reading side.
QtObject {
    id: sorter
    property var byAccount: ({})        // { account id: ["Offers", …] } (folders.py list)
    property var rules: []              // every account's: { account, folder, sender | domain, added }
    property var publicDomains: []      // gmail.com and the like: no domain rule for them (rules.py public)
    readonly property string lib: Quickshell.shellDir + "/../lib/"

    readonly property Component proc: Component {
        Process {
            id: p
            property var done: null
            running: true
            stdout: StdioCollector { onStreamFinished: { if (p.done) p.done(text); p.destroy() } }
        }
    }
    // Every script here answers with one JSON object, { error } when it fails
    function call(script, args, done) {
        proc.createObject(sorter, { command: ["python3", lib + script].concat(args), done: t => {
            let r
            try { r = JSON.parse(t) } catch (e) { r = { error: t.trim() || script + " gave no answer" } }
            if (done) done(r)
        } })
    }

    function load(done) {
        call("folders.py", ["list"], r => { if (r.folders) byAccount = r.folders; if (done) done() })
        rulesFile.reload()
    }
    Component.onCompleted: call("rules.py", ["public"], r => { if (r.domains) publicDomains = r.domains })
    readonly property FileView rulesFile: FileView {
        path: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/nightmail/rules.json"
        watchChanges: true
        printErrors: false      // none yet is no rules
        onFileChanged: reload()
        onLoaded: { try { sorter.rules = JSON.parse(text()).rules || [] } catch (e) { sorter.rules = [] } }
        onLoadFailed: sorter.rules = []
    }

    // Folders: made empty (and given a channel in isyncrc where the account needs one), or deleted with their mail
    // going back to the inbox and their rules ending (folders.py)
    // done comes once the folders have been read again, so the window's list holds the change
    function create(account, name, done) { call("folders.py", ["create", account, name], r => load(() => done(r))) }
    function remove(account, name, done) { call("folders.py", ["delete", account, name], r => load(() => done(r))) }

    // A drag into a folder (learn), one back out of it to the inbox (forget), and ⌘Z for either (undo: the step as
    // learn or forget gave it). ids: "thread:…" or message ids.
    function learn(account, folder, ids, domain, done) {
        call("sorting.py", ["learn"].concat(domain ? ["--domain"] : []).concat([account, folder]).concat(ids), r => { rulesFile.reload(); done(r) })
    }
    function forget(account, ids, done) { call("sorting.py", ["forget", account].concat(ids), r => { rulesFile.reload(); done(r) }) }
    function undo(step, done) { call("sorting.py", ["undo", JSON.stringify(step)], r => { rulesFile.reload(); if (done) done(r) }) }
    function removeRule(rule, done) {
        const kind = rule.sender ? "sender" : "domain"
        call("rules.py", ["remove", rule.account, kind, rule[kind]], r => { rulesFile.reload(); if (done) done(r) })
    }

    // The rule that sorts an address in an account, as rules.py's match: the address's own before its domain's
    function ruleFor(account, address) {
        const a = (address || "").toLowerCase(), d = a.split("@")[1] || ""
        const mine = rules.filter(r => r.account === account)
        return mine.find(r => r.sender === a)
            || mine.find(r => r.domain && (d === r.domain || d.endsWith("." + r.domain))) || null
    }
    function describe(rule) { return rule.sender || "all of " + rule.domain }
}
