import QtQuick
import qs.kit
import "Markdown.js" as Markdown

// The open note: its title and when it was saved in the header, then its Markdown as formatted text to read
// (Markdown.js), or, while it is written in (edit(), Enter), as it is in the file in NoteEditor. A link opens in the
// browser. Apostrophe is still a click away (Open in Apostrophe). The reading keys are shell.qml's, the writing ones
// NoteEditor's.
Item {
    id: root
    required property QtObject c
    required property QtObject store
    property bool onePane: false
    signal back()
    signal message(string text, bool danger)   // for the window's toast
    readonly property var note: store.note
    readonly property int margin: width < 520 ? 24 : 40
    readonly property bool editing: editor.open
    readonly property bool busy: editor.busy     // a save still running: quitting waits for it

    function edit() { if (note && !editing) editor.begin(note.id, store.text) }
    // Back to reading, saved first. Not with a conflict unsettled: leaving would drop the text that wasn't saved.
    function leave() {
        if (!editing) return true
        if (editor.conflicted) {
            message("Saved elsewhere while you wrote: keep yours or theirs first", true)
            return false
        }
        editor.end()
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

    Item {
        id: header
        width: parent.width; height: 62
        AppIconButton {
            id: backButton
            visible: root.onePane
            anchors.left: parent.left; anchors.leftMargin: 16; anchors.verticalCenter: parent.verticalCenter
            c: root.c; glyph: "arrow-left"; tip: "The notes"; keys: "Esc"
            onClicked: root.back()
        }
        Column {
            anchors.left: root.onePane ? backButton.right : parent.left
            anchors.leftMargin: root.onePane ? 12 : root.margin
            anchors.right: editButton.left; anchors.rightMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2
            Text {
                textFormat: Text.PlainText
                width: parent.width; elide: Text.ElideRight
                text: root.note ? root.note.title : ""
                font.family: root.c.font; font.pixelSize: 17; font.weight: Font.Medium; color: root.c.title
            }
            // When it was saved, or while writing whether it is: whole, as it matters more. The path takes what room is
            // left, shortened in the middle.
            Row {
                width: parent.width
                spacing: 12
                Text {
                    id: stateText
                    textFormat: Text.PlainText
                    text: !root.note ? "" : root.editing ? editor.status
                        : Qt.formatDateTime(new Date(root.note.modified), "d MMM yyyy  HH:mm")
                    font.family: root.c.font; font.pixelSize: 11
                    color: editor.conflicted ? root.c.danger : root.c.faint
                }
                Text {
                    textFormat: Text.PlainText
                    width: Math.max(0, parent.width - stateText.width - parent.spacing)
                    elide: Text.ElideMiddle
                    text: root.note ? root.store.folder + "/" + root.note.id : ""
                    font.family: root.c.font; font.pixelSize: 11; color: root.c.faint
                }
            }
        }
        // Reading: Edit and Apostrophe. Writing: Done, or with a conflict its two ways out.
        Row {
            id: editButton
            visible: !!root.note
            anchors.right: parent.right; anchors.rightMargin: 20; anchors.verticalCenter: parent.verticalCenter
            spacing: 8
            readonly property bool narrow: root.width < 520
            AppIconButton {
                visible: !root.editing
                c: root.c; glyph: "external-link"; tip: "Open in Apostrophe"; keys: "⇧⏎"
                onClicked: root.store.edit()
            }
            AppButton {
                visible: !root.editing
                c: root.c; glyph: "pencil"; label: editButton.narrow ? "" : "Edit"; strong: true
                tip: "Write in it here"; keys: "⏎  e"
                onClicked: root.edit()
            }
            AppButton {
                visible: editor.conflicted
                c: root.c; glyph: "rotate-ccw"; label: editButton.narrow ? "" : "Keep theirs"
                tip: "Drop what you wrote since, take the saved one"
                onClicked: editor.keepTheirs()
            }
            AppButton {
                visible: editor.conflicted
                c: root.c; glyph: "save"; label: editButton.narrow ? "" : "Keep mine"; strong: true
                tip: "Write yours over the one saved elsewhere"; keys: "⌘S"
                onClicked: editor.keepMine()
            }
            AppButton {
                visible: root.editing && !editor.conflicted
                c: root.c; glyph: "check"; label: editButton.narrow ? "" : "Done"
                tip: "Back to reading (it saves by itself)"; keys: "Esc"
                onClicked: root.leave()
            }
        }
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: root.c.divider }
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
    }

    Flickable {
        id: flick
        visible: !root.editing
        anchors.top: header.bottom; anchors.bottom: parent.bottom
        width: parent.width
        clip: true
        contentHeight: Math.max(page.implicitHeight + 64, height)   // the whole view takes the double click
        boundsBehavior: Flickable.StopAtBounds
        // A double click writes in the note (the cursor at its end, as Edit: a place in the formatted text doesn't map
        // to one in the Markdown). Inside the Flickable, which would take the press from a handler outside it.
        TapHandler {
            enabled: !!root.note
            onDoubleTapped: root.edit()
        }
        Text {
            id: page
            x: root.margin; y: 24
            width: Math.min(root.width - 2 * root.margin, 760)
            wrapMode: Text.Wrap
            textFormat: Text.RichText
            text: Markdown.html(root.body, root.c)
            font.family: root.c.font; font.pixelSize: 14
            color: root.c.body
            onLinkActivated: link => { if (/^(https?:\/\/|mailto:)/i.test(link)) Qt.openUrlExternally(link) }
            HoverHandler { cursorShape: page.hoveredLink ? Qt.PointingHandCursor : Qt.ArrowCursor }
        }
    }

    // The address a hovered link goes to, as a browser shows it: a link's text can name another address than its own
    // (a note Claude wrote, or one from the web), and this is the one a click opens (#1930)
    Rectangle {
        visible: page.hoveredLink !== ""
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
        text: root.store.error || (root.store.notes.length ? "Pick a note to read it."
            : "No notes in " + root.store.folder + " yet.\nWrite one in Apostrophe, or ask Claude to.")
        font.family: root.c.font; font.pixelSize: 13; color: root.c.faint
    }
}
