import QtQuick
import qs.kit
import "Markdown.js" as Markdown

// The open note, laid out as Mail's message: its buttons in the bar at the top (NoteBar), then its header (NoteHeader:
// title, when it was saved, its file) and its Markdown as formatted text to read (Markdown.js), scrolling together; or,
// while it is written in (edit(), Enter), the text as it is in the file in NoteEditor under the bar. A link opens in the
// browser. Apostrophe is still a click away (Open in Apostrophe). The reading keys are shell.qml's, the writing ones
// NoteEditor's.
Item {
    id: root
    required property QtObject c
    required property QtObject store
    property bool onePane: false
    property var marks: []                     // a search's words, marked where they are in the note (Markdown.mark)
    signal back()
    signal newNote()                           // New: an untitled note, written in at once (shell.qml)
    signal rename()                            // Rename and Trash: shell.qml's, which wait for a save running
    signal trash()
    signal message(string text, bool danger)   // for the window's toast
    signal tagPicked(string tag)               // a #tag clicked in the note: its notes in the list (Store.pickTag)
    signal wroteIn(string id, string was)      // NoteEditor's: its file may follow its title (shell.qml)
    readonly property var note: store.note
    readonly property int margin: width < 520 ? 24 : 40
    readonly property bool editing: editor.open
    readonly property bool busy: editor.busy || boxes.busy     // a save still running: quitting waits for it

    // Not before the note's file has been read: the editor would start from an empty text
    function edit() { if (note && !editing && store.textId === note.id) editor.begin(note.id, store.text, false, note.title) }
    // A note New has just made (notes create's answer): written in at once, its title first
    function editNew(note) { editor.begin(note.id, note.text, true, note.title) }
    // Back to reading, saved first. Not with a conflict unsettled: leaving would drop the text that wasn't saved.
    // refile: NoteEditor.end's
    function leave(refile) {
        if (!editing) return true
        if (editor.conflicted) {
            message("Saved elsewhere while you wrote: keep yours or theirs first", true)
            return false
        }
        editor.end(refile)
        forceActiveFocus()
        return true
    }
    function flush(close) { editor.flush(close) }

    // The heading the note starts with is its title, which the header shows already
    readonly property string body: {
        const t = store.text
        const m = t.match(/^\s*#{1,6}\s+(.+?)\s*#*\s*(\n|$)/)
        return m && note && m[1] === note.title ? t.slice(m[0].length) : t
    }
    function scroll(d) { flick.contentY = Math.max(0, Math.min(flick.contentHeight - flick.height, flick.contentY + d)) }
    function home() { flick.contentY = 0 }

    NoteBar {
        id: header
        width: parent.width
        c: root.c
        onePane: root.onePane
        editing: root.editing
        hasNote: !!root.note
        conflicted: editor.conflicted
        status: editor.status
        margin: root.margin
        onBack: root.back()
        onEdit: root.edit()
        onNewNote: root.newNote()
        onRename: root.rename()
        onTrash: root.trash()
        onApostrophe: root.store.edit()
        onKeepTheirs: editor.keepTheirs()
        onKeepMine: editor.keepMine()
        onDone: root.leave()
    }

    NoteEditor {
        id: editor
        visible: open
        anchors.top: header.bottom; anchors.bottom: parent.bottom
        width: parent.width
        c: root.c
        store: root.store
        margin: root.margin
        onDone: root.leave()
        onMessage: (text, danger) => root.message(text, danger)
        onWroteIn: (id, was) => root.wroteIn(id, was)
    }

    TaskBoxes { id: boxes; store: root.store; onMessage: (text, danger) => root.message(text, danger) }

    Flickable {
        id: flick
        visible: !root.editing
        anchors.top: header.bottom; anchors.bottom: parent.bottom
        width: parent.width
        clip: true
        contentHeight: Math.max(page.y + page.implicitHeight + 40, height)   // the whole view takes the double click
        boundsBehavior: Flickable.StopAtBounds
        // A double click writes in the note (the cursor at its end, as Edit: a place in the formatted text doesn't map
        // to one in the Markdown). Inside the Flickable, which would take the press from a handler outside it.
        TapHandler {
            enabled: !!root.note
            onDoubleTapped: root.edit()
        }
        // The note's title, date and file over its text, scrolling with it as a message's header does in Mail
        NoteHeader {
            id: noteHeader
            visible: !!root.note
            x: root.margin; y: 28
            width: page.width
            c: root.c
            note: root.note
            folder: root.store.folder
        }
        Text {
            id: page
            x: root.margin; y: noteHeader.visible ? noteHeader.y + noteHeader.height + 24 : 24
            width: Math.min(root.width - 2 * root.margin, 760)
            wrapMode: Text.Wrap
            textFormat: Text.RichText
            text: Markdown.mark(Markdown.html(root.body, root.c), root.marks, root.c)
            font.family: root.c.font; font.pixelSize: 14
            color: root.c.body
            onLinkActivated: link => {
                if (/^box:\d+$/.test(link)) boxes.toggle(+link.slice(4))
                else if (link.startsWith("tag:")) root.tagPicked(link.slice(4))
                else if (/^(https?:\/\/|mailto:)/i.test(link)) Qt.openUrlExternally(link)
            }
            HoverHandler { cursorShape: page.hoveredLink ? Qt.PointingHandCursor : Qt.ArrowCursor }
        }
    }

    // The address a hovered link goes to, as a browser shows it: a link's text can name another address than its own
    // (a note Claude wrote, or one from the web), and this is the one a click opens (#1930)
    Rectangle {
        visible: page.hoveredLink !== "" && !/^(box|tag):/.test(page.hoveredLink)
        anchors.left: parent.left; anchors.bottom: parent.bottom; anchors.margins: 8
        width: Math.min(linkText.implicitWidth + 20, parent.width - 16); height: linkText.implicitHeight + 10
        radius: 6; color: root.c.solid; border.width: 1; border.color: root.c.divider
        Text {
            id: linkText
            anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 10
            verticalAlignment: Text.AlignVCenter; elide: Text.ElideMiddle
            textFormat: Text.PlainText
            text: page.hoveredLink
            font.family: root.c.font; font.pixelSize: 11; color: root.c.dim
        }
    }

    Text {
        visible: root.store.loaded && !root.note
        anchors.centerIn: parent
        width: Math.min(parent.width - 48, 380)
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        text: root.store.error || (root.store.notes.length ? root.store.shown.length ? "Pick a note to read it." : ""
            : "No notes in " + root.store.folder + " yet.\nNew (n) writes one, and Claude can too.")
        font.family: root.c.font; font.pixelSize: 13; color: root.c.faint
    }
}
