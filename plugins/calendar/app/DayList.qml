import QtQuick
import qs.kit
import "Dates.js" as Dates

// The days as a list, in a window too narrow for the month's or the week's grid (#2025; Jari 2.11.: "a small window
// could show the days as a list"): the week's seven days, or the month's, each with its events under it: all-day ones
// first, then by time, the time and title in full words. Cells of a few pixels showed "16…" or only marks; a list
// reads at any width. A click on a day picks it, on an event opens it; the picked day (← → and the rest) stays in view.
ListView {
    id: root
    required property var app           // the window: day, view, today, weekDays, byDay, dayPicked, dayHover, pickDay(), openEvent(), newEvent()
    required property QtObject c
    readonly property date at: Dates.parse(app.day)
    readonly property var days: {
        if (app.view === "week") return app.weekDays
        const out = []
        for (let d = new Date(at.getFullYear(), at.getMonth(), 1); d.getMonth() === at.getMonth(); d = Dates.addDays(d, 1))
            out.push(Dates.iso(d))
        return out
    }
    readonly property int line: 22

    // A day's events, all-day and multi-day ones first, then by their start
    function eventsOf(day) {
        return (app.byDay[day] || []).slice().sort((a, b) => (Dates.spansDays(b) - Dates.spansDays(a)) || (a.start < b.start ? -1 : a.start > b.start ? 1 : 0))
    }
    function keepInView() { const i = days.indexOf(app.day); if (i >= 0) positionViewAtIndex(i, ListView.Contain) }
    Connections { target: root.app; function onDayChanged() { Qt.callLater(root.keepInView) } }
    onVisibleChanged: if (visible) Qt.callLater(keepInView)
    onDaysChanged: Qt.callLater(keepInView)

    clip: true
    boundsBehavior: Flickable.StopAtBounds
    model: days
    TouchScroll { view: root }

    delegate: Column {
        id: dayItem
        required property string modelData
        readonly property date date: Dates.parse(modelData)
        readonly property var items: root.eventsOf(modelData)
        readonly property bool picked: modelData === root.app.day
        readonly property bool isToday: modelData === root.app.today
        width: root.width
        bottomPadding: 18      // the days apart, so each reads as its own group (Jari 2.11.)

        // The day: its name and number, the picked one on the selection's colour, today's number in the accent
        Rectangle {
            width: parent.width; height: 30; radius: 6
            color: dayItem.picked ? root.app.dayPicked : dayHover.hovered && !root.c.pointerAway ? root.app.dayHover : "transparent"   // as MonthView's
            HoverHandler { id: dayHover }
            TapHandler { onTapped: root.app.pickDay(dayItem.modelData); onDoubleTapped: root.app.newEvent(dayItem.modelData) }
            Row {
                x: 8; anchors.verticalCenter: parent.verticalCenter
                spacing: 8
                Rectangle {
                    width: 26; height: 22; radius: 11
                    anchors.verticalCenter: parent.verticalCenter
                    color: dayItem.isToday ? root.c.primary : "transparent"
                    Text {
                        anchors.centerIn: parent
                        text: dayItem.date.getDate()
                        color: dayItem.isToday ? root.c.solid : root.c.title
                        font.family: root.c.font; font.pixelSize: 13; font.weight: dayItem.isToday ? Font.Bold : Font.Normal
                    }
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Regional.dayName(dayItem.date.getDay(), true) + (dayItem.items.length ? "" : "  ·  nothing")
                    color: dayItem.date.getDay() % 6 === 0 ? root.c.faint : root.c.dim
                    font.family: root.c.font; font.pixelSize: 12
                }
            }
        }
        Repeater {
            model: dayItem.items
            delegate: Rectangle {
                id: row
                required property var modelData
                readonly property bool allDay: Dates.spansDays(modelData)
                x: 8; width: dayItem.width - 8; height: root.line
                radius: 4
                color: rowHover.hovered ? root.app.dayHover : "transparent"
                HoverHandler { id: rowHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: root.app.openEvent(row.modelData) }
                // The calendar's colour: a bar for what takes the day, a dot for a time
                Rectangle {
                    x: 6; anchors.verticalCenter: parent.verticalCenter
                    width: row.allDay ? 10 : 6; height: row.allDay ? 4 : 6; radius: row.allDay ? 2 : 3
                    color: row.modelData.color
                }
                Text {
                    id: when
                    x: 24; width: 62; anchors.verticalCenter: parent.verticalCenter
                    text: row.allDay ? "all day" : Regional.time(Dates.time(row.modelData))
                    color: root.c.dim; font.family: root.c.font; font.pixelSize: 11
                }
                Text {
                    textFormat: Text.PlainText
                    x: when.x + when.width; width: parent.width - x - 6
                    anchors.verticalCenter: parent.verticalCenter
                    elide: Text.ElideRight
                    text: row.modelData.title
                    color: root.c.text; font.family: root.c.font; font.pixelSize: 12
                }
            }
        }
    }
}
