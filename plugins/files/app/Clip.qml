import QtQuick
import Quickshell
import Quickshell.Io
import "Format.js" as Format

// Files on the desktop's clipboard, shared with other apps: y / ⌘C and x / ⌘X offer them as files and as text at once
// (lib/clipboard.py, #3304), and the one who pastes picks: Files and Nautilus take x-special/gnome-copied-files (it says
// copy or cut), other file browsers and chats text/uri-list, a terminal or a text field the paths (text/plain), and
// Mail's message attaches them. Files remembers a cut too: pasted while those are still what the clipboard holds, they
// move, and the clipboard is cleared. p / ⌘V reads what is there: an archive's members, else
// x-special/gnome-copied-files, else text/uri-list.
QtObject {
    id: root
    required property var app              // the window: say(), ops
    required property QtObject shared       // shell.qml, whose cut every window shares: cut in one, pasted in another
    readonly property var cut: shared.cut   // the paths of the last cut, while the clipboard still holds them
    readonly property var cutSet: { const s = {}; for (const p of cut) s[p] = true; return s }

    function copy(paths, isCut) {
        if (!paths.length) return
        Quickshell.execDetached(["python3", Quickshell.shellDir + "/../lib/clipboard.py", isCut ? "cut" : "copy", "--"].concat(paths))
        shared.cut = isCut ? paths.slice() : []
        app.say((isCut ? "Cut " : "Copied ") + (paths.length === 1 ? Format.base(paths[0]) : paths.length + " items"))
    }

    // Reads the types on offer, then the one wanted; then copies or moves into the folder
    property string into: ""
    property bool members: false            // what is there is an archive's members (Archive.copy)
    readonly property Process types: Process {
        command: ["wl-paste", "--list-types"]
        stdout: StdioCollector {
            onStreamFinished: {
                const t = text.split("\n")
                const type = t.indexOf(root.app.archive.mime) >= 0 ? root.app.archive.mime
                           : t.indexOf("x-special/gnome-copied-files") >= 0 ? "x-special/gnome-copied-files"
                           : t.indexOf("text/uri-list") >= 0 ? "text/uri-list" : ""
                if (!type) { root.app.say("No files on the clipboard"); return }
                root.members = type === root.app.archive.mime
                reader.command = ["wl-paste", "--no-newline", "--type", type]
                reader.running = true
            }
        }
    }
    readonly property Process reader: Process {
        stdout: StdioCollector { onStreamFinished: root.pasted(text) }
    }
    function paste(folder) {
        into = folder
        types.running = true
    }
    function pasted(text) {
        if (members) {                      // taken out of the archive, into the folder
            let d = null
            try { d = JSON.parse(text) } catch (e) {}
            if (d && d.archive && d.members && d.members.length) app.ops.extractMembers(d.archive, d.members, into)
            else app.say("No files on the clipboard")
            return
        }
        let lines = text.split(/\r?\n/).filter(l => l && !l.startsWith("#"))
        let op = "copy"
        if (lines[0] === "copy" || lines[0] === "cut") op = lines.shift()
        const paths = lines.map(Format.path).filter(p => p)
        if (!paths.length) { app.say("No files on the clipboard"); return }
        if (op === "cut" || (cut.length === paths.length && paths.every(p => cutSet[p]))) {
            app.ops.move(paths, into)
            shared.cut = []
            Quickshell.execDetached(["wl-copy", "--clear"])
        } else app.ops.copy(paths, into)
    }
}
