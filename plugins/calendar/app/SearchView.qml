import QtQuick
import Quickshell.Io
import qs.kit
import "Dates.js" as Dates

// Search (/): the events whose title, place or notes have every word typed, half a year back and ahead of today, under
// their days as the agenda shows them. `calendar events --search` finds them, the same as Claude's calendar_events, so the
// window and Claude find the same events. The sidebar's calendar narrows them as it does the views.
// The keys: typing searches (a moment after the last key), ↓ or ⏎ go down to the results, where ↑ ↓ j k move and ⏎ opens;
// / goes back to the words, Esc leaves the search.
FocusScope {
    id: root
    required property var app           // the window: command, today, sources, source, openEvent(), say()
    required property QtObject c
    signal closed()

    readonly property int back: 182     // days before today searched, and after: a year in all, under events.py's 400
    readonly property int ahead: 183
    readonly property string from: Dates.iso(Dates.addDays(Dates.parse(app.today), -back))
    readonly property string to: Dates.iso(Dates.addDays(Dates.parse(app.today), ahead))

    property string query: ""           // the words searched last (results are theirs)
    property var found: []
    property bool again: false          // words changed while a search ran: search once more when it ends
    readonly property bool busy: finder.running || typing.running

    // The results of the sidebar's calendar, by the day each begins
    readonly property var groups: {
        const only = (app.sources[app.source] || {}).id || ""
        const out = []
        for (const e of found) {
            if (only && e.calendar !== only) continue
            const d = e.start.slice(0, 10)
            if (!out.length || out[out.length - 1].day !== d) out.push({ day: d, events: [] })
            out[out.length - 1].events.push(e)
        }
        return out
    }
    readonly property int shown: groups.reduce((n, g) => n + g.events.length, 0)

    property alias text: field.text
    function open() { field.forceActiveFocus() }
    function focusList() { if (list.eventCount) list.forceActiveFocus(); else field.forceActiveFocus() }
    function search() {
        const q = field.text.trim()
        if (!q) { query = ""; found = []; return }
        if (finder.running) { again = true; return }
        query = q
        finder.command = [app.command, "events", "--json", "--limit", "100000", "--search", q, from, to]
        finder.running = true
    }

    Timer { id: typing; interval: 300; onTriggered: root.search() }
    Process {
        id: finder
        stdout: StdioCollector {
            onStreamFinished: {
                let d
                try { d = JSON.parse(text) } catch (e) { return }
                root.found = d.events
                // The first one from today on, as the agenda starts there; else the last before it
                const all = [].concat(...root.groups.map(g => g.events))
                const i = all.findIndex(e => Dates.lastDay(e) >= root.app.today)
                list.current = i >= 0 ? i : Math.max(0, root.shown - 1)
                Qt.callLater(list.keepInView)
            }
        }
        stderr: StdioCollector { onStreamFinished: if (text.trim()) root.app.say(text.trim().split("\n").pop(), false, true) }
        onExited: if (root.again) { root.again = false; root.search() }
    }

    Item {
        id: top
        x: 12; width: parent.width - 24; height: 64
        AppSearchField {
            id: field
            x: 10; y: 12; width: parent.width - 20
            focus: true
            c: root.c
            placeholder: "Search titles, places and notes"
            onEdited: typing.restart()
            onReturnPressed: { if (typing.running) { typing.stop(); root.search() } root.focusList() }
            onDownPressed: root.focusList()
            onEscapePressed: root.closed()
        }
        // What was searched, and where: the span says what a search doesn't reach
        Text {
            x: 10 + 25; anchors.bottom: parent.bottom; anchors.bottomMargin: 4
            width: parent.width - x - 10; elide: Text.ElideRight
            readonly property string span: Regional.range(root.from, Dates.addDays(Dates.parse(root.to), -1))
            text: root.busy && field.text.trim() ? "Searching…"
                : root.query ? (root.shown === 1 ? "1 event" : root.shown + " events") + "  ·  " + span
                : span
            color: root.c.faint; font.family: root.c.font; font.pixelSize: 11
        }
    }
    Rectangle { anchors.top: top.bottom; anchors.topMargin: 6; width: parent.width; height: 1; color: root.c.divider }

    AgendaList {
        id: list
        anchors.top: top.bottom; anchors.topMargin: 10
        anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
        anchors.leftMargin: 12; anchors.rightMargin: 12; anchors.bottomMargin: 8
        app: root.app
        c: root.c
        groups: root.groups
        active: activeFocus
        empty: root.query && !root.busy ? "Nothing found for “" + root.query + "”." : ""
        Keys.onPressed: e => {
            if (list.key(e)) e.accepted = true
            else if (e.key === Qt.Key_PageDown || e.key === Qt.Key_PageUp) { list.move(e.key === Qt.Key_PageDown ? 10 : -10); e.accepted = true }
            else if (e.key === Qt.Key_Slash || e.text === "/") { root.open(); e.accepted = true }
            else if (e.key === Qt.Key_Escape) { root.closed(); e.accepted = true }
        }
    }
}
