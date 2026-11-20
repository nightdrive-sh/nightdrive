import QtQuick
import Quickshell
import Quickshell.Io
import "Format.js" as Format

// Files on the desktop's clipboard, shared with other apps: y / ⌘C and x / ⌘X put them there as text/uri-list, the
// type browsers, chats and Nautilus paste files from (wl-copy offers one type, and a text/ one comes with text/plain,
// so a terminal pastes the URLs). A cut is the same on the clipboard, and Files remembers it: pasted while those are
// still what the clipboard holds, they move, and the clipboard is cleared. p / ⌘V reads what is there: Nautilus's
// x-special/gnome-copied-files first (it says copy or cut), else text/uri-list.
QtObject {
    id: root
    required property var app              // the window: say(), ops
    required property QtObject shared       // shell.qml, whose cut every window shares: cut in one, pasted in another
    readonly property var cut: shared.cut   // the paths of the last cut, while the clipboard still holds them
    readonly property var cutSet: { const s = {}; for (const p of cut) s[p] = true; return s }

    function uris(paths) { return paths.map(Format.url).join("\r\n") + "\r\n" }

    function copy(paths, isCut) {
        if (!paths.length) return
        Quickshell.execDetached(["wl-copy", "--type", "text/uri-list", "--", uris(paths)])
        shared.cut = isCut ? paths.slice() : []
        app.say((isCut ? "Cut " : "Copied ") + (paths.length === 1 ? Format.base(paths[0]) : paths.length + " items"))
    }

    // Reads the types on offer, then the one wanted; then copies or moves into the folder
    property string into: ""
    readonly property Process types: Process {
        command: ["wl-paste", "--list-types"]
        stdout: StdioCollector {
            onStreamFinished: {
                const t = text.split("\n")
                const type = t.indexOf("x-special/gnome-copied-files") >= 0 ? "x-special/gnome-copied-files"
                           : t.indexOf("text/uri-list") >= 0 ? "text/uri-list" : ""
                if (!type) { root.app.say("No files on the clipboard"); return }
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
