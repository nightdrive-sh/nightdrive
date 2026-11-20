import QtQuick
import Quickshell
import Quickshell.Io
import "Format.js" as Format

// Files' changes, each run as lib/cli.py's command in a process of its own: copy and move (paste, a drop), trash,
// rename, new, compress, extract, and the trash's restore and delete. A change's result names its undo (cli.py's "undo"), which the toast's
// Undo and ⌘Z run. A copy or move that takes a while shows how far it is in a toast that stays, with Stop (SIGTERM:
// cli.py removes the file it was writing and keeps what it had done, Undo included).
QtObject {
    id: root
    required property var app             // the window: helper, say(), offer(), toast, done(result) to pick what came
    property var undos: []                // newest last: [{ undo: [cli args], said }]
    readonly property int undoDepth: 30
    property int busy: 0                  // changes under way

    readonly property Component runner: Component {
        Process {
            id: p
            property var then: null
            property var last: null
            property string label: ""     // "Copying", "Moving": the progress toast's word
            stdout: SplitParser {
                onRead: line => {
                    let d
                    try { d = JSON.parse(line) } catch (e) { return }
                    if (d.progress !== undefined && p.label) {
                        const pct = d.total ? Math.floor(100 * d.progress / d.total) : 0
                        root.app.toast.show(p.label + " " + d.name + " – " + pct + " %",
                                            { sticky: true, action: "Stop", run: () => p.signal(15) })
                    } else if (d.progress === undefined) p.last = d
                }
            }
            stderr: StdioCollector { id: err }
            onExited: code => {
                root.busy--
                then(code === 0 ? last : null, err.text.trim().split("\n").pop() || "That didn't work: files log says why.")
                destroy()
            }
        }
    }
    function run(args, then, label) {
        busy++
        const p = runner.createObject(root, { command: ["python3", app.helper].concat(args), then: then, label: label || "" })
        p.running = true
    }

    function count(n, one) { return n === 1 ? one : n + " items" }

    // A change done: what it says, its Undo, and the window told (which picks what it made and reads the places again)
    function change(args, said, label) {
        run(args, (d, why) => {
            if (!d) { app.say(why, true); app.changed(null); return }
            // Stopped before anything was done: there is nothing to say done, nor to undo
            const s = d.stopped && !d.undo ? "Stopped" : typeof said === "function" ? said(d) : said
            if (d.error) app.say(d.error, true)
            else if (d.undo) remember({ undo: d.undo }, d.stopped ? "Stopped: " + s : s)
            else app.say(s)
            app.changed(d)
        }, label)
    }
    function remember(step, said) {
        undos = undos.concat([step]).slice(-undoDepth)
        app.offer(said, () => undo(step))
    }
    function undo(which) {
        const step = which || undos[undos.length - 1]
        if (!step) { app.say("Nothing to undo"); return }
        undos = undos.filter(x => x !== step)
        run(step.undo, (d, why) => {
            const left = d && d.left && d.left.length ? d.left : []
            app.say(!d ? why : left.length ? "Not undone: " + left.join(", ") + " has changed since" : "Undone", !d || left.length > 0)
            app.changed(d)
        })
    }

    function copy(paths, into) {
        if (paths.length) change(["copy", "--into", into, "--"].concat(paths),
                                 d => "Copied " + count(d.made.length, Format.base(d.made[0] || "")), "Copying")
    }
    function move(paths, into) {
        if (paths.length) change(["move", "--into", into, "--"].concat(paths),
                                 d => d.moved.length ? "Moved " + count(d.moved.length, Format.base(d.moved[0][0])) : "Already here", "Moving")
    }
    // c and ⏎ on an archive (pack.py, unpack.py): what was left out of an archive as unsafe is said, not hidden
    function compress(paths, into, name, format) {
        if (paths.length) change(["compress", "--into", into, "--name", name, "--format", format, "--"].concat(paths),
                                 d => "Compressed into " + Format.base(d.made[0] || ""), "Compressing")
    }
    function extract(path) {
        change(["extract", "--", path], d => "Extracted " + Format.base(d.made[0] || "")
               + (d.skipped && d.skipped.length ? " (" + count(d.skipped.length, "1 item") + " left out: unsafe paths or links)" : ""), "Extracting")
    }
    function trash(paths) {
        if (paths.length) change(["trash", "--"].concat(paths), "Moved " + count(paths.length, Format.base(paths[0])) + " to the trash")
    }
    function rename(path, name) { change(["rename", path, name], "Renamed to " + name) }
    function create(folder, name, isDir) {
        change(["new", folder, name].concat(isDir ? ["--dir"] : []), (isDir ? "New folder " : "New file ") + name)
    }
    // The trash's own: back where they were (Undo trashes them again), and for good (no undo: AppConfirm asks first)
    function restore(ids) {
        run(["restore", "--"].concat(ids), (d, why) => {
            if (!d) { app.say(why, true); return }
            if (d.restored.length) remember({ undo: ["trash", "--"].concat(d.restored) }, "Put back " + count(d.restored.length, Format.base(d.restored[0])))
            if (d.left.length) app.say("Not put back: " + d.left.join(", "), true)
            app.changed(d)
        })
    }
    function remove(ids) {
        run(["delete", "--"].concat(ids), (d, why) => { app.say(d ? "Deleted " + count(d.deleted, "1 item") : why, !d); app.changed(d) })
    }
    function empty() {
        run(["trash-empty"], (d, why) => { app.say(d ? "Trash emptied" : why, !d); app.changed(d) })
    }
}
