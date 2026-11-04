import QtQuick
import Quickshell
import qs
import qs.kit

// Today's events under the clock menu's month (CalendarMenu.qml loads every installed plugin's <Name>Today.qml there,
// so Tasks' today can join the same menu later rather than a menu of its own). Read once as the menu opens, with
// `calendar events`; a click opens the event in Calendar and closes the menu. Nothing shows on a day without events,
// nor when the command fails: the menu is then just the month, as without Calendar.
Column {
    id: t
    width: parent ? parent.width : 300
    spacing: 2
    signal close()

    readonly property string calendar: Quickshell.env("HOME") + "/.local/bin/calendar"
    readonly property string day: Regional.iso(new Date())
    property var events: []
    readonly property bool shown: events.length > 0      // CalendarMenu hides the part without it

    // An event's time as the row's detail, from today's side: one that began earlier or goes on after today says so
    function when(e) {
        const from = e.start.slice(0, 10), to = e.end.slice(0, 10)
        // An end at midnight is the end of the day before, as khal writes a timed event that runs to 24:00
        const endsToday = to === day || (to > day && e.end.slice(11) === "00:00" && to === nextDay())
        if (e.all_day || (from < day && !endsToday)) return "All day"
        if (from < day) return "until " + Regional.time(e.end.slice(11))
        if (!endsToday) return "from " + Regional.time(e.start.slice(11))
        return Regional.time(e.start.slice(11)) + " – " + Regional.time(e.end.slice(11))
    }
    function nextDay() {
        const d = new Date(); d.setDate(d.getDate() + 1)
        return Regional.iso(d)
    }
    // All-day ones (and those under way since an earlier day) first, then by the time they start
    function order(list) {
        const key = e => (e.all_day || e.start.slice(0, 10) < day ? "0" : "1") + e.start
        return list.slice().sort((a, b) => key(a) < key(b) ? -1 : key(a) > key(b) ? 1 : 0)
    }

    MenuSection { width: parent.width; title: "Today"; apart: true }

    Repeater {
        model: t.events
        delegate: MenuRow {
            required property var modelData
            width: t.width
            icon: "circle"
            iconColor: modelData.color || Theme.dim
            label: modelData.title || "(No title)"
            detail: t.when(modelData)
            onClicked: {
                // DAY picks today's time of a recurring event
                Quickshell.execDetached([t.calendar, "open-event", modelData.calendar, modelData.uid, t.day])
                t.close()
            }
        }
    }

    Sh {
        id: read
        command: [t.calendar, "events", t.day, t.nextDay(), "--json"]
        onResult: text => {
            try { t.events = t.order(JSON.parse(text).events || []) } catch (e) { t.events = [] }
        }
    }
    Component.onCompleted: read.running = true
}
