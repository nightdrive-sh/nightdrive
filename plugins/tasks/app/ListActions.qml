import QtQuick
import qs.kit

// The lists' changes in the window (#2022): New list (⇧N, + by the sidebar's title) and Rename (F2) ask for a name in
// the kit's AppPrompt, Delete asks first in AppConfirm when the list has tasks, which go to the trash with it. Each runs
// the command Claude's tools and `tasks` run (lib/lists.py), and its Undo, in the toast and ⌘Z, is theirs too
// (`cli.py restore`), through Actions so ⌘Z goes back through the tasks' and the lists' changes in the order made.
Item {
    id: root
    anchors.fill: parent
    required property QtObject c
    required property var app           // the window: tasks, view, load(), say(), keepList
    required property var ops           // Actions: run(), remember()
    property Item behind: null
    signal closed()
    readonly property bool busy: prompt.visible || confirm.visible

    function create() {
        prompt.ask("New list", "", name => {
            if (name) change(["list-new", "--", name], d => "Made the list " + d.name)
        })
    }
    function rename(list) {
        if (!list) return
        prompt.ask("Rename " + list.name, list.name, name => {
            if (name && name !== list.name) change(["list-rename", "--", list.id, name], d => "Renamed to " + d.name)
        })
    }
    // An empty list goes at once (Undo brings it back); one with tasks asks first, saying how many
    property var removing: null
    function remove(list) {
        if (!list) return
        const tasks = app.tasks.filter(t => t.list_id === list.id)
        if (!tasks.length) { removeNow(list); return }
        const open = tasks.filter(t => !t.done).length
        confirm.question = "Delete the list " + list.name + "?"
        confirm.detail = (tasks.length === 1 ? "Its task goes" : "Its " + tasks.length + " tasks" + (open < tasks.length ? " (" + open + " open)" : "") + " go")
                       + " to the trash with it. Undo brings the list back as it was."
        removing = list
    }
    function removeNow(list) {
        change(["list-remove", "--with-tasks", "--", list.id], d => "Deleted " + d.name + (d.tasks ? " and its " + (d.tasks === 1 ? "task" : d.tasks + " tasks") : ""))
    }

    // said: the toast's words from cli.py's answer. The list made or renamed is picked once the window has read again;
    // its undo picks it again where it comes back
    function change(args, said) {
        ops.run(args, (d, why) => {
            if (!d) { app.say(why, true); return }
            app.keepList = d.id
            app.load()
            ops.remember({ sid: d.undo, id: "", list: d.id }, said(d))
        })
    }

    AppPrompt {
        id: prompt
        c: root.c
        behind: root.behind
        onClosed: root.closed()
    }
    AppConfirm {
        id: confirm
        c: root.c
        behind: root.behind
        visible: root.removing !== null
        action: "Delete"
        onAnswered: ok => {
            const list = root.removing
            root.removing = null
            if (ok) root.removeNow(list)
            root.closed()
        }
    }
}
