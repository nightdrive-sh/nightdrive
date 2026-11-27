import QtQuick
import Quickshell.Io
import qs
import qs.kit
import "Format.js" as Format

// I, ⌘I: the picked file's info (lib/info.py): its type, size, where it is, its times, whose it is and who may read,
// write and run it, as words rather than rwx. The one change here is Executable, for a file of the user's own: a
// download that won't run, a script written by hand. It is made at once, with Undo in the toast; the rest of the
// permissions are only shown (info.py says why). Space turns the switch, Esc or ⏎ closes.
AppPanel {
    id: root
    required property var app             // FilesWindow: picked, helper, ops, say(), look
    property var d: null                  // info.py's answer for the file on show
    property string path: ""
    visible: false
    cardWidth: 480
    c: app.look
    onOutsideTapped: close()
    onVisibleChanged: if (!visible) app.toList()
    Keys.onPressed: e => {
        if (e.key === Qt.Key_Escape || e.key === Qt.Key_Return || e.key === Qt.Key_Enter) close()
        else if (e.key === Qt.Key_Space && exe.visible) exe.toggle()
        else return
        e.accepted = true
    }

    function ask() {
        const f = app.picked
        if (!f) return
        // An archive's members and the trash's files aren't files on disk here: nothing of theirs to show
        if (app.inArchive || app.trashShown) { app.say("Info is for the files in a folder", true); return }
        path = f.path
        d = null
        load()
        visible = true
        forceActiveFocus()
    }
    function load() { reader.command = ["python3", "-I", app.helper, "info", path]; reader.running = true }
    function close() { visible = false }

    // The switch: info.py's executable, whose undo the window's ⌘Z and the toast's Undo run
    function setExecutable(on) {
        app.ops.run(["executable", path, on ? "on" : "off"], (r, why) => {
            if (!r) { app.say(why, true); load(); return }
            app.ops.remember({ undo: r.undo }, (on ? "Executable: " : "Not executable: ") + Format.base(path))
            load()
        })
    }

    Process {
        id: reader
        stdout: StdioCollector { id: out }
        stderr: StdioCollector { id: err }
        onExited: code => {
            if (code !== 0) { root.app.say(err.text.trim().split("\n").pop() || "No info", true); root.close(); return }
            try { root.d = JSON.parse(out.text) } catch (e) { root.d = null }
            exe.on = !!root.d && root.d.executable     // the box's own toggle() has broken any binding
        }
    }

    // "Read and write", "Read, write and run", "Nothing"
    function may(t) {
        const w = []
        if (t.read) w.push(d && d.dir ? "see what is in it" : "read")
        if (t.write) w.push(d && d.dir ? "change it" : "write")
        if (t.run) w.push(d && d.dir ? "go in" : "run")
        if (!w.length) return "Nothing"
        const s = w.length === 1 ? w[0] : w.slice(0, -1).join(", ") + " and " + w[w.length - 1]
        return s[0].toUpperCase() + s.slice(1)
    }
    function when(iso) { return iso ? Regional.format(iso, "medium") + " " + Regional.time(iso.slice(11, 16)) : "" }
    function sizeText() {
        if (!d) return ""
        if (!d.dir) return Format.size(d.size) + (d.size >= 1000 ? " (" + d.size.toLocaleString(Qt.locale(), "f", 0) + " bytes)" : "")
        if (d.complete && !d.files) return "Empty"
        return (d.complete ? "" : "More than ") + Format.size(d.size) + " in " + d.files + (d.files === 1 ? " file" : " files")
    }
    readonly property var lines: !d ? [] : [
        ["Kind", d.kind || d.type || "Unknown"],
        ["Size", sizeText()],
        ["Where", app.tilde(Format.parent(d.path))],
    ].concat(d.link ? [["Link to", d.link]] : []).concat([
        ["Modified", when(d.modified)],
        ["Owner", d.owner + (d.mine ? " (you)" : "")],
        ["Group", d.group],
        ["Owner may", may(d.perms.owner)],
        ["Group may", may(d.perms.group)],
        ["Others may", may(d.perms.others)],
        ["Mode", d.text + "  " + d.mode]
    ])

    Text {
        width: parent.width
        textFormat: Text.PlainText
        elide: Text.ElideMiddle
        text: Format.base(root.path)
        color: root.c.title; font.family: root.c.font; font.pixelSize: 15; font.weight: Font.Medium
    }
    Text {
        visible: !root.d
        text: "Reading…"
        color: root.c.faint; font.family: root.c.font; font.pixelSize: 13
    }
    Grid {
        visible: !!root.d
        columns: 2
        columnSpacing: 16
        rowSpacing: 6
        width: parent.width
        Repeater {
            model: root.lines.length * 2
            Text {
                readonly property bool label: index % 2 === 0
                readonly property var line: root.lines[Math.floor(index / 2)]
                width: label ? 92 : parent.width - 92 - 16
                text: label ? line[0] : line[1]
                textFormat: Text.PlainText
                wrapMode: label ? Text.NoWrap : Text.WrapAnywhere
                color: label ? root.c.faint : root.c.text
                font.family: root.c.font; font.pixelSize: 13
            }
        }
    }
    AppCheck {
        id: exe
        visible: !!root.d && root.d.can_switch
        c: root.c
        label: "Executable: may run as a program"
        onToggled: root.setExecutable(on)
        onAccepted: root.close()
    }
    // Why there is no switch, when it isn't self-evident (a folder has none, and needs no word)
    Text {
        visible: !!root.d && !root.d.can_switch && !root.d.dir
        width: parent.width
        wrapMode: Text.Wrap
        text: !root.d ? "" : root.d.link ? "A link: its target's own info says whether it runs."
            : !root.d.mine ? root.d.owner + "'s: only they can change who may run it." : ""
        color: root.c.faint; font.family: root.c.font; font.pixelSize: 11
    }
    Row {
        spacing: 8
        AppPanelButton { c: root.c; label: "Close"; strong: true; keys: ["Esc"]; onClicked: root.close() }
    }
}
