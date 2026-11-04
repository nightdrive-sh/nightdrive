import QtQuick
import Quickshell.Io

// The window's quick changes to a task (and the lists', ListActions): done (Space or its circle), back to open (the same in Done), to the trash
// (Delete), and their undo, from the toast's Undo or ⌘Z. Each runs the `cli.py` command Claude's tools and `tasks` run, so
// a change from the window is undone the same way as theirs (`cli.py restore UNDO`, refused once the task has changed
// since). Each call gets a process of its own: Space pressed down a list starts the next before the last has finished.
QtObject {
    id: root
    required property var app           // the window: helper, load(), say(), offer()
    // The window's changes, newest last, for ⌘Z: [{ sid (restore's id), id (the task's), list (a list's: ListActions) }]
    property var undos: []
    readonly property int undoDepth: 20

    readonly property Component runner: Component {
        Process {
            property var then: null
            stdout: StdioCollector { id: out }
            stderr: StdioCollector { id: err }
            onExited: code => {
                let d = null
                if (code === 0) try { d = JSON.parse(out.text) } catch (e) {}
                // cli.py's own words (sys.exit), the last line: the rest is a traceback, if anything
                then(d, err.text.trim().split("\n").pop() || "That didn't work: tasks log says why.")
                destroy()
            }
        }
    }
    // args: the verb and its words; --json goes right after the verb, before any "--"
    function run(args, then) {
        const cmd = ["python3", app.helper, args[0], "--json"].concat(args.slice(1))
        const p = runner.createObject(root, { command: cmd, then: then })
        p.running = true
    }

    // Done, or back to open when it is done (Done's rows)
    function toggle(task) {
        if (!task) return
        change([task.done ? "undone" : "done", "--", task.id], (task.done ? "Not done: " : "Done: ") + task.title)
    }
    function trash(task) {
        if (task) change(["trash", "--", task.id], "Moved to the trash: " + task.title)
    }
    function change(args, said) {
        run(args, (d, why) => {
            app.load()
            if (!d) { app.say(why, true); return }
            remember({ sid: d.undo, id: d.id }, said)
        })
    }
    // A change made, for ⌘Z and the toast's Undo
    function remember(step, said) {
        undos = undos.concat([step]).slice(-undoDepth)
        app.offer(said, () => undo(step))
    }

    // The newest change, or the one the toast's Undo names; the task is picked again where it comes back
    function undo(which) {
        const step = which || undos[undos.length - 1]
        if (!step) { app.say("Nothing to undo"); return }
        undos = undos.filter(x => x.sid !== step.sid)
        run(["restore", step.sid], (d, why) => {
            if (d) { app.keepNext = step.id; app.keepList = step.list || "" }
            app.load()
            app.say(d ? "Undone" : why, !d)
        })
    }
}
