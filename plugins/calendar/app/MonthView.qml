import QtQuick
import QtQuick.Layouts
import "Dates.js" as Dates

// The month: six weeks from the Monday on or before the 1st, with week numbers, and as many of each day's events as
// fit in its cell (all-day ones first, as a coloured bar; then the times). A click on a day picks it, a double click
// opens its week; a click on an event opens it (EventPanel). A narrower window (#2025) keeps them readable: below a
// width the time goes and the title stays, and "+4 more" becomes "+4"; narrower still, DayList takes the month's place.
Item {
    id: root
    required property var app           // the window: day, today, now, byDay, dayPicked, dayHover, pickDay(), openEvent(), newEvent()
    required property QtObject c
    readonly property date first: Dates.parse(app.day)
    readonly property var days: Dates.monthDays(first.getFullYear(), first.getMonth())
    readonly property string today: app.today
    readonly property int weekCol: 34
    readonly property int headRow: 26
    readonly property real cellW: (width - weekCol) / 7
    readonly property real cellH: (height - headRow) / 6
    readonly property int line: 18          // an event's row in a cell
    readonly property int gap: 2            // between stacked rows: a bar's colour mustn't run into the next (#1481)
    readonly property var dayNames: ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    FontMetrics { id: small; font.family: root.c.font; font.pixelSize: 11 }
    // A chip's words: the time too only while "16:30 Ainon" fits, else the title alone ("16…" said nothing)
    readonly property bool withTime: cellW - 8 - 18 >= small.advanceWidth("00:00 Abcd")

    // The weekdays' names over the columns
    Repeater {
        model: 7
        delegate: Text {
            required property int index
            x: root.weekCol + index * root.cellW + 8
            width: root.cellW - 16
            height: root.headRow
            verticalAlignment: Text.AlignVCenter
            text: root.dayNames[index]
            color: index >= 5 ? root.c.faint : root.c.dim
            font.family: root.c.font; font.pixelSize: 11; font.weight: Font.Medium
        }
    }

    Repeater {
        model: 6
        delegate: Text {
            required property int index
            x: 0; y: root.headRow + index * root.cellH + 8
            width: root.weekCol - 6
            horizontalAlignment: Text.AlignRight
            text: Dates.week(root.days[index * 7])
            color: root.c.faint; font.family: root.c.font; font.pixelSize: 10
        }
    }

    Repeater {
        model: root.days
        delegate: Rectangle {
            id: cell
            required property var modelData
            required property int index
            readonly property string day: Dates.iso(modelData)
            readonly property bool inMonth: modelData.getMonth() === root.first.getMonth()
            readonly property var items: root.app.byDay[day] || []
            // Rows that fit under the day's number; the last one says how many more when they don't all
            readonly property int room: Math.max(0, Math.floor((height - 30) / root.line))
            readonly property int shown: items.length > room ? Math.max(0, room - 1) : items.length
            x: root.weekCol + (index % 7) * root.cellW
            y: root.headRow + Math.floor(index / 7) * root.cellH
            width: root.cellW; height: root.cellH
            color: day === root.app.day ? root.app.dayPicked : hover.hovered ? root.app.dayHover : "transparent"
            Rectangle { anchors.top: parent.top; width: parent.width; height: 1; color: root.c.line }
            // Every day its left line, Monday's apart from the week numbers, and Sunday its right: the grid is closed at
            // both sides, as the week's hours are (Jari 2.11.)
            Rectangle { anchors.left: parent.left; height: parent.height; width: 1; color: root.c.line }
            Rectangle { anchors.right: parent.right; height: parent.height; width: 1; color: root.c.line; visible: cell.index % 7 === 6 }

            HoverHandler { id: hover }
            // A double click on the day: a new event on it (Jari 2.11.; it opened the week). Not on an event: the
            // chip's own TapHandler opens it, and in Qt 6 this one gets the same taps (both grab passively)
            TapHandler {
                onTapped: root.app.pickDay(cell.day)
                onDoubleTapped: point => {
                    const hit = chips.childAt(point.position.x - chips.x, point.position.y - chips.y)
                    if (!(hit && hit.isEvent)) root.app.newEvent(cell.day)
                }
            }

            // The day's number; today's in a circle of the accent
            Rectangle {
                x: 6; y: 5
                width: 22; height: 20; radius: 10
                color: cell.day === root.today ? root.c.primary : "transparent"
                Text {
                    anchors.centerIn: parent
                    text: cell.modelData.getDate()
                    color: cell.day === root.today ? root.c.solid : cell.inMonth ? root.c.title : root.c.faint
                    font.family: root.c.font; font.pixelSize: 12
                    font.weight: cell.day === root.today ? Font.Bold : Font.Normal
                }
            }

            Column {
                id: chips
                x: 4; y: 28
                width: parent.width - 8
                spacing: root.gap
                Repeater {
                    model: cell.items.slice(0, cell.shown)
                    delegate: Rectangle {
                        id: chip
                        required property var modelData
                        readonly property bool bar: Dates.spansDays(modelData)
                        readonly property bool isEvent: true     // for the cell's double click, above
                        width: parent.width; height: root.line - root.gap      // with the gap, a row is still root.line
                        radius: 4
                        color: bar ? Qt.rgba(ev.r, ev.g, ev.b, 0.35) : chipHover.hovered ? root.app.dayHover : "transparent"
                        readonly property color ev: modelData.color
                        HoverHandler { id: chipHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: root.app.openEvent(chip.modelData) }
                        Rectangle {
                            visible: !chip.bar
                            x: 4; anchors.verticalCenter: parent.verticalCenter
                            width: 6; height: 6; radius: 3; color: chip.ev
                        }
                        Text {
                            textFormat: Text.PlainText
                            x: chip.bar ? 6 : 14
                            width: parent.width - x - 4
                            anchors.verticalCenter: parent.verticalCenter
                            elide: Text.ElideRight
                            text: (chip.bar || !root.withTime ? "" : Dates.time(chip.modelData) + " ") + chip.modelData.title
                            color: root.c.text; font.family: root.c.font; font.pixelSize: 11
                        }
                    }
                }
                // "+4 more", or "+4" where that doesn't fit: it ran into the next day's cell (#2025)
                Text {
                    readonly property string count: "+" + (cell.items.length - cell.shown)
                    visible: cell.items.length > cell.shown
                    x: 6; width: parent.width - 6
                    height: root.line
                    clip: true
                    verticalAlignment: Text.AlignVCenter
                    text: small.advanceWidth(count + " more") <= width ? count + " more" : count
                    color: root.c.faint; font.family: root.c.font; font.pixelSize: 10
                }
            }
        }
    }
}
