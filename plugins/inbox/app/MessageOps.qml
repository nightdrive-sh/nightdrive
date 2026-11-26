import QtQuick

// Archive, read or unread and delete, on the open message or on every selected one (Selection.qml, #3455), each with
// its toast; archiving says Undo (⌘Z). Apart from shell.qml, which only asks for them from a key or a button.
QtObject {
    id: ops
    required property QtObject store
    required property QtObject actions         // Actions.qml
    required property QtObject toast           // kit/AppToast
    readonly property QtObject sel: store.selection

    function failed(text) { toast.show(text, { danger: true }) }
    function ids(ms) { return ms.map(m => m.id) }
    // "Deploy notes", or "3 messages"
    function named(ms) { return ms.length === 1 ? ms[0].title : ms.length + " messages" }
    // Undo puts them back and shows them again: the one, or the same selection
    function restore(ms) {
        actions.unarchive(ids(ms), () => {
            store.raw = ""
            if (ms.length === 1) store.picked = ms[0].id
            else { sel.ids = ids(ms); sel.anchorId = ms[0].id; store.picked = ms[0].id }
            store.refresh()
        }, failed)
    }

    // a: out of the list (in the archive: back to the inbox), the next one shown
    function archive() {
        const ms = sel.targets()
        if (!ms.length) return
        if (store.view === "archive" || ms[0].archived && ms.length === 1)
            actions.unarchive(ids(ms), () => { store.forget(ids(ms)); toast.show("Back in the inbox: " + named(ms)) }, failed)
        else actions.archive(ids(ms), () => {
            store.forget(ids(ms))
            toast.show("Archived " + named(ms), { action: "Undo", run: () => restore(ms) })
        }, failed)
    }
    // u: all read, unless they all are (as Mail's): then all unread. The selection stays, to change its mind.
    function toggleRead() {
        const ms = sel.targets()
        if (!ms.length) return
        const read = ms.some(m => !m.read)
        actions.read(ids(ms), read, () => {
            if (!sel.any) store.message = null
            store.raw = ""
            store.refresh()
            if (sel.any) toast.show(named(ms) + (read ? " marked read" : " marked unread"))
        }, failed)
    }
    // ⇧U: every message shown read (the view, sender or search), as Mail's ⇧U does a folder
    function allRead() {
        const ms = store.messages.filter(m => !m.read)
        if (!ms.length) return toast.show("Nothing unread here")
        actions.read(ids(ms), true, () => {
            store.raw = ""
            store.refresh()
            toast.show(named(ms) + " marked read")
        }, failed)
    }
    function remove(ms) {
        actions.remove(ids(ms), () => { store.forget(ids(ms)); toast.show("Deleted " + named(ms)) }, failed)
    }
}
