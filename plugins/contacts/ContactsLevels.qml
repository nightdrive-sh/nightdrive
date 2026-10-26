import QtQuick
import Quickshell
import qs

// Contacts' part of the launcher (plugin-parts lists it while the plugin is on): the root search finds people by name,
// company, address or number (rootRows), and Enter on one opens its card here: Open in Contacts, then a row per number,
// address and email address, which Enter copies or writes to. `contacts people` (lib/cards.py) gives them, read on every
// open of the launcher. Settings › Launcher › Include contacts turns them off.
// Launcher.qml asks it like its own level files (levels, titles, parents, items, activate, footer, entered).
Item {
    id: m
    property var launcher: null               // Launcher.qml sets it once the file is loaded

    readonly property string cmdPath: Qt.resolvedUrl("bin/contacts").toString().replace(/^file:\/\//, "")
    property var people: []                   // [{ id, name, org, emails, phones, addresses: [{ label, value }] }]
    property var person: null                 // the card open in Contacts › NAME

    readonly property var levels: ["contact"]
    readonly property var titles: ({ contact: "Contacts › " + (person ? person.name : "") })
    readonly property var parents: ({ contact: "root" })

    function opened() { peopleProc.running = true }
    function entered(level) {}

    function footer(level, query) {
        const cur = launcher.results[launcher.selIndex] || {}
        if (cur.kind === "contactwrite") return "Enter: write an email  ·  Shift+Enter: copy"
        if (cur.kind === "contactcopy") return "Enter: copy"
        if (cur.kind === "contactopen") return "Enter: open in Contacts"
        return ""
    }

    // Everyone in the root search: the name is what is matched first, the company, addresses and numbers after it
    function rootRows() {
        if (launcher.prefs.contacts === false) return []
        return people.map(p => ({
            item: { kind: "contact", name: p.name, glyph: "user", from: "Contacts", chevron: true, id: p.id },
            text: p.name,
            extra: [p.org].concat(p.emails.map(e => e.value), ...p.phones.map(n => numbers(n.value))).join(" ")
        }))
    }
    // A number as it may be typed: without its spaces (0401234 finds 040 123 4), and one with a country code also as at
    // home, a 0 and its last 9 digits (+358 40 123… is 040 123…), as cards.py tells numbers apart
    function numbers(v) {
        const plain = v.replace(/[\s\-()]/g, "")
        return plain.startsWith("+") ? [plain, "0" + plain.replace(/\D/g, "").slice(-9)] : [plain]
    }

    function line(kind, glyph, x) {
        // An address's lines on one row; copied, they keep their line breaks
        return { kind: kind, name: x.value.replace(/\n/g, ", "), glyph: glyph, value: x.value, summary: x.label || undefined }
    }
    function items(level, q) {
        if (level !== "contact" || !person) return []
        const p = person
        const rows = [{ kind: "contactopen", name: "Open in Contacts", glyph: "contact", sub: p.org || undefined }]
        if (p.phones.length) rows.push({ kind: "header", name: "Numbers" }, ...p.phones.map(x => line("contactcopy", "phone", x)))
        if (p.emails.length) rows.push({ kind: "header", name: "Email" }, ...p.emails.map(x => line("contactwrite", "mail", x)))
        if (p.addresses.length) rows.push({ kind: "header", name: "Addresses" }, ...p.addresses.map(x => line("contactcopy", "map-pin", x)))
        return { all: rows.map(r => ({ item: r, text: r.kind === "header" ? "" : r.name })) }
    }

    function copy(value) {
        Quickshell.execDetached(["sh", "-c", 'printf %s "$1" | wl-copy; notify-send -e -a Contacts -t 1500 "Copied" "$1"', "_", value])
    }
    function activate(it) {
        const l = launcher
        if (it.kind === "contact") {
            person = people.find(p => p.id === it.id) || null
            if (person) l.go("contact")
            return true
        }
        if (it.kind === "contactopen") { l.open = false; Quickshell.execDetached([cmdPath, "show", person.id]); return true }
        if (it.kind === "contactcopy") { l.open = false; copy(it.value); return true }
        // mailto: goes to the email app (Settings › Apps › Default apps): Mail, when it is that
        if (it.kind === "contactwrite") { l.open = false; Qt.openUrlExternally("mailto:" + it.value); return true }
        return false
    }
    function shiftActivate(it) {
        if (it.kind === "contactwrite" || it.kind === "contactcopy") { launcher.open = false; copy(it.value) }
    }

    Sh {
        id: peopleProc
        command: [m.cmdPath, "people"]
        onResult: text => { try { m.people = JSON.parse(text) } catch (e) { m.people = [] } }
    }
}
