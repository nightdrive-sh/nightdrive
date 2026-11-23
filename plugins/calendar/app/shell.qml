import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs
import qs.kit
import "Dates.js" as Dates

// Nightdrive Calendar: the calendars in the sidebar, the month, the week, the day or the agenda on the right, over the
// events the sync keeps in ~/.local/share/calendar (`calendar events` reads them by khal). An event opens in EventPanel;
// a new one is added, and one opened is changed, in EventEditor (`calendar add`, `calendar edit`), or deleted after
// EventDelete asks (`calendar delete`). / searches them (SearchView). ⌘, opens Settings (SettingsPanel: the reminders,
// which lib/remind.py notifies; a reminder's Open comes back here as showEvent).
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
        // The picked day and the one under the pointer are whole cells here, not rows: the kit's sel and hover would
        // fill a large part of the month, so the views take them fainter (Jari 2.11.)
        readonly property color dayPicked: Qt.rgba(c.sel.r, c.sel.g, c.sel.b, 0.55)
        readonly property color dayHover: Qt.rgba(c.sel.r, c.sel.g, c.sel.b, 0.25)

        // `calendar sync`, add and delete ask for a reload once they are done
        IpcHandler {
            target: "calendar"
            function refresh(): void { win.reload() }
            function today(): void { win.pickDay(Dates.iso(new Date())) }
            // A day, YYYY-MM-DD (`calendar show DAY`)
            function showDay(day: string): void { if (/^\d{4}-\d{2}-\d{2}$/.test(day)) win.pickDay(day) }
            // "month", "week", "day" or "agenda" (`calendar month`, `week`, `day`, `agenda`)
            function setView(view: string): void { if (["month", "week", "day", "agenda"].indexOf(view) >= 0) { win.searching = false; win.view = view } }
            // The search, with these words (`calendar search [TEXT]`)
            function search(text: string): void { win.openSearch(text) }
            // The new event panel on a day, YYYY-MM-DD, or the picked one (`calendar new [DAY]`)
            function newEvent(day: string): void { win.newEvent(/^\d{4}-\d{2}-\d{2}$/.test(day) ? day : win.day) }
            // Settings (the kit's `calendar settings`)
            function openSettings(): void { settingsPanel.open() }
            // An event open on its day (a reminder's Open: `calendar open-event CALENDAR UID [DAY]`), once the day's
            // events are read; DAY tells a recurring event's time apart
            function showEvent(calendar: string, uid: string, day: string): void { win.showEvent(calendar, uid, day) }
        }

        readonly property int headerHeight: 22  // the sidebar's title line and the view's header, as Contacts'
        readonly property string command: Quickshell.shellDir + "/../bin/calendar"

        property var calendars: []          // [{ id, name, color, source, read_only, events }]
        property bool loaded: false
        // The sidebar's rows: every calendar together, then each one
        readonly property var sources: [{ id: "", name: "All calendars", color: "", events: -1 }].concat(calendars)
        property int source: 0
        property string view: "month"       // or "week", "day", "agenda"
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

        // The week of the picked day, for the week view and its list
        readonly property var weekDays: {
            const first = Dates.weekFirst(Dates.parse(day), Regional.weekStart)
            return [0, 1, 2, 3, 4, 5, 6].map(i => Dates.iso(Dates.addDays(first, i)))
        }
        // The agenda: the days from the picked one on, a page of them at a time
        readonly property int agendaDays: 30
        // Its days that have events, each day's all-day and multi-day ones first, as DayList's
        readonly property var agendaGroups: {
            const out = []
            for (let i = 0, d = Dates.parse(day); i < agendaDays; i++, d = Dates.addDays(d, 1)) {
                const list = byDay[Dates.iso(d)]
                if (list && list.length)
                    out.push({ day: Dates.iso(d), events: list.slice().sort((a, b) => (Dates.spansDays(b) - Dates.spansDays(a)) || (a.start < b.start ? -1 : a.start > b.start ? 1 : 0)) })
            }
            return out
        }
        // What the view shows: the month's six weeks, the week, the day, or the agenda's days
        function viewRange() {
            const d = Dates.parse(day)
            if (view === "day") return [day, Dates.iso(Dates.addDays(d, 1))]
            if (view === "agenda") return [day, Dates.iso(Dates.addDays(d, agendaDays))]
            const from = view === "month" ? Dates.monthDays(d.getFullYear(), d.getMonth(), Regional.weekStart)[0] : Dates.weekFirst(d, Regional.weekStart)
            return [Dates.iso(from), Dates.iso(Dates.addDays(from, view === "month" ? 42 : 7))]
        }
        function load(force) {
            const r = viewRange()
            if (!force && r.join(" ") === range) return
            range = r.join(" ")
            reader.command = [command, "events", "--json", "--limit", "100000", r[0], r[1]]
            reader.running = true
        }
        function reload() { calReader.running = true; load(true); if (settingsPanel.visible) settingsPanel.load() }
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
                    if (d.from + " " + d.to === win.range) { win.events = d.events; win.openPending() }
                }
            }
            stderr: StdioCollector { onStreamFinished: if (text.trim()) win.say(text.trim().split("\n").pop(), false, true) }
        }
        Component.onCompleted: { calReader.running = true; load(true); keys.forceActiveFocus() }

        function pickDay(d) { day = d }
        // The month, week, day or the agenda's days before (-1) or after (1)
        function page(n) {
            const d = Dates.parse(day)
            day = view === "month" ? Dates.iso(new Date(d.getFullYear(), d.getMonth() + n, 1))
                : Dates.iso(Dates.addDays(d, (view === "week" ? 7 : view === "agenda" ? agendaDays : 1) * n))
        }
        function setView(v) { searching = false; view = v }
        function moveDay(n) { day = Dates.iso(Dates.addDays(Dates.parse(day), n)) }
        function pickSource(i) { if (i >= 0 && i < sources.length) source = i }
        function openEvent(e) { eventPanel.show(e) }
        // The new event panel on day, at hour:minute when a time was clicked. Only a calendar that isn't read-only takes
        // one: with none, say why rather than open a panel that can't save
        function newEvent(d, hour, minute) {
            if (!calendars.some(x => !x.read_only)) {
                say("No calendar here takes new events: the ICS ones are read only, and so is an account with read-only = yes.", false, true)
                return
            }
            if (d !== day) day = d
            editor.open(d, hour, minute)
        }
        // The colour picker for a calendar, or the one picked in the sidebar (c): All calendars has none of its own
        function pickColor(cal) {
            const it = cal || sources[source]
            if (!it || !it.id) { say("Pick a calendar first (1–9 or Ctrl ↓), then c gives it a colour.", false, false); return }
            colorPicker.open(it)
        }
        // Saved by the picker: said with an Undo, which gives back the colour it had
        function colorSaved(r) {
            say(r.name + (!r.custom ? " has its own colour back" : r.color_name ? " is " + r.color_name + " now" : " is " + r.color + " now"),
                false, false, "Undo", () => colorUndo.run(r.id, r.previous))
        }
        // showEvent's event, opened once the read of its day brings it (or said to be gone, as the phone may have moved it)
        property var pending: null
        function showEvent(cal, uid, d) {
            const target = /^\d{4}-\d{2}-\d{2}$/.test(d) ? d : day
            pending = { calendar: cal, uid: uid, day: target }
            searching = false
            if (settingsPanel.visible) settingsPanel.close()   // it would cover the event
            if (target !== day) day = target    // a new range is read (load), and openPending follows the read
            if (!reader.running) openPending()  // the range was read already
        }
        function openPending() {
            if (!pending) return
            const p = pending
            pending = null
            const e = events.find(x => x.calendar === p.calendar && x.uid === p.uid && Dates.onDay(x, p.day))
            if (e) openEvent(e)
            else say("That event isn't on " + Regional.format(Dates.parse(p.day), "medium") + " any more.", false, true)
        }
        // ⏎ on a day: its first event
        function openFirst() { const list = byDay[day] || []; if (list.length) openEvent(list[0]) }

        // The search (/) in place of the view, its words given or as they were; Esc there comes back
        property bool searching: false
        function openSearch(text) {
            searching = true
            if (text) { searchView.text = text; searchView.search() }
            Qt.callLater(searchView.open)
        }
        function closeSearch() { searching = false; keys.forceActiveFocus() }
        // The keys back where they were once a panel closes: the search's results, or the view
        function refocus() { if (searching) searchView.focusList(); else keys.forceActiveFocus() }

        // A sync from the window (⌘R): the command's, which asks for a reload when it's done
        Process { id: syncer; command: [win.command, "sync"]; onExited: code => win.say(code === 0 ? "Synced" : "The sync didn't finish: calendar sync in a terminal says why", false, code !== 0) }
        function sync() { if (!syncer.running) { say("Syncing…", true); syncer.running = true } }

        // What just happened, at the top of the window (the kit's toast): seen where a line at the sidebar's foot wasn't
        function say(t, sticky, danger, action, run) { toast.show(t, { sticky: !!sticky, danger: !!danger, action: action, run: run }) }
        Process {
            id: colorUndo
            function run(id, value) { command = [win.command, "color", id, value]; running = true }
            onExited: code => { if (code === 0) win.reload() }
        }

        // The week's line for now, and today's circle, move along with the clock
        property date now: new Date()
        readonly property string today: Dates.iso(now)
        Timer { interval: 60000; running: true; repeat: true; onTriggered: win.now = new Date() }

        Shortcut { sequence: "Ctrl+R"; onActivated: win.sync() }
        Shortcut { sequence: "Ctrl+Q"; onActivated: Qt.quit() }
        Shortcut { sequence: "Ctrl+Z"; onActivated: toast.act() }   // the toast's Undo (a colour)
        Shortcut { sequences: ["Ctrl+B", "Meta+B"]; onActivated: win.sidebarChoice = !win.sidebarShown }
        Shortcut { sequences: ["Ctrl+,", "Meta+,"]; onActivated: settingsPanel.visible ? settingsPanel.close() : settingsPanel.open() }

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
                        // Its colour (#2031): a right click, or the palette under the pointer, as Mail's gear shows
                        TapHandler {
                            enabled: nav.modelData.id !== ""
                            acceptedButtons: Qt.RightButton
                            onTapped: win.pickColor(nav.modelData)
                        }
                        AppIconButton {
                            visible: nav.modelData.id !== "" && (nav.hovered || hovered)
                            anchors.right: parent.right; anchors.rightMargin: 4; anchors.verticalCenter: parent.verticalCenter
                            c: win.look
                            glyph: "palette"; hoverColor: c.sel
                            tip: "Colour"; keys: "c"; tipAlign: "right"
                            onClicked: win.pickColor(nav.modelData)
                        }
                    }
                }
                Item { Layout.fillHeight: true }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 0
                Header {
                    Layout.fillWidth: true
                    // As far from both edges, Today as New; over the list of days (a narrow window), with the list's edges
                    Layout.leftMargin: keys.narrow ? 12 : 16; Layout.rightMargin: keys.narrow ? 12 : 16; Layout.topMargin: 16
                    // As high as the buttons (AppButton's 28): the name stays level with the sidebar's title
                    Layout.preferredHeight: Math.max(win.headerHeight, 28)
                    // Over the divider and the view that come after it, which would otherwise draw over its buttons' tips
                    z: 1
                    app: win
                    c: win.look
                }
                Rectangle { Layout.fillWidth: true; Layout.topMargin: 17; Layout.preferredHeight: 1; color: c.divider }

                SearchView {
                    id: searchView
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: win.searching
                    app: win
                    c: win.look
                    onClosed: win.closeSearch()
                }
                FocusScope {
                    id: keys
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: !win.searching
                    focus: true
                    Keys.onPressed: e => {
                        const k = e.key
                        win.look.moved(e)
                        if (win.cheats && k !== Qt.Key_Question && sheet.modifierKeys.indexOf(k) < 0) win.cheats = false
                        const ctrl = e.modifiers & Qt.ControlModifier
                        // The agenda's list takes the arrows and ⏎; PgUp PgDn [ ] page its days as the other views'
                        if (win.view === "agenda" && !ctrl && agenda.key(e)) { e.accepted = true; return }
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
                        else if (k === Qt.Key_D && !ctrl) win.view = "day"
                        else if (k === Qt.Key_A && !ctrl) win.view = "agenda"
                        else if (k === Qt.Key_Slash || e.text === "/") win.openSearch("")
                        else if (k === Qt.Key_N && !ctrl) win.newEvent(win.day)
                        else if (k === Qt.Key_C && !ctrl) win.pickColor(null)
                        else if (k === Qt.Key_Return || k === Qt.Key_Enter) win.openFirst()
                        else if (k === Qt.Key_Question) win.cheats = !win.cheats
                        else if (k >= Qt.Key_1 && k <= Qt.Key_9 && !ctrl) win.pickSource(k - Qt.Key_1)
                        else return
                        e.accepted = true
                    }
                    // Narrower than this the grids' cells can't hold a word (#2025): the days as a list instead. Not the
                    // day view's: its one column has the room at any width
                    readonly property bool narrow: width < 500
                    readonly property bool listed: narrow && win.view !== "day" && win.view !== "agenda"
                    DayList {
                        anchors.fill: parent
                        anchors.margins: 12; anchors.topMargin: 8
                        visible: keys.listed
                        app: win
                        c: win.look
                    }
                    MonthView {
                        anchors.fill: parent
                        // The grids reach the edges: the week numbers and the hours give the left its room (Jari 2.11.)
                        anchors.topMargin: 4
                        visible: win.view === "month" && !keys.listed
                        app: win
                        c: win.look
                    }
                    HoursView {
                        anchors.fill: parent
                        anchors.topMargin: 4
                        visible: win.view === "week" && !keys.listed
                        days: win.weekDays
                        app: win
                        c: win.look
                    }
                    HoursView {
                        anchors.fill: parent
                        anchors.topMargin: 4
                        visible: win.view === "day"
                        days: [win.day]
                        app: win
                        c: win.look
                    }
                    AgendaList {
                        id: agenda
                        anchors.fill: parent
                        anchors.margins: 12; anchors.topMargin: 8
                        visible: win.view === "agenda"
                        app: win
                        c: win.look
                        groups: win.agendaGroups
                        active: keys.activeFocus
                        empty: win.calendars.length ? "Nothing in the " + win.agendaDays + " days from " + Regional.format(Dates.parse(win.day), "medium") + "." : ""
                        // A new page of days starts at its first event
                        Connections { target: win; function onDayChanged() { agenda.current = 0; agenda.positionViewAtBeginning() } }
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

        ColorPicker {
            id: colorPicker
            behind: content
            c: win.look
            app: win
            onClosed: win.refocus()
        }
        EventPanel {
            id: eventPanel
            behind: content
            c: win.look
            app: win
            onClosed: win.refocus()
            onEditRequested: (ev, scope) => editor.edit(ev, scope)
            onDeleteRequested: (ev, scope) => deleter.ask(ev, scope)
        }
        EventDelete {
            id: deleter
            behind: content
            c: win.look
            app: win
            onClosed: win.refocus()
            // As the editor's: this window may not be the one `calendar delete` asks to reload
            onDeleted: r => {
                win.reload()
                win.say("Deleted: " + r.title + (r.synced ? "" : ". The next sync takes it from the server."))
            }
        }
        SettingsPanel {
            id: settingsPanel
            behind: content
            c: win.look
            app: win
            onClosed: win.refocus()
        }
        EventEditor {
            id: editor
            behind: content
            c: win.look
            app: win
            onClosed: win.refocus()
            // The window shows it at once: `calendar add` asks a running Calendar to reload, but this one may have been
            // started apart from the command (qs -p), so reload here too
            onSaved: (ev, edited) => {
                win.reload()
                win.say((edited ? "Saved in " : "Added to ") + ev.calendar_name + ": " + ev.title
                        + (ev.synced ? "" : ". The next sync takes it to the server."))
            }
        }

        property alias cheats: sheet.shown
        KeySheet {
            id: sheet
            c: win.look
            groups: [
                { title: "Calendar", keys: [["← →  h l", "Previous, next day"], ["↑ ↓  k j", "A week back, on"], ["PgUp PgDn  [ ]", "Previous, next month, week, day, agenda's days"],
                                           ["t", "Today"], ["m  w  d  a", "Month, week, day, agenda"], ["⏎", "Open the day's first event"], ["n", "New event"], ["/", "Search"]] },
                { title: "Agenda, search", keys: [["↑ ↓  j k", "Previous, next event"], ["⏎", "Open it"], ["/", "To the search's words"], ["Esc", "Leave the search"]] },
                { title: "Window", keys: [["Ctrl ↑ ↓", "Previous, next calendar"], ["1 – 9", "A calendar of the sidebar"], ["c", "The calendar's colour"], ["⌘R", "Sync now"], ["⌘B", "Hide or show the sidebar"], ["⌘,", "Settings: reminders"]] },
                { title: "An event", keys: [["e", "Edit it"], ["Del  ⌫", "Delete it (asks first)"], ["← →", "A recurring one: this time, every time"], ["Esc  ⏎", "Close it"]] },
                { title: "New or edited event", keys: [["⏎  Ctrl ⏎", "Save it"], ["Tab", "The next field"], ["← →", "Another calendar"], ["Space", "All day, on or off"], ["↓", "A day's month to pick from"], ["Esc", "Leave it"]] }
            ]
        }
        // Last, so it shows over the panels too
        AppToast { id: toast; c: win.look }
    }
}
