import QtQuick
import qs.kit
import "Dates.js" as Dates

// Days side by side over their hours: the week view's seven (Monday to Sunday, Sunday to Saturday in the US: Settings ›
// Region) and the day view's one (#2004), the same grid so neither copies the other. A row on top for what takes whole
// days (all-day and multi-day events, as bars on each of their days), and under it the hours, scrolled to the morning,
// with each timed event a block from its start to its end. Events that overlap share their day's width, side by side.
Item {
    id: root
    required property var app           // the window: day, today, now, byDay, dayPicked, pickDay(), openEvent(), newEvent()
    required property QtObject c
    required property var days          // ["YYYY-MM-DD"], in order
    // One day alone has the width for its name in full ("Tuesday") and for a block's time and place beside its title
    readonly property bool single: days.length === 1
    readonly property string today: app.today
    readonly property int timeCol: 46
    readonly property int headRow: 40
    // An hour is at least 44 px, more when the window is taller than the day: the 24 hours then fill it instead of
    // leaving empty room under midnight (#2036); shorter, they scroll
    readonly property int hourMin: 44
    readonly property real hourH: Math.max(hourMin, (height - headRow - laneH - 1) / 24)
    readonly property int bar: 18           // a row of the all-day lane
    readonly property int gap: 2            // between its stacked bars, so they don't touch (#1481)
    readonly property real colW: (width - timeCol) / Math.max(1, days.length)
    // The all-day lane is as high as its fullest day needs, up to four rows (the rest: "+N")
    readonly property int laneRows: Math.min(4, Math.max(1, ...days.map(d => (app.byDay[d] || []).filter(Dates.spansDays).length)))
    readonly property int laneH: laneRows * bar + 8
    readonly property int scrollTo: 7       // the hour at the top when the week opens
    // A narrow window (#2025): a day's name is its letter once "Mon" and the date's circle no longer fit side by side,
    // and an event too narrow for a word is its colour alone (its title elided to "…" said nothing)
    readonly property bool shortNames: colW < 72
    readonly property int wordMin: 28

    // A day's timed events with their place: [{ e, top, height, col, cols }]. Greedy columns: each event takes the
    // first column free at its start; a cluster of overlapping ones shares the width by its count of columns.
    function layout(day) {
        const items = (app.byDay[day] || []).filter(e => !Dates.spansDays(e))
            .map(e => ({ e: e, from: Dates.minutes(e.start, day), to: Math.max(Dates.minutes(e.end, day), Dates.minutes(e.start, day) + 20) }))
            .sort((a, b) => a.from - b.from || b.to - a.to)
        const out = []
        let cluster = [], ends = [], clusterEnd = -1
        const close = () => { for (const x of cluster) x.cols = ends.length; cluster = []; ends = [] }
        for (const x of items) {
            if (x.from >= clusterEnd) close()
            let col = ends.findIndex(t => t <= x.from)
            if (col < 0) { col = ends.length; ends.push(x.to) } else ends[col] = x.to
            x.col = col
            clusterEnd = Math.max(clusterEnd, x.to)
            cluster.push(x)
            out.push(x)
        }
        close()
        return out.map(x => ({ e: x.e, top: x.from / 60 * root.hourH, height: Math.max(18, (x.to - x.from) / 60 * root.hourH - 2), col: x.col, cols: x.cols }))
    }

    // The days' names and dates
    Repeater {
        model: root.days
        delegate: Item {
            required property string modelData
            required property int index
            readonly property int wd: Dates.parse(modelData).getDay()
            x: root.timeCol + index * root.colW
            width: root.colW; height: root.headRow
            TapHandler { onTapped: root.app.pickDay(parent.modelData) }
            Row {
                anchors.left: parent.left; anchors.leftMargin: root.colW < 56 ? 3 : 8; anchors.verticalCenter: parent.verticalCenter
                spacing: 6
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.colW >= 44
                    text: root.single ? Regional.dayName(wd, false) : Regional.dayName(wd, true).slice(0, root.shortNames ? 1 : 3)
                    color: wd % 6 === 0 ? root.c.faint : root.c.dim   // the weekend
                    font.family: root.c.font; font.pixelSize: 11; font.weight: Font.Medium
                }
                Rectangle {
                    width: 26; height: 22; radius: 11
                    color: modelData === root.today ? root.c.primary : modelData === root.app.day && !root.single ? root.app.dayPicked : "transparent"
                    Text {
                        anchors.centerIn: parent
                        text: Dates.parse(modelData).getDate()
                        color: modelData === root.today ? root.c.solid : root.c.title
                        font.family: root.c.font; font.pixelSize: 13
                        font.weight: modelData === root.today ? Font.Bold : Font.Normal
                    }
                }
            }
        }
    }

    // The all-day lane
    Rectangle { y: root.headRow; width: parent.width; height: 1; color: root.c.line }
    Repeater {
        model: root.days
        delegate: Column {
            id: lane
            required property string modelData
            required property int index
            readonly property var items: (root.app.byDay[modelData] || []).filter(Dates.spansDays)
            x: root.timeCol + index * root.colW + 2
            y: root.headRow + 4
            width: root.colW - 4
            spacing: root.gap
            Repeater {
                model: lane.items.length > root.laneRows ? lane.items.slice(0, root.laneRows - 1) : lane.items
                delegate: Rectangle {
                    id: pill
                    required property var modelData
                    readonly property color ev: modelData.color
                    width: lane.width; height: root.bar - root.gap; radius: 4      // with the gap, a row is still root.bar
                    color: Qt.rgba(ev.r, ev.g, ev.b, pillHover.hovered ? 0.5 : 0.35)
                    HoverHandler { id: pillHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: root.app.openEvent(pill.modelData) }
                    Text {
                        textFormat: Text.PlainText
                        x: 6; width: parent.width - 10; anchors.verticalCenter: parent.verticalCenter
                        elide: Text.ElideRight
                        text: pill.modelData.title
                        color: root.c.text; font.family: root.c.font; font.pixelSize: 11
                    }
                }
            }
            Text {
                visible: lane.items.length > root.laneRows
                x: 6; height: root.bar
                verticalAlignment: Text.AlignVCenter
                text: "+" + (lane.items.length - root.laneRows + 1) + " more"
                color: root.c.faint; font.family: root.c.font; font.pixelSize: 10
            }
        }
    }
    Rectangle { y: root.headRow + root.laneH; width: parent.width; height: 1; color: root.c.divider }

    // The hours
    Flickable {
        id: hours
        anchors.fill: parent
        anchors.topMargin: root.headRow + root.laneH + 1
        clip: true
        contentHeight: 24 * root.hourH
        boundsBehavior: Flickable.StopAtBounds
        // The morning at the top, its label whole, not cut; kept within the day, as a day that fits has nowhere to scroll.
        // The hour wanted at the top is kept apart from contentY, which the window's height clamps: a taller or lower
        // window stretches the hours (hourH), and the same hour stays at the top, not the same pixel. Only a scroll
        // moves it. Back to the morning each time the view comes up, as it was laid out hidden at another size
        property real topHour: root.scrollTo - 10 / root.hourMin
        property bool placing: false
        function place() {
            placing = true
            contentY = Math.max(0, Math.min(24 * root.hourH - height, topHour * root.hourH))
            placing = false
        }
        function toMorning() { topHour = root.scrollTo - 10 / root.hourH; place() }
        onContentYChanged: if (!placing) topHour = contentY / root.hourH
        onHeightChanged: place()
        Component.onCompleted: toMorning()
        Connections {
            target: root
            function onVisibleChanged() { if (root.visible) Qt.callLater(hours.toMorning) }
            function onHourHChanged() { hours.place() }
        }
        TouchScroll { view: hours }

        Repeater {
            model: 24
            delegate: Item {
                required property int index
                y: Math.round(index * root.hourH)       // a stretched hour isn't whole pixels: its line stays sharp
                width: hours.width; height: root.hourH
                Rectangle { x: root.timeCol; width: parent.width - root.timeCol; height: 1; color: root.c.line; visible: index > 0 }
                Text {
                    visible: index > 0
                    width: root.timeCol - 8; y: -7
                    horizontalAlignment: Text.AlignRight
                    // 9:00 or 09:00 as the region writes it, or 9 AM where the clock is 12 h: "9:00 AM" is too wide here
                    text: Regional.h24 ? Regional.time(Dates.pad(index) + ":00") : Regional.format(new Date(2000, 0, 1, index), "h AP")
                    color: root.c.faint; font.family: root.c.font; font.pixelSize: 10
                }
            }
        }
        Repeater {
            model: root.days
            delegate: Item {
                id: column
                required property string modelData
                required property int index
                x: root.timeCol + index * root.colW
                width: root.colW; height: 24 * root.hourH
                Rectangle { width: 1; height: parent.height; color: root.c.line }
                // Each day draws its left line: the last closes the grid on its right too, as the first opens it
                Rectangle { visible: column.index === root.days.length - 1; anchors.right: parent.right; width: 1; height: parent.height; color: root.c.line }
                Rectangle {
                    anchors.fill: parent; anchors.leftMargin: 1; anchors.rightMargin: column.index === root.days.length - 1 ? 1 : 0
                    // The picked day among the week's; the day view's one day is always the picked one
                    color: column.modelData === root.app.day && !root.single ? Qt.rgba(root.c.sel.r, root.c.sel.g, root.c.sel.b, 0.35) : "transparent"
                }
                // A double click in the hours: a new event there, at the half hour it fell in. Not on an event: the
                // block's own TapHandler opens it, and in Qt 6 this one gets the same taps (both grab passively)
                TapHandler {
                    onTapped: root.app.pickDay(column.modelData)
                    onDoubleTapped: point => {
                        const hit = column.childAt(point.position.x, point.position.y)
                        if (hit && hit.isEvent) return
                        const at = Math.floor(point.position.y / (root.hourH / 2))
                        root.app.newEvent(column.modelData, Math.min(23, Math.floor(at / 2)), at % 2 ? 30 : 0)
                    }
                }
                Repeater {
                    model: root.layout(column.modelData)
                    delegate: Rectangle {
                        id: block
                        required property var modelData
                        readonly property bool isEvent: true     // for the column's double click, above
                        readonly property color ev: modelData.e.color
                        readonly property real w: (column.width - 6) / modelData.cols
                        x: 3 + modelData.col * w; y: modelData.top + 1
                        width: w - 2; height: modelData.height
                        radius: 5
                        color: Qt.rgba(ev.r, ev.g, ev.b, blockHover.hovered ? 0.45 : 0.3)
                        clip: true
                        Rectangle { width: 3; height: parent.height; radius: 2; color: block.ev }
                        HoverHandler { id: blockHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: root.app.openEvent(block.modelData.e) }
                        // The title, and under it the time and place; in a block too low for two lines, the day view's
                        // width takes them beside the title instead, as a half hour there is still a wide strip
                        Item {
                            id: words
                            readonly property bool beside: root.single && block.height <= 34
                            visible: block.width >= root.wordMin
                            x: 8; y: 3; width: parent.width - 12
                            Text {
                                id: titleText
                                textFormat: Text.PlainText
                                width: words.beside ? Math.min(implicitWidth, words.width * 0.6) : words.width
                                elide: Text.ElideRight
                                text: block.modelData.e.title
                                color: root.c.title; font.family: root.c.font; font.pixelSize: 11; font.weight: Font.Medium
                            }
                            Text {
                                textFormat: Text.PlainText
                                visible: block.height > 34 || words.beside
                                x: words.beside ? titleText.width + 10 : 0
                                y: words.beside ? 1 : titleText.height
                                width: words.width - x; elide: Text.ElideRight
                                text: Regional.time(block.modelData.e.start.slice(11, 16)) + " – " + Regional.time(block.modelData.e.end.slice(11, 16))
                                    + (block.modelData.e.location ? "  " + block.modelData.e.location.split("\n")[0] : "")
                                color: root.c.dim; font.family: root.c.font; font.pixelSize: 10
                            }
                        }
                    }
                }
            }
        }
        // Now, as a line across today
        Rectangle {
            readonly property int at: root.days.indexOf(root.today)
            visible: at >= 0
            x: root.timeCol + at * root.colW; width: root.colW; height: 2
            y: (root.app.now.getHours() * 60 + root.app.now.getMinutes()) / 60 * root.hourH
            color: root.c.danger
        }
    }
}
