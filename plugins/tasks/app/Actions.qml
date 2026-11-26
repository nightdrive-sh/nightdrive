import QtQuick
import Quickshell
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

    // Done, or back to open when it is done (Done's rows). The row shows it at once (ticking: the task's id → its new
    // done), and the change runs a moment later, so the tick is seen before the row leaves the view. Pressed again in
    // that moment, it is called off. An entry goes once a read shows the task so (settle) or the change failed.
    property var ticking: ({})
    readonly property int tickDelay: 2000
    property var waits: ({})            // the task's id → its Timer, while the change hasn't been run
    readonly property Component wait: Component { Timer { property var go: null; onTriggered: { go(); destroy() } } }
    function toggle(task) {
        if (!task) return
        const id = task.id
        if (waits[id]) { waits[id].destroy(); forget(waits, id); untick(id); return }
        if (ticking[id] !== undefined) return            // already on its way to cli.py
        const done = !task.done
        ticking = Object.assign({}, ticking, { [id]: done })
        const t = wait.createObject(root, { interval: tickDelay })
        t.go = () => {
            forget(waits, id)
            change([done ? "done" : "undone", "--", id], (done ? "Done: " : "Not done: ") + task.title, () => untick(id))
        }
        waits[id] = t
        t.start()
    }
    function forget(map, id) { delete map[id] }
    // The window is closing (Tasks quits with it): a tick still waiting is written now, detached, so it isn't lost
    function flush() {
        for (const id in waits) {
            Quickshell.execDetached(["python3", app.helper, ticking[id] ? "done" : "undone", "--", id])
            waits[id].destroy()
        }
        waits = ({})
    }
    function untick(id) {
        if (ticking[id] === undefined) return
        const next = Object.assign({}, ticking); delete next[id]; ticking = next
    }
    // A read is in: the ticks it shows done (or gone) are over; those still waiting stay
    function settle(tasks) {
        const left = {}
        for (const id in ticking) {
            const t = tasks.find(x => x.id === id)
            if (waits[id] || (t && t.done !== ticking[id])) left[id] = ticking[id]
        }
        ticking = left
    }
    function trash(task) {
        if (task) change(["trash", "--", task.id], "Moved to the trash: " + task.title)
    }
    function change(args, said, failed) {
        run(args, (d, why) => {
            if (!d && failed) failed()
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
