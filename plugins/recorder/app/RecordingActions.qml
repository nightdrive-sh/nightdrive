import QtQuick

// What can be done to the picked recording, for the view's buttons and the window's keys alike: Rename (F2, asked in
// the window's AppPrompt), Export (e, ExportPanel), Show in Files (o) and Trash (⌘⌫, no question first: the trash keeps
// it, and the toast's Undo, ⌘Z, puts it back). Each says in the toast how it went; rename and trash go through the
// recorder command (`recorder rename|trash|restore|show`), so they are the same as in a terminal or Claude's tools.
QtObject {
    id: a
    required property var store
    required property var player
    required property var toast
    required property var prompt              // AppPrompt
    required property var exporter            // ExportPanel
    readonly property var rec: store.current

    function rename() {
        if (!rec) return
        const was = rec.name
        prompt.ask("New name", was, name => {
            if (!name || name === was) return
            store.act(["rename", was, name], r => {
                store.picked = r.name
                toast.show("Renamed to " + r.name, { action: "Undo", run: () =>
                    store.act(["rename", r.name, was], () => store.picked = was) })
            })
        })
    }

    function trash() {
        if (!rec) return
        const name = rec.name
        const i = store.index
        player.stop()
        store.act(["trash", name], r => {
            // The one below it is picked, as Notes does; the last one gives way to the one above
            const rest = store.recordings.filter(x => x.name !== name)
            store.picked = rest.length ? rest[Math.min(i, rest.length - 1)].name : ""
            toast.show("Moved " + name + " to the trash", { action: "Undo", run: () =>
                store.act(["restore"].concat(r.names), () => store.picked = name) })
        })
    }

    function show() { if (rec) store.run(["show", rec.name]) }
    function exportIt() { if (rec) exporter.open(rec) }
}
