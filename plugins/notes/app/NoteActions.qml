import QtQuick
import Quickshell.Io

// The window's changes to a note as a whole, each through the notes command as Claude's tools make them, so the window,
// a terminal and Claude rename and trash a note the same way (lib/rename.py, notes.py trash) and undo it the same way:
// rename and its undo unrename, trash and its undo restore. One at a time: a key pressed again while one runs does
// nothing. then gets the command's JSON answer, failed its words for the window's toast.
Item {
    id: root
    required property string command          // the plugin's bin/notes, by its path
    readonly property bool running: job.running

    function rename(id, title, then, failed) { run(["rename", "--json", "--", id, title], then, failed) }
    // r: rename's answer, which holds what puts it back
    function unrename(r, then, failed) {
        run(["unrename", "--json", "--expect", r.md5, "--", r.id, r.old_id, r.old_head], then, failed)
    }
    function trash(id, then, failed) { run(["trash", "--json", id], then, failed) }
    // names: trash's answer's names in the trash. restore prints no JSON: then gets null
    function restore(names, then, failed) { run(["restore", "--"].concat(names), then, failed, true) }

    function run(args, then, failed, plain) {
        if (job.running) return
        job.then = then
        job.failed = failed
        job.plain = !!plain
        job.command = [command].concat(args)
        job.running = true
    }

    Process {
        id: job
        property var then: null
        property var failed: null
        property bool plain: false
        stdout: StdioCollector { id: out }
        stderr: StdioCollector { id: err }
        onExited: code => {
            let answer = null
            if (code === 0 && !plain) try { answer = JSON.parse(out.text) } catch (e) { code = -1 }
            // The last line: notes.py's message, after anything the shell printed on the way
            if (code !== 0) failed(err.text.trim().split("\n").pop() || "That didn't work (notes log has more).")
            else then(answer)
        }
    }
}
