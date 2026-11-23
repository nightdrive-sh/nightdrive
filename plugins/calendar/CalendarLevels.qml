import QtQuick
import Quickshell
import qs
import qs.kit

// Calendar's part of the launcher (plugin-parts lists it while the plugin is on): the root search finds the events of
// the next DAYS days by title, place or calendar (rootRows), and Enter opens one in Calendar on its day; "New event"
// opens the window's editor on today. `calendar events --json` gives them, read on every open of the launcher, so a
// sync shows the next time. Settings › Launcher › Include calendar events turns the events off (New event stays: it is
// a command, not your data).
// Launcher.qml asks it like its own level files (levels, titles, parents, items, activate, footer, entered); it has no
// levels of its own, as an event's place is its window.
Item {
    id: m
    property var launcher: null               // Launcher.qml sets it once the file is loaded

    readonly property int days: 30            // how far ahead the search looks, as the agenda's 30 days
    readonly property string cmdPath: Qt.resolvedUrl("bin/calendar").toString().replace(/^file:\/\//, "")
    property var events: []                   // `calendar events` rows: { uid, calendar, calendar_name, title, start, end, all_day, location }

    readonly property var levels: []
    readonly property var titles: ({})
    readonly property var parents: ({})

    function opened() {
        const from = new Date(), to = new Date()
        to.setDate(to.getDate() + days)
        listProc.command = [cmdPath, "events", Regional.iso(from), Regional.iso(to), "--json", "--limit", "500"]
        listProc.running = true
    }
    function entered(level) {}
    function footer(level, query) { return "" }
    function items(level, q) { return [] }
    function shiftActivate(it) {}

    // When an event is, from today's side: "Today 9:30", "Tomorrow", "Fri 14.11. 18:00" (the region's way). One under
    // way since an earlier day is "Now".
    function when(e) {
        const today = Regional.iso(new Date())
        const tomorrow = new Date(); tomorrow.setDate(tomorrow.getDate() + 1)
        const day = e.start.slice(0, 10)
        const t = e.all_day ? "" : " " + Regional.time(e.start.slice(11))
        if (day < today) return "Now"
        if (day === today) return "Today" + t
        if (day === Regional.iso(tomorrow)) return "Tomorrow" + t
        const d = new Date(day + "T12:00")
        return Regional.dayName(d.getDay(), true) + " " + Regional.format(d, "day") + t
    }

    // Found by searching only, the title matched first, then the place and the calendar's name. A recurring event is
    // one row, its next time (the list comes by start), so a daily stand-up doesn't fill the search.
    function rootRows() {
        const rows = [{ item: { kind: "calnew", name: "New event", glyph: "calendar-plus", from: "Calendar",
                                footer: "Enter: a new event in Calendar, today" },
                        text: "New event", extra: "calendar add appointment meeting" }]
        if (launcher.prefs.calendar === false) return rows
        const seen = {}
        const next = events.filter(e => seen[e.calendar + "/" + e.uid] ? false : (seen[e.calendar + "/" + e.uid] = true))
        return rows.concat(next.map(e => ({
            item: { kind: "calevent", name: e.title || "(No title)", glyph: "calendar", from: "Calendar",
                    sub: [when(e), e.location].filter(x => x).join("  ·  "), calendar: e.calendar, uid: e.uid, day: e.start.slice(0, 10),
                    footer: "Enter: open in Calendar" },
            text: e.title || "",
            extra: [e.location, e.calendar_name].join(" ")
        })))
    }

    function activate(it) {
        if (it.kind === "calevent") {
            launcher.open = false
            // DAY picks this time of a recurring event, and the day before it for one under way
            Quickshell.execDetached([cmdPath, "open-event", it.calendar, it.uid, it.day])
            return true
        }
        if (it.kind === "calnew") { launcher.open = false; Quickshell.execDetached([cmdPath, "new"]); return true }
        return false
    }

    Sh {
        id: listProc
        onResult: text => {
            try { m.events = JSON.parse(text).events || [] }
            catch (e) { m.events = [] }
        }
    }
}
