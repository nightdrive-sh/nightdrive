import QtQuick
import Quickshell.Io

// The window's changes to a message and its buttons, each through `nightdrive inbox` as a terminal makes them: archive
// (and back), read and unread, delete, and press (config/inbox/press.py: open, url, run, session, task). One at a time:
// a key pressed again while one runs does nothing. then gets the command's JSON answer, failed its words for the toast.
Item {
    id: root
    required property var command             // Store.command: python3 and the core's cli.py
    property bool running: false

    function archive(id, then, failed) { run(["archive", "--json", id], then, failed) }
    function unarchive(id, then, failed) { run(["archive", "--json", "--undo", id], then, failed) }
    function read(id, isRead, then, failed) { run(["read", "--json", id].concat(isRead ? [] : ["--unread"]), then, failed) }
    function remove(id, then, failed) { run(["delete", "--json", id], then, failed) }
    // which: the button's place (0 the first), or "session" / "task" for the sender's own. A run button only after
    // the user confirmed it on RunPanel: yes is that confirmation, and nothing else passes it.
    function press(id, which, yes, then, failed) {
        run(["press", "--json", id, String(which)].concat(yes ? ["--yes"] : []), then, failed)
    }

    function run(args, then, failed) {
        if (running) return
        running = true
        job.then = then
        job.failed = failed
        job.command = command.concat(args)
        job.running = true
    }

    Process {
        id: job
        property var then: null
        property var failed: null
        stdout: StdioCollector { id: out }
        stderr: StdioCollector { id: err }
        onExited: code => {
            let answer = null
            if (code === 0) try { answer = JSON.parse(out.text) } catch (e) { code = -1 }
            try {
                // cli.py's own words ("inbox: …"), without its prefix
                if (code !== 0) failed((err.text.trim().split("\n").pop() || "That didn't work.").replace(/^inbox: /, ""))
                else if (then) then(answer)
            } finally {
                root.running = false
            }
        }
    }
}
