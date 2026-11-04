import QtQuick

// Writing a note in the window: its Markdown as it is in the file, in a text field where the reading view was (the
// same font, width and margins, so the note doesn't jump). Raw Markdown rather than formatted text: Qt's own Markdown
// editing would write every note back in its own dialect, and a note is the user's plain file.
//
// It saves by itself a moment after typing stops, and whenever it is left (Esc, another note, quitting: flush()),
// through NoteSaver. base is the text the file had when the editor last read or wrote it: while the field still holds
// it nothing needs saving, and a save is only written over that text. A change made elsewhere meanwhile (Apostrophe,
// Claude's append) is taken in when nothing here is unsaved, and otherwise held as a conflict for the user to settle:
// keep theirs or keep mine (NoteView's header).
//
// A note made here (New) and left empty, its heading alone or nothing at all, is deleted when the editor leaves it
// rather than kept as clutter in the folder: by `notes discard`, only while the file is still what the editor last saw.
// Any other note left says so (wroteIn), with the title it had when writing began: the window then names its file
// after the title it has now, if it was named after that one (`notes refile`): a new note is "Untitled.md" until then.
Item {
    id: root
    required property QtObject c
    required property QtObject store
    required property int margin
    signal done()                              // Esc: back to reading
    signal message(string text, bool danger)   // for the window's toast
    signal wroteIn(string id, string was)      // a note written in, left and saved: was is its title at begin()

    property string noteId: ""                 // the note being written, fixed while the editor is open
    property string was: ""                    // its title when writing began
    property string base: ""
    property bool conflicted: false
    readonly property bool open: noteId !== ""
    readonly property bool dirty: open && area.text !== base
    readonly property bool busy: saver.busy
    property string fresh: ""                  // a new note's text as notes create made it; "" for any other note
    readonly property bool blankNew: open && fresh !== "" && (area.text.trim() === "" || area.text.trim() === fresh.trim())
    // The title as it is being written, for the header: the first line's heading
    readonly property string heading: {
        const m = area.text.match(/^\s*#{1,6}[ \t]+(.*?)[ \t#]*(\n|$)/)
        return m ? m[1] : ""
    }
    readonly property string status: conflicted ? "Changed elsewhere" : blankNew ? "New: kept once you write in it"
        : saver.busy ? "Saving…" : dirty ? "Edited" : "Saved"

    readonly property int saveDelay: 800       // ms after the last key: soon enough that little is ever unsaved

    // isNew: made by New just now, so the cursor goes after its "# " (its title to write) or below its heading, and
    // the note goes again if it is left empty
    function begin(id, text, isNew, title) {
        noteId = id
        was = title
        base = text
        fresh = isNew ? text : ""
        conflicted = false
        area.text = text
        help.reset()
        // At the end, past the last newline: a note is mostly added to, and the title is at its top. A new one's is
        // all there is, so its line below; or, still to be written, after its "# ".
        const first = text.split("\n")[0]
        area.cursorPosition = !isNew ? text.replace(/\s+$/, "").length : /^#+\s*$/.test(first) ? first.length : text.length
        area.forceActiveFocus()
    }
    // closing: the window is going, so text that can't be saved into its note goes into a note of its own
    property bool closing: false
    function flush(close) {
        autosave.stop()
        if (close) closing = true
        if (blankNew && closing) discard()
        else if (dirty && conflicted && closing) aside()
        else if (dirty && !conflicted) saver.save(noteId, area.text, base)
    }
    function aside() { saver.keepAside(noteId, store.note ? store.note.title : noteId, area.text) }
    // refile false: the window renames or trashes the note next, so its file isn't named after its title first
    function end(refile) {
        if (blankNew) discard()
        else { flush(); if (refile !== false) wroteIn(noteId, was) }
        noteId = ""; fresh = ""; conflicted = false
    }
    // Out of the list at once; the list read again once the file is gone, or kept (saved elsewhere meanwhile)
    function discard() { saver.discard(noteId, base); store.drop(noteId) }

    // The conflict's two ways out
    function keepMine() { conflicted = false; saver.save(noteId, area.text, null) }
    function keepTheirs() { conflicted = false; take(store.text) }

    // The text in the field replaced (a change from elsewhere), the cursor kept where it was as far as it can be
    function take(text) {
        const at = area.cursorPosition
        base = text
        area.text = text
        help.reset()
        area.cursorPosition = Math.min(at, text.length)
    }

    // The file changed: Store has read it again (its FileView watches it). Not while a save of ours runs: the file then
    // holds our own text, and the save's answer says what it wrote.
    function outside() {
        if (!open || saver.busy || !store.note || store.note.id !== noteId || store.textId !== noteId) return
        const t = store.text
        if (t === base) return
        if (t === area.text) base = t                  // the file has what the field has
        else if (!dirty) take(t)
        else conflicted = true
    }
    Connections { target: root.store; function onTextChanged() { root.outside() } }

    NoteSaver {
        id: saver
        command: root.store.command
        onSaved: (id, text, note) => {
            if (id !== root.noteId) return
            root.base = text
            root.outside()                              // anything saved elsewhere since
        }
        onConflict: (id, text) => {
            if (id !== root.noteId) {
                root.message("Not saved: " + id + " was changed elsewhere meanwhile", true)
                return
            }
            root.conflicted = true
            if (root.closing) root.aside()
        }
        onSetAside: (id, note) => root.message("Changed elsewhere: what you wrote is in " + note.id, false)
        onFailed: (id, message) => root.message(message, true)
        onDiscarded: (id, gone) => root.store.refresh()
    }

    // Lists, bold, italic and links as one types (EditorHelp.qml): the editor's keys go there first
    EditorHelp { id: help; area: area }

    Timer { id: autosave; interval: root.saveDelay; onTriggered: root.flush() }

    Flickable {
        id: flick
        anchors.fill: parent
        clip: true
        contentHeight: area.y + area.height + 48
        boundsBehavior: Flickable.StopAtBounds

        // The cursor stays in sight as it moves or the text grows under it
        function follow(r) {
            const top = area.y + r.y, bottom = top + r.height
            if (top < contentY + 12) contentY = Math.max(0, top - 12)
            else if (bottom > contentY + height - 24) contentY = bottom - height + 24
        }

        // A click below the text puts the cursor at its end, as in any editor
        TapHandler { onTapped: { area.forceActiveFocus(); area.cursorPosition = area.length } }

        TextEdit {
            id: area
            x: root.margin; y: 24
            width: Math.min(root.width - 2 * root.margin, 760)
            height: Math.max(implicitHeight, flick.height - 72)
            textFormat: TextEdit.PlainText
            wrapMode: TextEdit.Wrap
            selectByMouse: true
            persistentSelection: true
            font.family: root.c.font; font.pixelSize: 14
            color: root.c.body
            selectionColor: Qt.rgba(root.c.primary.r, root.c.primary.g, root.c.primary.b, 0.35)
            selectedTextColor: root.c.title
            cursorDelegate: Rectangle { width: 2; color: root.c.primary; visible: area.cursorVisible }
            onCursorRectangleChanged: flick.follow(cursorRectangle)
            onTextChanged: if (root.dirty && !root.conflicted) autosave.restart()

            Keys.onPressed: e => {
                if (help.key(e)) { e.accepted = true; return }
                const ctrl = e.modifiers & (Qt.ControlModifier | Qt.MetaModifier)
                if (e.key === Qt.Key_Escape) root.done()
                // Said in the toast as well: it has mostly saved by itself already, and the bar's "Saved" wouldn't change
                else if (ctrl && e.key === Qt.Key_S) {
                    if (root.conflicted) root.keepMine()
                    else { root.flush(); root.message("Saved", false) }
                }
                else return
                e.accepted = true
            }
        }
    }
}
