import QtQuick

// Several messages selected at once, as Mail's threads (#3455): ⇧↑ ⇧↓ (⇧K ⇧J) and ⇧-click a range from where the keys
// are, Ctrl-click one more or one less, ⌘A every one shown, v the one where the keys are and on (Files' and Mail's, #3672),
// Esc none. Archive, read or unread and delete then act on them
// all (shell.qml) and SelectedPane says how many. Without any, they act on the open message. Store.picked stays where
// the keyboard is, but while some are selected the message under it isn't shown, so moving doesn't mark it read.
QtObject {
    id: sel
    required property QtObject store
    property var ids: []                       // the selected messages' ids, in the list's order; empty: the open one
    property string anchorId: ""               // where a ⇧ range starts
    // Selecting with v: j k (the arrows) then move the keys and keep what is selected, as in Files and Mail; one
    // selected is a selection too, so v can start one
    property bool marking: false
    readonly property int count: ids.length
    readonly property bool any: ids.length > 0

    function has(id) { return ids.indexOf(id) >= 0 }
    // What a key acts on: the selected messages (as the list has them), else the open one
    function targets() {
        if (any) return store.messages.filter(m => has(m.id))
        return store.message ? [store.message] : []
    }
    function clear() { ids = []; anchorId = ""; marking = false }
    function set(list, anchor, at) {
        ids = list
        anchorId = anchor
        marking = false
        store.message = null                   // hidden while they are: its keys (⌥1 … ⌥8, s, t, i) do nothing
        store.picked = store.messages[at].id
    }
    // v: the message where the keys are in or out of the selection, and the keys on to the next. With the last one out,
    // the next is open again, so the keys never act on one that isn't shown.
    function markNext() {
        const ms = store.messages
        const i = store.index
        if (i < 0) return
        const id = ms[i].id
        const at = Math.min(i + 1, ms.length - 1)
        const next = has(id) ? ids.filter(p => p !== id) : ids.concat([id])
        if (!next.length) { clear(); store.picked = ms[at].id; return }
        set(ms.filter(m => next.indexOf(m.id) >= 0).map(m => m.id), id, at)
        marking = true
    }
    function moveMarking(d) { store.step(d) }
    // From the anchor (or where the keys are) to i
    function range(i) {
        const ms = store.messages
        if (i < 0 || i >= ms.length) return
        let a = ms.findIndex(m => m.id === anchorId)
        if (a < 0) a = Math.max(store.index, 0)
        if (a === i) { clear(); store.picked = ms[i].id; return }
        set(ms.slice(Math.min(a, i), Math.max(a, i) + 1).map(m => m.id), ms[a].id, i)
    }
    function toggle(i) {
        const ms = store.messages
        if (i < 0 || i >= ms.length) return
        const id = ms[i].id
        const base = any ? ids : store.picked ? [store.picked] : []
        const next = base.indexOf(id) >= 0 ? base.filter(p => p !== id) : base.concat([id])
        // One left is just the open message again
        if (next.length <= 1) { clear(); store.picked = next.length ? next[0] : id; return }
        set(ms.filter(m => next.indexOf(m.id) >= 0).map(m => m.id), id, i)
    }
    function all() {
        const ms = store.messages
        if (ms.length < 2) return
        set(ms.map(m => m.id), ms[0].id, Math.max(store.index, 0))
    }

    // Another view, sender or search: a fresh start. The list read again: those gone (archived elsewhere) drop out
    readonly property Connections scope: Connections {
        target: sel.store
        function onViewChanged() { sel.clear() }
        function onFromChanged() { sel.clear() }
        function onSearchChanged() { sel.clear() }
        function onMessagesChanged() {
            if (!sel.any) return
            const left = sel.ids.filter(id => sel.store.messages.some(m => m.id === id))
            if (left.length < (sel.marking ? 1 : 2)) sel.clear()
            else if (left.length !== sel.ids.length) sel.ids = left
        }
    }
    // Back to one: the message where the keys are, shown (and read after a moment, as any)
    onAnyChanged: if (!any) store.load()
}
