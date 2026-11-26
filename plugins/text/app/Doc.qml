import QtQuick
import Quickshell.Io
import qs

// One open file: its text in a field of its own (so each file keeps its own undo, cursor and scroll while another is
// shown), saved on ⌘S through lib/textfile.py. Nothing is saved by itself: a config file half written would be read by
// whatever watches it (Hyprland, Quickshell reload on save), so the file changes only when the user says so.
//
// base is the text the file had when last read or written. The file is watched: changed elsewhere while nothing here is
// unsaved, the field takes the new text; with unsaved changes it is a conflict for the user to settle (DocBar: keep
// mine, or take theirs). A save is only written over base (--expect), never over a change made meanwhile unasked.
Item {
    id: root
    required property QtObject c
    required property string script            // lib/textfile.py
    property string path: ""
    property string name: ""
    property string dir: ""
    property bool crlf: false
    property bool writable: true
    property string base: ""
    property bool dirty: false
    property bool conflicted: false
    property bool gone: false                   // the file was removed or renamed elsewhere: ⌘S writes it again
    readonly property bool busy: io.busy
    readonly property alias area: area
    signal message(string text, bool danger)
    signal saved()

    readonly property string status: gone ? "Removed elsewhere" : conflicted ? "Changed elsewhere"
        : !writable ? "Read only" : io.busy ? "Saving…" : dirty ? "Edited" : ""

    // info: textfile.py read's answer
    function load(info) {
        path = info.path; name = info.name; dir = info.dir; crlf = info.crlf; writable = info.writable
        base = info.text
        area.text = info.text
        area.cursorPosition = 0
        dirty = false
    }

    // The unsaved text kept when the window closed (shell.qml): over the file, still unsaved; a conflict if the file
    // has changed since that text started from it
    function restore(text, baseMd5) {
        area.text = text
        dirty = text !== base
        conflicted = dirty && Qt.md5(base) !== baseMd5
    }

    // then(ok): after the save, ok when it was written (quitting and closing wait for it)
    function save(then, force) {
        if (!dirty && !gone) { if (then) then(true); return }
        if (conflicted && !force) {
            message(name + " was changed elsewhere: Keep mine writes over it", true)
            if (then) then(false)
            return
        }
        const text = area.text
        const argv = ["python3", script, "write", path, "--md5", Qt.md5(text)]
            .concat(force || gone ? [] : ["--expect", Qt.md5(base)], crlf ? ["--crlf"] : [])
        io.run(argv, text, (code, out, err) => {
            if (code === 0) {
                base = text
                gone = false; conflicted = false
                dirty = area.text !== base
                saved()
            } else if (code === 3) conflicted = true
            else message(err || name + " wasn't saved", true)
            if (then) then(code === 0)
        })
    }
    function keepMine(then) { save(then, true) }
    function keepTheirs() { conflicted = false; reread(true) }

    // The file changed on disk: read again, and taken in if nothing here is unsaved
    function reread(take) {
        if (io.busy) return                      // our own save: its answer says what the file has
        reader.run(["python3", script, "read", path], null, (code, out, err) => {
            if (code !== 0) {
                if (/isn't there/.test(err)) gone = true
                return
            }
            gone = false
            let info
            try { info = JSON.parse(out) } catch (e) { return }
            writable = info.writable
            if (info.text === base) return
            if (info.text === area.text) { base = info.text; dirty = false }
            else if (!dirty || take) replace(info.text)
            else conflicted = true
        })
    }
    // The text replaced (taken from the file), the cursor kept where it was as far as it can be
    function replace(text) {
        const at = area.cursorPosition, top = flick.contentY
        base = text
        area.text = text
        area.cursorPosition = Math.min(at, text.length)
        flick.contentY = Math.min(top, Math.max(0, flick.contentHeight - flick.height))
        dirty = false
    }

    // Find: the next place with what (case aside) after the cursor, or before it (back); round past the end. False
    // when it isn't in the text at all.
    function find(what, back) {
        if (!what) return false
        const t = area.text.toLowerCase(), w = what.toLowerCase()
        let i
        if (back) {
            i = t.lastIndexOf(w, area.selectionStart - 1)
            if (i < 0) i = t.lastIndexOf(w)
        } else {
            i = t.indexOf(w, area.selectionEnd)
            if (i < 0) i = t.indexOf(w)
        }
        if (i < 0) return false
        area.select(i, i + w.length)
        return true
    }
    function focusText() { area.forceActiveFocus() }

    Run { id: io }
    Run { id: reader }
    // Quickshell has a watcher for one file: an outside save (another editor, Claude, git) shows at once
    FileView {
        path: root.path
        preload: false
        watchChanges: true
        printErrors: false
        onFileChanged: root.reread(false)
    }

    Flickable {
        id: flick
        TouchScroll { view: flick }
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
            x: 28; y: 16
            width: flick.width - 56
            height: Math.max(implicitHeight, flick.height - 64)
            textFormat: TextEdit.PlainText
            wrapMode: TextEdit.WrapAnywhere     // long lines (JSON, CSV) wrap rather than scroll sideways
            selectByMouse: true
            persistentSelection: true
            readOnly: !root.writable
            activeFocusOnTab: false             // Tab is a tab in the text
            tabStopDistance: fm.advanceWidth(" ") * 4
            font.family: root.c.font; font.pixelSize: 14
            color: root.c.body
            selectionColor: Qt.rgba(root.c.primary.r, root.c.primary.g, root.c.primary.b, 0.35)
            selectedTextColor: root.c.title
            cursorDelegate: Rectangle { width: 2; color: root.c.primary; visible: area.cursorVisible }
            onCursorRectangleChanged: flick.follow(cursorRectangle)
            onTextChanged: root.dirty = text !== root.base
            FontMetrics { id: fm; font: area.font }
        }
    }
}
