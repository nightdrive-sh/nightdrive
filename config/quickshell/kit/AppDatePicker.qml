import QtQuick
import qs
import "Dates.js" as Dates

// A day in a field, the region's way (Settings › Region: 5.11.2026, 11/5/2026): typed, or picked from a month grid
// (AppMonthGrid) that opens on a click into the field, on its calendar glyph or on ↓. While the grid is open the field
// keeps the keys: ← → a day, ↑ ↓ a week, PgUp PgDn a month, ⏎ picks, Esc closes it (a second Esc is the panel's), and
// typing goes on, the grid following a day typed whole. Everything else is AppField's: label, hint, accepted, escaped.
//
// The grid is drawn over the whole window, not inside the field's panel, so a panel that scrolls or clips doesn't cut it:
// below the field when there is room, else above it, else where it fits; never past the window's edges. A click outside
// it closes it.
//
// day is the field read the region's way ("YYYY-MM-DD", "" when it isn't a day); a day without its year (5.11.) is in
// base's year. set(day) writes one; picked(day) comes out when the grid picks, so the app can do what it does when the
// field is left (Calendar's end follows its start). Part of the apps' kit (README.md).
AppField {
    id: root
    property string base: ""                    // "YYYY-MM-DD" whose year a day typed without one takes; "" this year
    readonly property string day: Regional.parse(text, base)
    property bool isOpen: false
    property string cursor: ""
    signal picked(string day)

    endRoom: 18
    keyFilter: e => root.key(e)

    function set(d) { text = d ? Regional.format(d, "short") : "" }
    function open() {
        cursor = day || base || Regional.iso(new Date())
        place()
        isOpen = true
    }
    function close() { isOpen = false }
    function pick(d) {
        set(d)
        close()
        input.cursorPosition = text.length
        picked(d)
    }
    // n days on, or n months (the day kept, or the month's last: 31 Jan → 28 Feb)
    function move(n, months) {
        const d = Dates.toDate(cursor) || new Date()
        if (months) {
            const last = new Date(d.getFullYear(), d.getMonth() + n + 1, 0).getDate()
            cursor = Regional.iso(new Date(d.getFullYear(), d.getMonth() + n, Math.min(d.getDate(), last)))
        } else cursor = Regional.iso(new Date(d.getFullYear(), d.getMonth(), d.getDate() + n))
    }
    function key(e) {
        if (e.modifiers & (Qt.ControlModifier | Qt.MetaModifier | Qt.AltModifier)) return   // Ctrl+⏎ saves the panel
        if (!isOpen) {
            if (e.key === Qt.Key_Down) { open(); e.accepted = true }
            return
        }
        switch (e.key) {
        case Qt.Key_Left: move(-1); break
        case Qt.Key_Right: move(1); break
        case Qt.Key_Up: move(-7); break
        case Qt.Key_Down: move(7); break
        case Qt.Key_PageUp: move(-1, true); break
        case Qt.Key_PageDown: move(1, true); break
        case Qt.Key_Return: case Qt.Key_Enter: pick(cursor); break
        case Qt.Key_Escape: close(); break
        case Qt.Key_Tab: case Qt.Key_Backtab: close(); return       // and on to the next field
        default: return                                            // typing: the field's
        }
        e.accepted = true
    }

    // Where the grid goes, in the window's coordinates: under the frame, else over it. In a low window, where it fits on
    // neither side, its days get lower (down to 22 px) to fit the larger side, and only then does it cover the field
    readonly property Item overlay: Window.window ? Window.window.contentItem : null
    function place() {
        if (!overlay) return
        const m = 6, gap = 4, full = 32, least = 22
        const at = frame.mapToItem(overlay, 0, 0)
        const below = at.y + frame.height + gap
        const roomBelow = overlay.height - m - below, roomAbove = at.y - gap - m
        const fits = room => Math.max(least, Math.min(full, Math.floor((room - grid.chrome) / 6)))
        const under = roomBelow >= grid.heightFor(full) || roomBelow >= roomAbove
        grid.cell = fits(under ? roomBelow : roomAbove)
        const h = grid.heightFor(grid.cell)
        pop.x = Math.max(m, Math.min(at.x, overlay.width - grid.implicitWidth - m))
        pop.y = under && h <= roomBelow ? below
              : !under && h <= roomAbove ? at.y - gap - h
              : Math.max(m, overlay.height - h - m)
    }
    Connections {
        target: root.overlay
        function onWidthChanged() { if (root.isOpen) root.place() }
        function onHeightChanged() { if (root.isOpen) root.place() }
    }
    // The keys gone elsewhere (Tab, a click into another field) close it
    Connections {
        target: root.input
        function onActiveFocusChanged() { if (!root.input.activeFocus) root.close() }
        function onTextChanged() {
            if (root.isOpen && root.day) root.cursor = root.day
        }
    }
    // A click into the field opens it; the field still takes the click (the text cursor, a selection)
    TapHandler {
        parent: root.input
        onTapped: if (!root.isOpen) root.open()
    }
    // The calendar glyph in the frame's right end, for the pointer
    Text {
        parent: root.frame
        anchors.right: parent.right; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter
        text: Icons.g("calendar"); font.family: Icons.family; font.pixelSize: 13
        color: glyphHover.hovered || root.isOpen ? root.c.text : root.c.dim
        HoverHandler { id: glyphHover; cursorShape: Qt.PointingHandCursor }
        TapHandler {
            onTapped: {
                root.input.forceActiveFocus()
                if (root.isOpen) root.close(); else root.open()
            }
        }
    }

    // Over the window: a catch-all under the grid, so a click anywhere else closes it and does nothing more
    Item {
        id: layer
        parent: root.overlay
        visible: root.isOpen
        anchors.fill: parent
        z: 1000
        MouseArea {
            anchors.fill: parent
            onPressed: root.close()
            onWheel: wheel => wheel.accepted = true
        }
        Item {
            id: pop
            width: grid.implicitWidth; height: grid.implicitHeight
            AppMonthGrid {
                id: grid
                anchors.fill: parent
                c: root.c
                cursor: root.cursor
                picked: root.day
                onClicked: d => root.pick(d)
                onMonthMoved: n => root.move(n, true)
            }
        }
    }
}
