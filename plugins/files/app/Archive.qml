import QtQuick
import Quickshell
import Quickshell.Io
import "Format.js" as Format

// An archive looked into as a folder, read-only (→ on a zip or tar, #3307; ⏎ still extracts it): lib/members.py reads
// its listing in a process of its own, so a big tar.gz read from end to end doesn't hold the window, and says how far it
// has come (progress); it keeps the listing in its cache, so the next look is at once. The window's path goes on below
// the archive's own ("…/photos.zip/docs"), so the path header, back and forward, and ← work as in a folder; rows are the
// folder's in the archive, as Folder gives them, each with its member's name. y puts the members on the clipboard as
// x-nightdrive/archive-members, and p in a folder unpacks them there (Clip, Ops.extractMembers). What would change the
// archive is refused in words (refuse).
Item {
    id: root
    required property var app               // FilesWindow: helper, filter, sortBy, reversed, showHidden, say()
    property string file: ""                // the archive on show, "" outside one
    property string dir: ""                 // the folder in it: "" its top, "docs/deep"
    property var known: ({})                // archives looked into in this window: their paths below read as such
    property var children: ({})             // folder → its entries, from the listing
    property int skipped: 0                 // members left out of the listing as unsafe
    property bool loading: false
    property real done: 0                   // how far the read has come, 0…1, while it takes a while
    property string error: ""
    property var rows: []
    property int total: 0                   // the folder's, before the filter
    signal changing()
    signal rebuilt()
    // The window's own place for members taken out for the preview (members.py), cleaned as it leaves
    readonly property string slot: Math.random().toString(36).slice(2, 12).replace(/[^a-z0-9]/g, "") || "w"
    readonly property string mime: "x-nightdrive/archive-members"

    // The archive p is in (or is), "" when p is a real folder's path
    function owner(p) {
        for (const k in known) if (p === k || p.startsWith(k + "/")) return k
        return ""
    }
    function look(p) { const k = Object.assign({}, known); k[p] = true; known = k }
    // The window goes to p: an archive's folder shows it (read first when it isn't the one on show), else leave
    function show(p) {
        const a = owner(p)
        if (!a) { leave(); return false }
        dir = p === a ? "" : p.slice(a.length + 1)
        if (a !== file) { file = a; read() }
        else build()
        return true
    }
    function leave() {
        if (!file) return
        file = ""; dir = ""; children = ({}); rows = []; total = 0; error = ""; skipped = 0
        clean()
    }
    function clean() { Quickshell.execDetached(["python3", app.helper, "member-clean", "--slot", slot]) }

    function read() {
        loading = true; done = 0; error = ""; children = ({}); rows = []; total = 0
        if (reader.running) reader.running = false   // another archive's read: its listing is no longer wanted
        reader.asked = file
        reader.command = ["python3", app.helper, "archive-list", file]
        reader.running = true
    }
    Process {
        id: reader
        property string asked: ""
        property var last: null
        stdout: SplitParser {
            onRead: line => {
                let d
                try { d = JSON.parse(line) } catch (e) { return }
                if (d.progress !== undefined) root.done = d.total ? d.progress / d.total : 0
                else reader.last = d
            }
        }
        stderr: StdioCollector { id: readErr }
        onExited: code => {
            const d = reader.last
            reader.last = null
            if (reader.asked !== root.file) return
            root.loading = false
            if (code !== 0 || !d || !d.entries) { root.error = readErr.text.trim().split("\n").pop() || "It couldn't be read."; root.build(); return }
            const kids = {}
            for (const e of d.entries) {
                const cut = e.name.lastIndexOf("/")
                const up = cut < 0 ? "" : e.name.slice(0, cut)
                ;(kids[up] = kids[up] || []).push(e)
            }
            root.children = kids
            root.skipped = d.skipped || 0
            if (root.skipped) root.app.say(Format.base(root.file) + ": " + root.skipped + (root.skipped === 1 ? " item" : " items")
                                          + " left out (unsafe paths or links)")
            root.build()
        }
    }

    Connections {
        target: root.app
        function onFilterChanged() { if (root.file) root.build() }
        function onSortByChanged() { if (root.file) root.build() }
        function onReversedChanged() { if (root.file) root.build() }
        function onShowHiddenChanged() { if (root.file) root.build() }
    }
    function build() {
        const out = []
        for (const e of children[dir] || []) {
            const name = e.name.slice(e.name.lastIndexOf("/") + 1)
            if (!app.showHidden && name.startsWith(".")) continue
            out.push({ name: name, path: file + "/" + e.name, dir: e.dir, size: e.size, member: e.name, link: e.link,
                       modified: new Date((e.modified || 0) * 1000) })
        }
        total = out.length
        const words = app.filter.trim().toLowerCase()
        changing()
        rows = Format.order(words ? out.filter(r => r.name.toLowerCase().indexOf(words) >= 0) : out, app.sortBy, app.reversed)
        rebuilt()
    }

    // y in it: the members on the clipboard, for p in a folder (Clip reads them back). The clipboard's own type, so no
    // other app pastes them as paths that aren't there
    function copy(rs) {
        if (!rs.length) return
        Quickshell.execDetached(["wl-copy", "--type", mime, "--", JSON.stringify({ archive: file, members: rs.map(r => r.member) })])
        app.manager.cut = []
        app.say("Copied " + (rs.length === 1 ? rs[0].name : rs.length + " items") + " from " + Format.base(file) + ": p in a folder takes them out")
    }
    // What would change it, in words
    function refuse() { app.say("Read-only inside " + Format.base(file) + ": y and p take files out") }

    // The preview's read of a row (Preview, QuickLook): a member is taken out first, into the slot
    function peek(row, long) {
        const a = ["python3", app.helper, "member-peek", file, row.member, "--slot", slot]
        return long ? a.concat(["--long"]) : a
    }
}
