import QtQuick
import Quickshell
import Quickshell.Io

// Nightdrive Contacts, as Mail sees it (plugins/contacts): its people's addresses, to complete To and Cc from with the
// mail's own, and a sender's card to open or make. Contacts is a plugin of its own: without it (or without an account in
// it) available stays false, and Mail is as before.
QtObject {
    id: book
    // The plugin beside this one; `contacts people` lists everyone as JSON
    readonly property string command: Quickshell.shellDir + "/../../contacts/bin/contacts"
    property var people: []                   // [{ id, name, emails: [{ label, value }] }]
    readonly property bool available: people.length > 0
    // address (lower case) → the person's name
    readonly property var names: {
        const out = {}
        for (const p of people) for (const e of p.emails) out[e.value.toLowerCase()] = p.name
        return out
    }

    function load() { reader.running = true }
    function known(address) { return names[(address || "").toLowerCase()] !== undefined }
    function show(address) { Quickshell.execDetached([command, "show", address]) }
    // Contacts opens its editor with these in it (a bare address as From has no name to give)
    function add(name, address) {
        Quickshell.execDetached([command, "new", name.indexOf("@") >= 0 ? "" : name, address])
        waitingFor = address.toLowerCase(); tries = 0; recheck.start()
    }
    // Once it is saved there, the sender's button turns to Open in Contacts: read again now and then until it is (or a while)
    property string waitingFor: ""
    property int tries: 0
    property Timer recheck: Timer {
        interval: 5000; repeat: true
        onTriggered: {
            if (book.known(book.waitingFor) || ++book.tries > 36) { stop(); book.waitingFor = ""; return }
            book.load()
        }
    }

    // Name <address>, the name in quotes when it has what a header reads otherwise (a comma: "Virtanen, Matti")
    function nameAddr(name, address) {
        if (!name) return address
        return (/[",;:<>@()\[\]\\]/.test(name) ? '"' + name.replace(/(["\\])/g, "\\$1") + '"' : name) + " <" + address + ">"
    }
    // The mail's addresses (Notmuch.addresses, the most written with first) with Contacts': the people in Contacts first, by
    // their name there, then the rest; an address only in Contacts comes after those of them the mail has
    function merge(mail) {
        if (!available) return mail
        const inBook = [], rest = [], seen = {}
        for (const a of mail) {
            const k = a.address.toLowerCase(), name = names[k]
            seen[k] = true
            if (name !== undefined) inBook.push({ name: name, address: a.address, nameAddr: nameAddr(name, a.address) })
            else rest.push(a)
        }
        for (const p of people) for (const e of p.emails) {
            const k = e.value.toLowerCase()
            if (seen[k]) continue
            seen[k] = true
            inBook.push({ name: p.name, address: e.value, nameAddr: nameAddr(p.name, e.value) })
        }
        return inBook.concat(rest)
    }

    property Process reader: Process {
        command: ["bash", "-c", '[ -x "$1" ] && exec "$1" people', "_", book.command]
        stdout: StdioCollector {
            onStreamFinished: { try { book.people = JSON.parse(text) || [] } catch (e) { book.people = [] } }
        }
    }
}
