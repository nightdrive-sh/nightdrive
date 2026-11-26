import QtQuick
import qs.kit
import "Dates.js" as Dates

// Events as a list under their days' headings (Today, Tomorrow, Thu 5 November): the agenda (a), and a search's results
// (/, SearchView). The keys' place is one event, current, on the kit's AppRow: ↑ ↓ j k move it, Home End go to the ends,
// ⏎ opens it, as a click does. groups comes from the view that uses it, [{ day, events }], so the agenda can put a
// multi-day event on each of its days and a search only on its first. It reads at any width: the end time, the place
// and the calendar's name come as the room does, and the title elides in what is left.
ListView {
    id: root
    required property var app           // the window: today, now, openEvent()
    required property QtObject c
    property var groups: []             // [{ day: "YYYY-MM-DD", events: [event] }]
    property bool active: true          // the keys are here: the current row is framed
    property string empty: ""           // what to say when there is nothing
    property int current: 0             // the event's number in the list, all days counted

    // The rows: each day's heading, then its events, numbered across the days
    readonly property var rows: {
        const out = []
        let n = 0
        for (const g of groups) {
            out.push({ day: g.day, first: out.length === 0 })
            for (const e of g.events) out.push({ day: g.day, event: e, n: n++ })
        }
        return out
    }
    readonly property int eventCount: rows.length - groups.length
    readonly property var currentEvent: { const r = rows.find(x => x.event && x.n === current); return r ? r.event : null }
    onEventCountChanged: current = Math.max(0, Math.min(current, eventCount - 1))

    function move(n) { if (eventCount) { current = Math.max(0, Math.min(eventCount - 1, current + n)); keepInView() } }
    function keepInView() {
        const i = rows.findIndex(x => x.event && x.n === current)
        // The day's heading too when its first event is the current one, else it would sit just out of sight
        if (i >= 0) positionViewAtIndex(i > 0 && !rows[i - 1].event ? i - 1 : i, ListView.Contain)
    }
    // The keys a list of events takes; true when it took this one
    function key(e) {
        const k = e.key
        if (k === Qt.Key_Down || k === Qt.Key_J) move(1)
        else if (k === Qt.Key_Up || k === Qt.Key_K) move(-1)
        else if (k === Qt.Key_Home) move(-eventCount)
        else if (k === Qt.Key_End) move(eventCount)
        else if ((k === Qt.Key_Return || k === Qt.Key_Enter) && currentEvent) app.openEvent(currentEvent)
        else return false
        return true
    }

    // The end time, the place and the calendar's name come as the room does (420 px: the start and the title alone)
    readonly property bool roomy: width >= 520
    readonly property bool wide: width >= 760
    FontMetrics { id: small; font.family: root.c.font; font.pixelSize: 11 }
    readonly property real timeWidth: Math.ceil(small.advanceWidth(roomy ? Regional.time("22:30") + " – " + Regional.time("23:30")
                                                                         : "until " + Regional.time("22:30"))) + 12

    // Now as the events write it, YYYY-MM-DDTHH:MM
    readonly property string nowText: Dates.iso(app.now) + "T" + Dates.pad(app.now.getHours()) + ":" + Dates.pad(app.now.getMinutes())

    clip: true
    boundsBehavior: Flickable.StopAtBounds
    model: rows
    TouchScroll { view: root }

    delegate: Item {
        id: item
        required property var modelData
        readonly property bool isDay: !modelData.event
        width: root.width
        height: isDay ? (modelData.first ? 30 : 46) : 30

        // A day: its heading, today's in the accent, the weekend's fainter, as DayList's
        Text {
            visible: item.isDay
            x: 10; anchors.bottom: parent.bottom; anchors.bottomMargin: 7
            width: parent.width - 20; elide: Text.ElideRight
            readonly property date date: Dates.parse(item.modelData.day)
            text: Dates.heading(item.modelData.day, root.app.today, Regional)
            color: item.modelData.day === root.app.today ? root.c.primary : date.getDay() % 6 === 0 ? root.c.faint : root.c.dim
            font.family: root.c.font; font.pixelSize: 12; font.weight: Font.Medium
        }

        AppRow {
            id: row
            visible: !item.isDay
            anchors.fill: parent
            c: root.c
            readonly property var e: item.modelData.event || ({})
            selected: !item.isDay && item.modelData.n === root.current
            active: root.active
            radius: 6
            // An event of today that is over already reads fainter
            readonly property bool over: !item.isDay && !e.all_day && e.end < root.nowText
            TapHandler {
                onTapped: { root.current = item.modelData.n; root.app.openEvent(row.e) }
            }
            // The calendar's colour: a bar for what takes the day, a dot for a time
            Rectangle {
                readonly property bool bar: !item.isDay && Dates.spansDays(row.e)
                x: 12; anchors.verticalCenter: parent.verticalCenter
                width: bar ? 10 : 6; height: bar ? 4 : 6; radius: bar ? 2 : 3
                color: row.e.color || "transparent"
            }
            Text {
                id: when
                x: 30; width: root.timeWidth; anchors.verticalCenter: parent.verticalCenter
                elide: Text.ElideRight
                text: item.isDay ? "" : Dates.when(row.e, item.modelData.day, Regional, root.roomy)
                color: root.c.dim; font.family: root.c.font; font.pixelSize: 11
            }
            Text {
                id: calName
                visible: root.wide
                anchors.right: parent.right; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, 160); elide: Text.ElideRight
                textFormat: Text.PlainText
                text: row.e.calendar_name || ""
                color: root.c.faint; font.family: root.c.font; font.pixelSize: 11
            }
            // The title, then its place fainter, in one line that elides
            Text {
                x: when.x + when.width
                width: (calName.visible ? calName.x - 12 : parent.width - 12) - x
                anchors.verticalCenter: parent.verticalCenter
                elide: Text.ElideRight
                textFormat: Text.StyledText
                readonly property string place: root.roomy && row.e.location ? row.e.location.split("\n")[0] : ""
                function esc(t) { return (t || "").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;") }
                text: esc(row.e.title) + (place ? "<font color=\"" + root.c.faint + "\">  ·  " + esc(place) + "</font>" : "")
                color: row.over ? root.c.dim : root.c.text
                font.family: root.c.font; font.pixelSize: 12
            }
        }
    }

    Text {
        visible: root.eventCount === 0 && root.empty !== ""
        anchors.centerIn: parent
        width: Math.min(parent.width - 40, 420)
        horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
        text: root.empty
        color: root.c.dim; font.family: root.c.font; font.pixelSize: 12
    }
}
