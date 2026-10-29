import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs
import qs.kit
import "Dates.js" as Dates

// Nightdrive Calendar: the calendars in the sidebar, the month or the week on the right, over the events the sync keeps
// in ~/.local/share/calendar (`calendar events` reads them by khal). Read only for now: events are added and deleted
// with the command, or by Claude (mcp.json), and the window shows them after the sync.
ShellRoot {
    id: shell
    FloatingWindow {
        id: win
        title: "Calendar"
        implicitWidth: 1200
        implicitHeight: 820
        color: c.bg
        // Closing the window (⌘W) quits Calendar, as Contacts
        onClosed: Qt.quit()

        AppLook { id: c }
        readonly property QtObject look: c

        // `calendar sync`, add and delete ask for a reload once they are done
        IpcHandler {
            target: "calendar"
            function refresh(): void { win.reload() }
            function today(): void { win.pickDay(Dates.iso(new Date())) }
            // A day, YYYY-MM-DD (`calendar show DAY`)
            function showDay(day: string): void { if (/^\d{4}-\d{2}-\d{2}$/.test(day)) win.pickDay(day) }
            // "month" or "week" (`calendar month`, `calendar week`)
            function setView(view: string): void { if (view === "month" || view === "week") win.view = view }
        }

        readonly property int headerHeight: 22  // the sidebar's title line and the view's header, as Contacts'
        readonly property string command: Quickshell.shellDir + "/../bin/calendar"

        property var calendars: []          // [{ id, name, color, source, read_only, events }]
        property bool loaded: false
        // The sidebar's rows: every calendar together, then each one
        readonly property var sources: [{ id: "", name: "All calendars", color: "", events: -1 }].concat(calendars)
        property int source: 0
        property string view: "month"       // or "week"
        property string day: Dates.iso(new Date())
        property var events: []             // the range's, every calendar's
        property string range: ""           // "FROM TO" of events, or of the read under way
        // The events by day, of the picked calendar: { "YYYY-MM-DD": [event] }, a multi-day event on each of its days
        readonly property var byDay: {
            const out = {}
            const only = (sources[source] || {}).id || ""
            for (const e of events) {
                if (only && e.calendar !== only) continue
                for (let d = Dates.parse(e.start); Dates.iso(d) <= Dates.lastDay(e); d = Dates.addDays(d, 1)) {
                    const k = Dates.iso(d)
                    ;(out[k] = out[k] || []).push(e)
                }
            }
            return out
        }

        // What the view shows: the month's six weeks, or the week
        function viewRange() {
            const d = Dates.parse(day)
            const from = view === "month" ? Dates.monthDays(d.getFullYear(), d.getMonth())[0] : Dates.monday(d)
            return [Dates.iso(from), Dates.iso(Dates.addDays(from, view === "month" ? 42 : 7))]
        }
        function load(force) {
            const r = viewRange()
            if (!force && r.join(" ") === range) return
            range = r.join(" ")
            reader.command = [command, "events", "--json", "--limit", "100000", r[0], r[1]]
            reader.running = true
        }
        function reload() { calReader.running = true; load(true) }
        onDayChanged: load(false)
        onViewChanged: load(false)

        Process {
            id: calReader
            command: [win.command, "calendars", "--json"]
            stdout: StdioCollector {
                onStreamFinished: {
                    try { win.calendars = JSON.parse(text).calendars } catch (e) { console.warn("calendar calendars: " + e); return }
                    win.loaded = true
                    win.source = Math.min(win.source, win.sources.length - 1)
                }
            }
        }
        Process {
            id: reader
            stdout: StdioCollector {
                id: readOut
                onStreamFinished: {
                    let d
                    try { d = JSON.parse(text) } catch (e) { return }
                    // Only the range asked last: a quick ‹ › ‹ mustn't leave an older month's events on screen
                    if (d.from + " " + d.to === win.range) win.events = d.events
                }
            }
            stderr: StdioCollector { onStreamFinished: if (text.trim()) win.say(text.trim().split("\n").pop()) }
        }
        Component.onCompleted: { calReader.running = true; load(true); keys.forceActiveFocus() }

        function pickDay(d) { day = d }
        function showWeek(d) { day = d; view = "week" }
        // The month or week before (-1) or after (1)
        function page(n) {
            const d = Dates.parse(day)
            day = view === "month" ? Dates.iso(new Date(d.getFullYear(), d.getMonth() + n, 1)) : Dates.iso(Dates.addDays(d, 7 * n))
        }
        function moveDay(n) { day = Dates.iso(Dates.addDays(Dates.parse(day), n)) }
        function pickSource(i) { if (i >= 0 && i < sources.length) source = i }
        function openEvent(e) { eventPanel.show(e) }
        // ⏎ on a day: its first event
        function openFirst() { const list = byDay[day] || []; if (list.length) openEvent(list[0]) }

        readonly property string heading: {
            const d = Dates.parse(day)
            if (view === "month") return Qt.formatDate(d, "MMMM yyyy")
            const m = Dates.monday(d), s = Dates.addDays(m, 6)
            return "Week " + Dates.week(m) + "  ·  " + Qt.formatDate(m, m.getMonth() === s.getMonth() ? "d" : "d MMM") + " – " + Qt.formatDate(s, "d MMM yyyy")
        }

        // A sync from the window (⌘R): the command's, which asks for a reload when it's done
        Process { id: syncer; command: [win.command, "sync"]; onExited: code => win.say(code === 0 ? "Synced" : "The sync didn't finish: calendar sync in a terminal says why") }
        function sync() { if (!syncer.running) { say("Syncing…", true); syncer.running = true } }

        property string note: ""
        function say(t, sticky) { note = t; if (sticky) noteTimer.stop(); else noteTimer.restart() }
        Timer { id: noteTimer; interval: 4000; onTriggered: win.note = "" }

        // The week's line for now, and today's circle, move along with the clock
        property date now: new Date()
        readonly property string today: Dates.iso(now)
        Timer { interval: 60000; running: true; repeat: true; onTriggered: win.now = new Date() }

        Shortcut { sequence: "Ctrl+R"; onActivated: win.sync() }
        Shortcut { sequence: "Ctrl+Q"; onActivated: Qt.quit() }
        Shortcut { sequences: ["Ctrl+B", "Meta+B"]; onActivated: win.sidebarChoice = !win.sidebarShown }

        readonly property int sidebarMin: 820
        property var sidebarChoice: null    // ⌘B's, over what the width says
        readonly property bool sidebarShown: sidebarChoice !== null ? sidebarChoice : width >= sidebarMin

        RowLayout {
            id: content
            anchors.fill: parent
            spacing: 0
            AppPointer { c: win.look }

            AppSidebar {
                Layout.preferredWidth: win.width < 900 ? 168 : 208
                visible: win.sidebarShown
                c: win.look
                title: "Calendar"
                headerHeight: 2 * 18 + win.headerHeight
                contentTop: 18 + win.headerHeight + 30
                bottomMargin: 24
                Repeater {
                    model: win.sources
                    delegate: AppNavRow {
                        id: nav
                        required property var modelData
                        required property int index
                        c: win.look
                        // A calendar's row: its colour inside the glyph's ring
                        glyph: modelData.id ? "circle" : "calendar-days"
                        label: modelData.name
                        selected: index === win.source
                        onClicked: win.pickSource(index)
                        Rectangle {
                            visible: nav.modelData.id !== ""
                            x: 17; anchors.verticalCenter: parent.verticalCenter
                            width: 9; height: 9; radius: 5
                            color: nav.modelData.color || "transparent"
                        }
                    }
                }
                Item { Layout.fillHeight: true }
                Text {
                    textFormat: Text.PlainText
                    Layout.fillWidth: true; Layout.leftMargin: 26; Layout.rightMargin: 12
                    visible: win.note !== ""
                    wrapMode: Text.Wrap
                    text: win.note; color: c.dim; font.family: c.font; font.pixelSize: 11
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 0
                // The month's or week's name, and the buttons
                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: 28; Layout.rightMargin: 18; Layout.topMargin: 16
                    Layout.preferredHeight: win.headerHeight
                    spacing: 8
                    Text {
                        Layout.fillWidth: true
                        text: win.heading
                        color: c.title; font.family: c.font; font.pixelSize: 15; font.weight: Font.Medium
                    }
                    AppIconButton { c: win.look; glyph: "chevron-left"; tip: win.view === "month" ? "Previous month" : "Previous week"; keys: "PgUp"; tipAlign: "right"; onClicked: win.page(-1) }
                    AppButton { c: win.look; label: "Today"; tip: "Go to today"; keys: "t"; onClicked: win.pickDay(Dates.iso(new Date())) }
                    AppIconButton { c: win.look; glyph: "chevron-right"; tip: win.view === "month" ? "Next month" : "Next week"; keys: "PgDn"; tipAlign: "right"; onClicked: win.page(1) }
                    Item { width: 10 }
                    AppButton { c: win.look; label: "Month"; on: win.view === "month"; tip: "The month"; keys: "m"; onClicked: win.view = "month" }
                    AppButton { c: win.look; label: "Week"; on: win.view === "week"; tip: "The week"; keys: "w"; onClicked: win.view = "week" }
                }
                Rectangle { Layout.fillWidth: true; Layout.topMargin: 17; Layout.preferredHeight: 1; color: c.divider }

                FocusScope {
                    id: keys
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    focus: true
                    Keys.onPressed: e => {
                        const k = e.key
                        win.look.moved(e)
                        if (win.cheats && k !== Qt.Key_Question && sheet.modifierKeys.indexOf(k) < 0) win.cheats = false
                        const ctrl = e.modifiers & Qt.ControlModifier
                        if (ctrl && k === Qt.Key_Down) win.pickSource(win.source + 1)
                        else if (ctrl && k === Qt.Key_Up) win.pickSource(win.source - 1)
                        else if (k === Qt.Key_Left || k === Qt.Key_H) win.moveDay(-1)
                        else if (k === Qt.Key_Right || k === Qt.Key_L) win.moveDay(1)
                        else if (k === Qt.Key_Up || k === Qt.Key_K) win.moveDay(-7)
                        else if (k === Qt.Key_Down || k === Qt.Key_J) win.moveDay(7)
                        else if (k === Qt.Key_PageUp || k === Qt.Key_BracketLeft) win.page(-1)
                        else if (k === Qt.Key_PageDown || k === Qt.Key_BracketRight) win.page(1)
                        else if (k === Qt.Key_T) win.pickDay(Dates.iso(new Date()))
                        else if (k === Qt.Key_M) win.view = "month"
                        else if (k === Qt.Key_W && !ctrl) win.view = "week"
                        else if (k === Qt.Key_Return || k === Qt.Key_Enter) win.openFirst()
                        else if (k === Qt.Key_Question) win.cheats = !win.cheats
                        else if (k >= Qt.Key_1 && k <= Qt.Key_9 && !ctrl) win.pickSource(k - Qt.Key_1)
                        else return
                        e.accepted = true
                    }
                    MonthView {
                        anchors.fill: parent
                        anchors.margins: 12; anchors.topMargin: 4
                        visible: win.view === "month"
                        app: win
                        c: win.look
                    }
                    WeekView {
                        anchors.fill: parent
                        anchors.margins: 12; anchors.topMargin: 4
                        visible: win.view === "week"
                        app: win
                        c: win.look
                    }
                    Text {
                        visible: win.loaded && win.calendars.length === 0
                        anchors.centerIn: parent
                        width: Math.min(parent.width - 80, 460)
                        horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
                        text: "No calendars yet. Calendar reads the iCloud account you set up in Contacts, and a Google calendar by its private address (calendar subscribe). Calendar's README has the steps."
                        color: c.dim; font.family: c.font; font.pixelSize: 12
                    }
                }
            }
        }

        EventPanel {
            id: eventPanel
            behind: content
            c: win.look
            onClosed: keys.forceActiveFocus()
        }

        property alias cheats: sheet.shown
        KeySheet {
            id: sheet
            c: win.look
            groups: [
                { title: "Calendar", keys: [["← →  h l", "Previous, next day"], ["↑ ↓  k j", "A week back, on"], ["PgUp PgDn  [ ]", "Previous, next month or week"],
                                           ["t", "Today"], ["m  w", "Month, week"], ["⏎", "Open the day's first event"], ["Double click", "A day's week"]] },
                { title: "Window", keys: [["Ctrl ↑ ↓", "Previous, next calendar"], ["1 – 9", "A calendar of the sidebar"], ["⌘R", "Sync now"], ["⌘B", "Hide or show the sidebar"]] }
            ]
        }
    }
}
