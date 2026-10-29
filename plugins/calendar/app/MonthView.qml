import QtQuick
import QtQuick.Layouts
import "Dates.js" as Dates

// The month: six weeks from the Monday on or before the 1st, with week numbers, and as many of each day's events as
// fit in its cell (all-day ones first, as a coloured bar; then the times). A click on a day picks it, a double click
// opens its week; a click on an event opens it (EventPanel).
Item {
    id: root
    required property var app           // the window: day, today, now, byDay, pickDay(), openEvent(), showWeek()
    required property QtObject c
    readonly property date first: Dates.parse(app.day)
    readonly property var days: Dates.monthDays(first.getFullYear(), first.getMonth())
    readonly property string today: app.today
    readonly property int weekCol: 34
    readonly property int headRow: 26
    readonly property real cellW: (width - weekCol) / 7
    readonly property real cellH: (height - headRow) / 6
    readonly property int line: 18          // an event's row in a cell
    readonly property var dayNames: ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

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
            color: day === root.app.day ? root.c.sel : hover.hovered ? root.c.hover : "transparent"
            Rectangle { anchors.top: parent.top; width: parent.width; height: 1; color: root.c.line }
            Rectangle { anchors.left: parent.left; height: parent.height; width: 1; color: root.c.line; visible: cell.index % 7 > 0 }

            HoverHandler { id: hover }
            TapHandler { onTapped: root.app.pickDay(cell.day); onDoubleTapped: root.app.showWeek(cell.day) }

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
                x: 4; y: 28
                width: parent.width - 8
                spacing: 0
                Repeater {
                    model: cell.items.slice(0, cell.shown)
                    delegate: Rectangle {
                        id: chip
                        required property var modelData
                        readonly property bool bar: Dates.spansDays(modelData)
                        width: parent.width; height: root.line - 2
                        radius: 4
                        color: bar ? Qt.rgba(ev.r, ev.g, ev.b, 0.35) : chipHover.hovered ? root.c.hover : "transparent"
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
                            text: (chip.bar ? "" : Dates.time(chip.modelData) + " ") + chip.modelData.title
                            color: root.c.text; font.family: root.c.font; font.pixelSize: 11
                        }
                    }
                }
                Text {
                    visible: cell.items.length > cell.shown
                    x: 6
                    height: root.line
                    verticalAlignment: Text.AlignVCenter
                    text: "+" + (cell.items.length - cell.shown) + " more"
                    color: root.c.faint; font.family: root.c.font; font.pixelSize: 10
                }
            }
        }
    }
}
