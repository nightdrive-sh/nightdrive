import QtQuick
import qs.kit

// Calendar: month view, its weeks from the region's first day (Settings › Region: Monday, Sunday in the US), with ISO
// week numbers. Opens by clicking the date. The names are the kit's Regional, as in the apps.
// ‹ › browse months, clicking the title returns to the current month.
// Under the month, the installed plugins' parts for today (their <Name>Today.qml, TopBar.plugin.today: Calendar's
// events, later Tasks'): one menu for the day rather than a menu each. A part sets `shown` when it has something, so
// without one, or on a day with nothing, the menu is just the month; its `close()` closes the menu.
Column {
    id: m
    width: parent ? parent.width : 300
    spacing: 8

    readonly property date today: new Date()
    property int year: today.getFullYear()
    property int month: today.getMonth()      // 0-11
    signal close()

    readonly property var dayNames: Regional.weekdays.map(wd => Regional.dayName(wd, true).slice(0, 2))
    readonly property int cell: 34
    readonly property int weekCol: 28

    // 42 cells (6 weeks): { d, inMonth, isToday, week }
    readonly property var cells: {
        const first = new Date(year, month, 1)
        const offset = (first.getDay() - Regional.weekStart + 7) % 7
        const out = []
        for (let i = 0; i < 42; i++) {
            const dt = new Date(year, month, 1 - offset + i)
            out.push({
                d: dt.getDate(),
                inMonth: dt.getMonth() === month,
                isToday: dt.getFullYear() === today.getFullYear() && dt.getMonth() === today.getMonth() && dt.getDate() === today.getDate(),
                // A week from Sunday is numbered by its Monday, the ISO week most of its days are in
                week: i % 7 === 0 ? isoWeek(new Date(dt.getFullYear(), dt.getMonth(), dt.getDate() + (dt.getDay() === 0 ? 1 : 0))) : 0
            })
        }
        return out
    }
    function isoWeek(dt) {                      // the week's Thursday determines the week number
        const t = new Date(Date.UTC(dt.getFullYear(), dt.getMonth(), dt.getDate()))
        t.setUTCDate(t.getUTCDate() + 4 - (t.getUTCDay() || 7))
        return Math.ceil(((t - Date.UTC(t.getUTCFullYear(), 0, 1)) / 86400000 + 1) / 7)
    }
    function shift(n) {
        const d = new Date(year, month + n, 1)
        year = d.getFullYear(); month = d.getMonth()
    }
    function reset() { year = today.getFullYear(); month = today.getMonth() }

    // Title and month arrows
    Item {
        width: parent.width
        height: 30
        Text {
            id: prev
            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
            width: 30; horizontalAlignment: Text.AlignHCenter
            text: Icons.g("chevron-left")
            color: prevArea.containsMouse ? Theme.accent : Theme.text
            font { family: Icons.family; pixelSize: 18 }
            MouseArea { cursorShape: Qt.PointingHandCursor; id: prevArea; anchors { fill: parent; margins: -4 } hoverEnabled: true; onClicked: m.shift(-1) }
        }
        Text {
            anchors.centerIn: parent
            text: Regional.format(new Date(m.year, m.month, 1), "month")
            color: titleArea.containsMouse ? Theme.accent : Theme.text
            font { family: Theme.font; pixelSize: 14; bold: true }
            MouseArea { cursorShape: Qt.PointingHandCursor; id: titleArea; anchors { fill: parent; margins: -4 } hoverEnabled: true; onClicked: m.reset() }
        }
        Text {
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            width: 30; horizontalAlignment: Text.AlignHCenter
            text: Icons.g("chevron-right")
            color: nextArea.containsMouse ? Theme.accent : Theme.text
            font { family: Icons.family; pixelSize: 18 }
            MouseArea { cursorShape: Qt.PointingHandCursor; id: nextArea; anchors { fill: parent; margins: -4 } hoverEnabled: true; onClicked: m.shift(1) }
        }
    }

    // Weekdays
    Row {
        x: (m.width - (m.weekCol + 7 * m.cell)) / 2
        Item { width: m.weekCol; height: 22 }
        Repeater {
            model: m.dayNames
            delegate: Text {
                required property string modelData
                width: m.cell; height: 22
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                text: modelData
                color: Theme.dim
                font { family: Theme.font; pixelSize: 11 }
            }
        }
    }

    // Days: week number + 7 days
    Grid {
        x: (m.width - (m.weekCol + 7 * m.cell)) / 2
        columns: 8
        Repeater {
            model: 48
            delegate: Item {
                required property int index
                readonly property bool isWeek: index % 8 === 0
                readonly property var c: isWeek ? null : m.cells[Math.floor(index / 8) * 7 + (index % 8) - 1]
                width: isWeek ? m.weekCol : m.cell
                height: m.cell

                Text {                          // week number
                    visible: parent.isWeek
                    anchors.centerIn: parent
                    text: parent.isWeek ? m.cells[Math.floor(index / 8) * 7].week : ""
                    color: Theme.dim
                    font { family: Theme.font; pixelSize: 10 }
                }
                Rectangle {                     // day; today highlighted
                    visible: !parent.isWeek
                    anchors.centerIn: parent
                    width: 30; height: 30; radius: 8
                    color: parent.c && parent.c.isToday ? Theme.sel : "transparent"
                    border.width: parent.c && parent.c.isToday ? 1 : 0
                    border.color: Theme.primary
                    Text {
                        anchors.centerIn: parent
                        text: parent.parent.c ? parent.parent.c.d : ""
                        color: !parent.parent.c ? Theme.text
                             : parent.parent.c.isToday ? Theme.accent
                             : parent.parent.c.inMonth ? Theme.text : Theme.dim
                        font { family: Theme.font; pixelSize: 13; bold: parent.parent.c ? parent.parent.c.isToday : false }
                    }
                }
            }
        }
    }

    Repeater {
        model: TopBar.plugin.today
        delegate: Loader {
            id: part
            required property string modelData
            width: m.width
            visible: item ? item.shown === true : false
            source: "file://" + modelData
            Connections { target: part.item; ignoreUnknownSignals: true; function onClose() { m.close() } }
        }
    }
}
