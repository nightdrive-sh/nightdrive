import QtQuick
import Quickshell
import "AskClaudeHistory.js" as Hist

// Ask Claude's earlier conversations in its own card (Dashboard #3713): ⌘H in the field puts this list where the
// conversation and the field were (the user's pick over a list with the field as its search), one line a conversation,
// the newest first: its first request, and on the right its age, "open" or "working…" (and how it ended when not well).
// ↑↓ or j k move, Enter or l brings one back into the card as it was (AskClaudeSession.open), Esc, h or ⌘H go back to
// the conversation. Searching the requests is the launcher's Ask Claude › History (AskClaudeHistoryLevels.qml), which
// reads the same `ask-claude list --json`.
FocusScope {
    id: h
    property int maxHeight: 400
    property int fontSize: 15
    property color selColor: Theme.sel
    signal back()
    signal opened()
    signal refused()          // another conversation is running: there is one at a time (the card plays the error sound)

    readonly property var session: AskClaudeSession
    readonly property string script: Quickshell.env("HOME") + "/.config/hypr/scripts/ask-claude"
    property var convs: []        // [{ id, title, started, last, turns, status, results }], times in ms
    property bool loaded: false
    property string note: ""      // under the list: why Enter did nothing

    // --- Tunables ---
    readonly property int rowH: Math.round(fontSize * 2.7)   // roomy: the user's ask, a list to read, not a menu
    readonly property int rowPad: 14         // the text from the selection's edges
    readonly property int maxRows: 12        // then it scrolls
    readonly property int headGap: 12        // the title line to the list
    readonly property int headTop: 4         // above the title, beside the card's own pad

    readonly property real listH: Math.min(Math.max(1, convs.length), maxRows) * rowH
    implicitHeight: Math.min(maxHeight, head.height + headGap + listH + (note !== "" ? noteText.height + headGap : 0))

    // Read the list afresh and take the keys: the open conversation selected, else the newest
    function start() {
        note = ""
        listProc.running = true
        forceActiveFocus()
    }
    function select() {
        const i = convs.findIndex(c => c.id === session.sessionId)
        list.currentIndex = i >= 0 ? i : 0
        list.positionViewAtIndex(list.currentIndex, ListView.Contain)
    }
    function openCurrent() {
        const c = convs[list.currentIndex]
        if (!c) return
        if (!session.open(c.id)) {
            note = "Claude is working on another request: open this when it's done"
            refused()
            return
        }
        opened()
    }
    function move(by) {
        if (!convs.length) return
        list.currentIndex = Math.max(0, Math.min(convs.length - 1, list.currentIndex + by))
        note = ""
    }

    Keys.onPressed: event => {
        const cmd = event.modifiers & (Qt.ControlModifier | Qt.MetaModifier)
        const k = event.key
        if (k === Qt.Key_Down || (!cmd && k === Qt.Key_J)) move(1)
        else if (k === Qt.Key_Up || (!cmd && k === Qt.Key_K)) move(-1)
        else if (k === Qt.Key_PageDown) move(maxRows - 1)
        else if (k === Qt.Key_PageUp) move(-(maxRows - 1))
        else if (k === Qt.Key_Home) move(-convs.length)
        else if (k === Qt.Key_End) move(convs.length)
        else if (k === Qt.Key_Return || k === Qt.Key_Enter || (!cmd && k === Qt.Key_L)) openCurrent()
        else if (k === Qt.Key_Escape || (!cmd && k === Qt.Key_H) || (cmd && k === Qt.Key_H)) back()
        else return
        event.accepted = true
    }

    Item {
        id: head
        width: parent.width
        height: h.headTop + title.height
        // A menu's section title (MenuSection): capitals in the theme colour, the count dimmed on the right
        Text {
            id: title
            x: h.rowPad
            y: h.headTop
            text: "HISTORY"
            color: Theme.primary
            font { family: Theme.font; pixelSize: h.fontSize - 3; letterSpacing: 0.6 }
        }
        Text {
            anchors { right: parent.right; rightMargin: h.rowPad; baseline: title.baseline }
            text: h.convs.length ? (h.convs.length + (h.convs.length === 1 ? " chat" : " chats") + " · 7 days").toUpperCase() : ""
            color: Theme.dim
            font { family: Theme.font; pixelSize: h.fontSize - 4; letterSpacing: 0.6 }
        }
    }

    ListView {
        id: list
        y: head.height + h.headGap
        width: parent.width
        height: Math.min(h.listH, h.maxHeight - y - (h.note !== "" ? noteText.height + h.headGap : 0))
        clip: true
        model: h.convs
        boundsBehavior: Flickable.StopAtBounds
        highlightMoveDuration: 0
        highlight: Rectangle { color: h.selColor; radius: 4 }
        delegate: Item {
            id: row
            required property var modelData
            required property int index
            readonly property bool current: ListView.isCurrentItem
            width: list.width
            height: h.rowH
            Text {
                anchors { left: parent.left; leftMargin: h.rowPad; right: age.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
                text: (row.modelData.title || "(no text)").replace(/\s+/g, " ")
                elide: Text.ElideRight
                color: row.current ? Theme.accent : Theme.text
                font { family: Theme.font; pixelSize: h.fontSize }
            }
            Text {
                id: age
                anchors { right: parent.right; rightMargin: h.rowPad; verticalCenter: parent.verticalCenter }
                readonly property string failed: Hist.failure(row.modelData)
                text: (failed !== "" ? failed + " · " : "") + Hist.when(row.modelData, h.session.sessionId)
                // Red only when it went wrong: stopped was your own doing
                color: failed !== "" && row.modelData.status !== "cancelled" ? Theme.danger : Theme.dim
                font { family: Theme.font; pixelSize: h.fontSize - 3 }
            }
            MouseArea {
                anchors.fill: parent
                onClicked: { list.currentIndex = row.index; h.openCurrent() }
            }
        }
    }
    Text {
        visible: h.convs.length === 0
        x: h.rowPad
        y: list.y + (h.rowH - height) / 2
        text: h.loaded ? "No Ask Claude conversations in the last 7 days" : "Reading the conversations…"
        color: Theme.dim
        font { family: Theme.font; pixelSize: h.fontSize - 2 }
    }
    Text {
        id: noteText
        visible: h.note !== ""
        x: h.rowPad
        y: list.y + list.height + h.headGap
        width: parent.width - 2 * h.rowPad
        wrapMode: Text.Wrap
        text: h.note
        color: Theme.warning
        font { family: Theme.font; pixelSize: h.fontSize - 3 }
    }

    Sh {
        id: listProc
        command: [h.script, "list", "--json"]
        onResult: text => {
            let l = []
            try { l = JSON.parse(text) } catch (e) {}
            h.convs = Array.isArray(l) ? l.filter(c => c && typeof c.id === "string") : []
            h.loaded = true
            h.select()
        }
    }
}
