import QtQuick
import qs.kit
import "Dates.js" as Dates

// The view's header: the month's or week's name on the left, the buttons that move about in the middle, and New on the
// right, apart from them as the one that makes something (Jari 2.11.). The middle gives way to a long name.
// In a narrow window (#2025) the words don't fit: the buttons become their glyphs and the name its short form
// ("Nov 2026", "W45 · 2–8 Nov"), rather than the buttons running into each other and Month losing its last letter.
Item {
    id: root
    required property var app           // the window: day, view, page(), pickDay(), newEvent()
    required property QtObject c

    readonly property date day: Dates.parse(app.day)
    readonly property date monday: Dates.monday(day)
    readonly property date sunday: Dates.addDays(monday, 6)
    readonly property string longName: app.view === "month" ? Qt.formatDate(day, "MMMM yyyy")
        : "Week " + Dates.week(monday) + "  ·  " + Qt.formatDate(monday, monday.getMonth() === sunday.getMonth() ? "d" : "d MMM")
          + " – " + Qt.formatDate(sunday, "d MMM yyyy")
    readonly property string shortName: app.view === "month" ? Qt.formatDate(day, "MMM yyyy")
        : "W" + Dates.week(monday) + " · " + Qt.formatDate(monday, monday.getMonth() === sunday.getMonth() ? "d" : "d MMM")
          + "–" + Qt.formatDate(sunday, "d MMM")

    // What the words take, measured in the theme's font so a wider font turns to glyphs sooner. The buttons are the
    // kit's: AppButton is its label + 24 (and a glyph, 13 + 8), AppIconButton 26; 8 between them and 10 before Month
    FontMetrics { id: words; font.family: root.c.font; font.pixelSize: 12 }
    FontMetrics { id: big; font.family: root.c.font; font.pixelSize: 15; font.weight: Font.Medium }
    readonly property real middleWide: 2 * 26 + 3 * 24 + words.advanceWidth("Today") + words.advanceWidth("Month")
        + words.advanceWidth("Week") + 10 + 5 * 8
    readonly property real newWide: 13 + 8 + 24 + words.advanceWidth("New")
    readonly property bool compact: big.advanceWidth(longName) + 24 + middleWide + 16 + newWide > width

    Text {
        id: heading
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(implicitWidth, root.width - middle.width - newButton.width - (root.compact ? 20 : 32))
        elide: Text.ElideRight
        text: root.compact ? root.shortName : root.longName
        color: root.c.title; font.family: root.c.font; font.pixelSize: 15; font.weight: Font.Medium
    }
    Row {
        id: middle
        anchors.verticalCenter: parent.verticalCenter
        x: Math.max((root.width - width) / 2, heading.width + (root.compact ? 10 : 16))
        spacing: root.compact ? 4 : 8       // glyphs need less air than words, and the name gets it
        AppIconButton { c: root.c; glyph: "chevron-left"; tip: root.app.view === "month" ? "Previous month" : "Previous week"; keys: "PgUp"; tipAlign: "left"; onClicked: root.app.page(-1) }
        AppButton { c: root.c; glyph: root.compact ? "calendar-check" : ""; label: root.compact ? "" : "Today"; tip: "Go to today"; keys: "t"; tipAlign: "left"; onClicked: root.app.pickDay(Dates.iso(new Date())) }
        AppIconButton { c: root.c; glyph: "chevron-right"; tip: root.app.view === "month" ? "Next month" : "Next week"; keys: "PgDn"; tipAlign: "left"; onClicked: root.app.page(1) }
        Item { width: root.compact ? 2 : 10; height: 1 }
        AppButton { c: root.c; glyph: root.compact ? "calendar-days" : ""; label: root.compact ? "" : "Month"; on: root.app.view === "month"; tip: "The month"; keys: "m"; tipAlign: "left"; onClicked: root.app.view = "month" }
        AppButton { c: root.c; glyph: root.compact ? "columns-3" : ""; label: root.compact ? "" : "Week"; on: root.app.view === "week"; tip: "The week"; keys: "w"; tipAlign: "left"; onClicked: root.app.view = "week" }
    }
    AppButton {
        id: newButton
        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
        c: root.c; glyph: "plus"; label: root.compact ? "" : "New"; tip: "New event"; keys: "n"
        onClicked: root.app.newEvent(root.app.day)
    }
}
