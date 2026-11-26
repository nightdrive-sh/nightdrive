import QtQuick
import "ListEdit.js" as ListEdit

// A task box ticked or unticked with a click while reading (NoteView.qml; Markdown.html draws each box as a link,
// "box:K", the K-th box of the note). Only that one character of the file changes, "[ ]" ↔ "[x]", saved as the editor
// saves (NoteSaver: only over the text that was read, so a change made elsewhere meanwhile is never written over). The
// box shows ticked at once; if the save doesn't go through, the note is shown as its file has it again.
Item {
    id: root
    required property QtObject store
    signal message(string text, bool danger)   // for the window's toast

    readonly property bool busy: saver.busy

    function toggle(k) {
        const note = store.note
        if (!note || store.textId !== note.id) return
        const before = store.text
        const after = ListEdit.toggle(before, k)
        if (after === null) return
        store.text = after
        saver.save(note.id, after, before)
    }

    function reread() { store.reread() }

    NoteSaver {
        id: saver
        command: root.store.command
        onConflict: (id, text) => { root.message("Not ticked: " + id + " was changed elsewhere meanwhile", true); root.reread() }
        onFailed: (id, message) => { root.message(message, true); root.reread() }
    }
}
