import QtQuick
import Quickshell
import Quickshell.Io

// m: the marked files, or the picked one, attached to a new message in Mail (`nightmail new FILE…`; a message already
// being written takes them instead). A mail can't carry a folder: the folders among them are left out with a word to
// compress them first (c), and folders alone send nothing. Mail is a plugin of its own, so its command may be missing.
QtObject {
    id: root
    required property var app             // FilesWindow: marked, picked, say()
    readonly property string nightmail: Quickshell.env("HOME") + "/.local/bin/nightmail"

    function send() {
        if (app.trashShown || runner.running) return
        const rows = app.marked.length ? app.marked : app.picked ? [app.picked] : []
        if (!rows.length) return
        const files = rows.filter(r => !r.dir).map(r => r.path)
        const folders = rows.length - files.length
        if (!files.length) {
            app.say(folders === 1 ? "A folder can't be attached: compress it first (c)" : "Folders can't be attached: compress them first (c)", true)
            return
        }
        left = folders
        // Through bash, so a Mail that isn't there answers 127 as a missing command would
        runner.command = ["bash", "-c", '[[ -x $0 ]] || exit 127; exec "$0" new -- "$@"', nightmail].concat(files)
        runner.running = true
    }

    property int left: 0                 // the folders left out, for the word once Mail has the files
    readonly property Process runner: Process {
        stderr: StdioCollector { id: err }
        onExited: code => {
            // 127: Mail isn't installed; 2: a file it couldn't take, its own words say which
            if (code === 127) { root.app.say("Mail isn't installed: nightdrive apps install mail", true); return }
            if (code !== 0) { root.app.say(err.text.trim().replace(/^nightmail: /, "") || "Mail couldn't take the files", true); return }
            root.app.marks = ({})             // done with them, as a compress is
            if (root.left) root.app.say("Left out " + (root.left === 1 ? "a folder" : root.left + " folders") + ": compress first (c) to send one")
        }
    }
}
