import QtQuick
import qs
import "Dates.js" as Dates

// A month as a grid of days, the date picker's popup (AppDatePicker): the month's name between its arrows, the weekdays
// in the region's order (Settings › Region: Monday first in Finland, Sunday in the US), and six weeks of days, so the
// grid keeps its height from month to month. The days of the months around it are fainter but can be clicked. It holds
// no keys and no focus: the field keeps them (typing goes on while it is open), and the picker moves `cursor`.
// Days travel as "YYYY-MM-DD", as everywhere in the kit (Dates.js). Part of the apps' kit (README.md).
Rectangle {
    id: root
    required property QtObject c
    property string cursor: ""          // the day the keys are on, "YYYY-MM-DD": its month is the one shown
    property string picked: ""          // the field's day, filled
    property string today: Regional.iso(new Date())
    signal clicked(string day)
    signal monthMoved(int n)            // the arrows: a month back (-1) or on (+1)

    property int cell: 32               // a day's height; the picker makes it lower in a low window
    readonly property int cellWidth: 32 // kept, so the month's name keeps its room
    readonly property int pad: 10
    readonly property int chrome: 2 * pad + 28 + 4 + 18    // all but the six weeks: the month's line, the weekdays'
    function heightFor(c) { return chrome + 6 * c }
    readonly property date first: {
        const d = Dates.toDate(cursor) || new Date()
        return new Date(d.getFullYear(), d.getMonth(), 1)
    }
    // The grid's first day: the week of the 1st, by the region's week start
    readonly property date start: Regional.startOfWeek(first)

    implicitWidth: 7 * cellWidth + 2 * pad
    implicitHeight: heightFor(cell)
    radius: 10
    color: c.solid
    border.color: c.line
    // A click between the days is the popup's, not the panel's under it (which would close it)
    MouseArea { anchors.fill: parent }

    // November 2026, with < > at its sides
    Item {
        id: head
        x: root.pad; y: root.pad
        width: root.width - 2 * root.pad; height: 28
        AppIconButton {
            anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
            c: root.c; glyph: "chevron-left"; tip: "Previous month"; keys: "PgUp"
            onClicked: root.monthMoved(-1)
        }
        Text {
            anchors.centerIn: parent
            width: parent.width - 64; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight
            text: Regional.format(root.first, "month")
            color: root.c.title; font.family: root.c.font; font.pixelSize: 13; font.weight: Font.Medium
        }
        AppIconButton {
            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
            c: root.c; glyph: "chevron-right"; tip: "Next month"; keys: "PgDn"; tipAlign: "right"
            onClicked: root.monthMoved(1)
        }
    }
    // Mo Tu We …, two letters as the cells are narrow
    Row {
        id: names
        x: root.pad; y: head.y + head.height + 4
        Repeater {
            model: Regional.weekdays
            Text {
                width: root.cellWidth; height: 18
                horizontalAlignment: Text.AlignHCenter
                text: Regional.dayName(modelData, true).slice(0, 2)
                color: root.c.dim; font.family: root.c.font; font.pixelSize: 11
            }
        }
    }
    Grid {
        x: root.pad; y: names.y + names.height
        columns: 7
        Repeater {
            model: 42
            Rectangle {
                id: day
                // By the calendar, not by adding hours: a day of a clock change isn't 24 hours long
                readonly property date date: new Date(root.start.getFullYear(), root.start.getMonth(), root.start.getDate() + index)
                readonly property string iso: Regional.iso(date)
                readonly property bool inMonth: date.getMonth() === root.first.getMonth()
                readonly property bool isPicked: iso === root.picked
                width: root.cellWidth; height: root.cell; radius: 6
                color: isPicked ? root.c.sel : hover.hovered ? root.c.hover : "transparent"
                // The keys' day: a frame, as a row the keys are on (the picked one may be elsewhere)
                border.color: iso === root.cursor ? root.c.primary : "transparent"
                HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: root.clicked(day.iso) }
                Text {
                    anchors.centerIn: parent
                    text: day.date.getDate()
                    font.family: root.c.font; font.pixelSize: 12
                    font.weight: day.iso === root.today ? Font.Bold : Font.Normal
                    color: day.iso === root.today ? root.c.primary
                         : day.isPicked ? root.c.title : day.inMonth ? root.c.text : root.c.faint
                }
            }
        }
    }
}
