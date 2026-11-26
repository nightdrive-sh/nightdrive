import QtQuick
import QtQuick.Layouts
import qs.kit

// The sidebar: Inbox, Unread and Archive, then who the messages are from, as `nightdrive inbox list` groups them
// (config/inbox/query.py): each project Claude's sessions worked in, each app, and Other (a terminal, a script). A click
// narrows the list to that sender; one session's messages are reached from a message (its sender line), and show here
// as a row of their own while picked. From the keyboard (Tab, shell.qml): ↑ ↓ pick, ⏎ Esc or Tab back to the messages.
AppSidebar {
    id: root
    required property QtObject store
    property bool active: false          // the keyboard is here: the picked row has the kit's frame
    signal done()                        // back to the messages (the keyboard's)
    signal chosen()                      // a click picked a row: a narrow window shows the list again
    title: "Inbox"

    readonly property var views: [
        { key: "inbox", glyph: "mailbox", label: "Inbox" },
        { key: "unread", glyph: "mail", label: "Unread" },
        { key: "archive", glyph: "archive", label: "Archive" }
    ]
    // Every row in order, for the keys
    readonly property bool sessionPicked: store.from.startsWith("session:")
    readonly property var entries: views.map(v => ({ view: v.key, from: "" }))
        .concat(sessionPicked ? [{ view: store.view, from: store.from, label: store.fromLabel }] : [])
        .concat(store.senders.map(s => ({ view: store.view, from: s.key, label: s.label })))
    readonly property int current: store.from ? entries.findIndex(e => e.from === store.from)
                                              : entries.findIndex(e => !e.from && e.view === store.view)
    function pick(e) { if (e.from) store.pickFrom(e.from, e.label); else store.pickView(e.view) }
    function step(d) { pick(entries[Math.max(0, Math.min(entries.length - 1, current + d))]) }
    function glyphOf(kind) { return kind === "claude" ? "folder-code" : kind === "app" ? "app-window" : "square-terminal" }

    Keys.onPressed: e => {
        const k = e.key
        if (k === Qt.Key_Down || k === Qt.Key_J) step(1)
        else if (k === Qt.Key_Up || k === Qt.Key_K) step(-1)
        else if (k === Qt.Key_Home) step(-entries.length)
        else if (k === Qt.Key_End) step(entries.length)
        else if ([Qt.Key_Return, Qt.Key_Enter, Qt.Key_Escape, Qt.Key_Tab, Qt.Key_Backtab, Qt.Key_Right].indexOf(k) >= 0) root.done()
        else return
        e.accepted = true
    }

    Flickable {
        id: flick
        TouchScroll { view: flick }
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true
        contentHeight: column.implicitHeight
        boundsBehavior: Flickable.StopAtBounds
        ColumnLayout {
            id: column
            width: flick.width
            spacing: 2

            Repeater {
                model: root.views
                delegate: AppNavRow {
                    required property var modelData
                    required property int index
                    c: root.c
                    glyph: modelData.glyph; label: modelData.label
                    // The inbox's unread count by Inbox and Unread; the archive has none to count
                    count: modelData.key !== "archive" && root.store.unread ? String(root.store.unread) : ""
                    countColor: root.c.primary
                    selected: root.current === index
                    active: root.active
                    onClicked: { root.store.pickView(modelData.key); root.chosen() }
                }
            }

            Section { visible: root.store.senders.length > 0 || root.sessionPicked; text: "From" }
            // One session, picked from a message: here while it is the list's
            AppNavRow {
                visible: root.sessionPicked
                c: root.c
                glyph: "bot"; label: root.store.fromLabel
                selected: true
                active: root.active
            }
            Repeater {
                model: root.store.senders
                delegate: AppNavRow {
                    required property var modelData
                    required property int index
                    c: root.c
                    glyph: root.glyphOf(modelData.kind)
                    label: modelData.label
                    count: modelData.unread ? String(modelData.unread) : ""
                    countColor: root.c.primary
                    selected: root.store.from === modelData.key
                    active: root.active
                    onClicked: { root.store.pickFrom(modelData.key, modelData.label); root.chosen() }
                }
            }
            Item { implicitHeight: 12 }
        }
    }

    component Section: Text {
        Layout.fillWidth: true
        Layout.leftMargin: 28; Layout.topMargin: 14; Layout.bottomMargin: 4
        textFormat: Text.PlainText
        font.family: root.c.font; font.pixelSize: 11; font.weight: Font.Medium
        color: root.c.faint
    }
}
