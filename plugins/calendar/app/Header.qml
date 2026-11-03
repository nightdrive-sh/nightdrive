import QtQuick
import qs.kit
import "Dates.js" as Dates

// The view's header. In the middle the month's or week's name between the arrows that change it: < November 2026 >,
// and after them Today while another day is picked (its room is kept, so the arrows don't move when it comes). On the
// left the switch between Week and Month (the kit's AppSegments, its fill sliding to the one shown), on the right New,
// apart as the one that makes something (Jari 2.11.). A long name gives way to the buttons.
// In a narrow window (#2025) the words don't fit: the buttons become their glyphs and the name its short form
// ("Nov 2026", "W45 · 2–8 Nov"), rather than the buttons running into each other and Month losing its last letter.
Item {
    id: root
    required property var app           // the window: day, today, view, page(), pickDay(), newEvent()
    required property QtObject c
    // Below about 500 px the views are a list of the days either way (#2025): the switch would change little there
    property bool switchable: true

    readonly property date day: Dates.parse(app.day)
    // The week shown, from its first day: Monday, or Sunday in the US (Settings › Region)
    readonly property date first: Dates.weekFirst(day, Regional.weekStart)
    readonly property date last: Dates.addDays(first, 6)
    readonly property string longName: app.view === "month" ? Regional.format(day, "month")
        : "Week " + Dates.weekNumber(first) + "  ·  " + Regional.range(first, last)
    readonly property string shortName: app.view === "month" ? Regional.format(day, "MMM yyyy")
        : "W" + Dates.weekNumber(first) + " · " + Regional.range(first, last, true)
    readonly property string unit: app.view === "month" ? "month" : "week"
    readonly property var views: ["week", "month"]
    readonly property int gap: compact ? 10 : 16        // between the groups

    // What the words take, measured in the theme's font so a wider font turns to glyphs sooner. The buttons are the
    // kit's: AppButton is its label + 24 (and a glyph, 13 + 8), AppIconButton 26, an AppSegments part its label + 24
    // and 2 for the frame. The middle is centred, so it needs twice the wider side's room around it
    FontMetrics { id: words; font.family: root.c.font; font.pixelSize: 12 }
    FontMetrics { id: big; font.family: root.c.font; font.pixelSize: 15; font.weight: Font.Medium }
    readonly property real leftWide: switchable ? 2 * 24 + words.advanceWidth("Week") + words.advanceWidth("Month") + 2 : 0
    readonly property real todayWide: 24 + words.advanceWidth("Today") + 8
    readonly property real newWide: 13 + 8 + 24 + words.advanceWidth("New")
    // The widest name the view can have, so the arrows stay put as the months go by: every month's name this year,
    // and for a week every pair of months' with two-digit days, written the region's way (Regional.range)
    function widest(short) {
        let w = 0
        for (let i = 0; i < 12; i++) {
            const y = day.getFullYear()
            if (app.view === "month")
                w = Math.max(w, big.advanceWidth(Regional.format(new Date(y, i, 1), short ? "MMM yyyy" : "month")))
            else   // a week over two months, two-digit days: the widest the name gets
                w = Math.max(w, big.advanceWidth((short ? "W00 · " : "Week 00  ·  ")
                                                 + Regional.range(new Date(y, i, 28), new Date(y, i + 1, 3), short)))
        }
        return w
    }
    readonly property bool compact: 2 * (Math.max(leftWide, todayWide + newWide) + 16) + 2 * (26 + 4) + 12 + widest(false) > width

    Row {
        id: left
        anchors.verticalCenter: parent.verticalCenter
        spacing: root.compact ? 4 : 8       // glyphs need less air than words
        AppSegments {
            visible: root.switchable
            c: root.c; compact: root.compact
            options: [{ label: "Week", glyph: "columns-3", tip: "Week view", keys: "w" },
                      { label: "Month", glyph: "calendar-days", tip: "Month view", keys: "m" }]
            current: root.views.indexOf(root.app.view)
            onPicked: i => root.app.view = root.views[i]
        }
    }

    // The name between its arrows, in the middle of the header; pushed aside by the left group when the room is short,
    // and the name elided before Today's room and New
    Row {
        id: middle
        anchors.verticalCenter: parent.verticalCenter
        readonly property real leftEdge: left.width > 0 ? left.width + root.gap : 0
        readonly property real rightEdge: newButton.x - root.gap - today.width - 8
        readonly property real room: rightEdge - leftEdge
        x: Math.max(leftEdge, Math.min((root.width - width) / 2, rightEdge - width))
        spacing: 4
        AppIconButton { c: root.c; glyph: "chevron-left"; tip: "Previous " + root.unit; keys: "PgUp"; tipAlign: "left"; onClicked: root.app.page(-1) }
        Text {
            id: heading
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(0, Math.min(root.widest(root.compact) + leftPadding + rightPadding, middle.room - 2 * (26 + middle.spacing)))
            leftPadding: 6; rightPadding: 6
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            text: root.compact ? root.shortName : root.longName
            color: root.c.title; font.family: root.c.font; font.pixelSize: 15; font.weight: Font.Medium
        }
        AppIconButton { c: root.c; glyph: "chevron-right"; tip: "Next " + root.unit; keys: "PgDn"; tipAlign: "left"; onClicked: root.app.page(1) }
    }

    AppButton {
        id: today
        anchors.left: middle.right; anchors.leftMargin: 8; anchors.verticalCenter: parent.verticalCenter
        visible: root.app.day !== root.app.today
        c: root.c; glyph: root.compact ? "calendar-check" : ""; label: root.compact ? "" : "Today"; tip: "Go to today"; keys: "t"; tipAlign: "left"
        onClicked: root.app.pickDay(root.app.today)
    }
    AppButton {
        id: newButton
        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
        c: root.c; glyph: "plus"; label: root.compact ? "" : "New"; tip: "New event"; keys: "n"
        onClicked: root.app.newEvent(root.app.day)
    }
}
