import QtQuick
import qs

// The view's rows (TrackRow each) and the window's keys: the list keeps the keyboard, also while the sections show, so
// the player's keys work wherever you are. Its own file as the one place the keys are read, apart from the rows' look.
ListView {
    id: list
    required property var win
    readonly property QtObject c: win.look
    readonly property var nav: win.nav
    readonly property var player: win.player
    readonly property var act: win.act

    onActiveFocusChanged: if (!activeFocus) nav.sectionsKeyed = false
    clip: true
    focus: true
    model: win.page.rows
    onModelChanged: currentIndex = Math.max(0, Math.min(nav.cursor, count - 1))
    boundsBehavior: Flickable.StopAtBounds
    highlightMoveDuration: 0
    spacing: 2
    // Inside the list, so rows scroll up to the line
    topMargin: win.listGap
    bottomMargin: 12
    TouchScroll { view: list }
    readonly property var row: win.page.rows[currentIndex]
    // The track numbers' column: as wide as the longest number here (12 tracks: two digits), or the
    // playing track's note
    TextMetrics { id: numberMetrics; font.family: c.font; font.pixelSize: 11; text: String(list.count) }
    readonly property real leadWidth: Math.max(Math.ceil(numberMetrics.advanceWidth), 14)
    Keys.onPressed: e => {
        const k = e.key, sheet = win.sheet
        win.look.moved(e)              // Tab and the arrows show the keys' frame (AppPointer)
        if (e.modifiers & (Qt.ControlModifier | Qt.MetaModifier | Qt.AltModifier)) return
        // The list takes most keys before they reach the sheet: any but ? closes it here
        if (sheet.shown && k !== Qt.Key_Question && sheet.modifierKeys.indexOf(k) < 0) sheet.shown = false
        // The sections on show (one pane): the keys move in them and Enter opens one; the player's keys
        // work as ever, and what acts on a row of the view out of sight does nothing
        if (k === Qt.Key_Tab || k === Qt.Key_Backtab) { nav.tabSections(); e.accepted = true; return }
        if ((nav.sectionsOpen || nav.sectionsKeyed) && nav.sectionKey(k)) { e.accepted = true; return }
        if (k === Qt.Key_Down || k === Qt.Key_J) nav.moveTo(currentIndex + 1)
        else if (k === Qt.Key_Up || k === Qt.Key_K) {
            if (currentIndex > 0) nav.moveTo(currentIndex - 1)
            else if (nav.view.kind === "search") win.searchField.forceActiveFocus()
        }
        else if (k === Qt.Key_Return || k === Qt.Key_Enter) act.activate(row)
        else if (k === Qt.Key_Escape || k === Qt.Key_Backspace) nav.back()
        else if (k === Qt.Key_Space) player.togglePlay()
        else if (k === Qt.Key_Left) player.ctl(["previous"])
        else if (k === Qt.Key_Right) player.next()
        else if (k === Qt.Key_P) act.play(row)
        else if (k === Qt.Key_E) act.enqueue(row)
        else if (k === Qt.Key_A) act.shelve(row)
        else if (k === Qt.Key_L) player.toggleLike()
        else if (k === Qt.Key_D || k === Qt.Key_Delete) act.remove(row)
        else if (k === Qt.Key_F) act.favorite(nav.view.kind === "station" ? act.genreRow(nav.view.genre) : row)
        else if (k === Qt.Key_O) win.outputs.visible = !win.outputs.visible
        else if (k === Qt.Key_N) nav.openPlaying()
        else if (k === Qt.Key_R) act.pick(nav.section === "curated" ? "curated" : nav.section === "shelf" ? "shelf" : "")
        else if (k === Qt.Key_Comma) player.seek((player.position - 10000) / player.duration)
        else if (k === Qt.Key_Period) player.seek((player.position + 10000) / player.duration)
        else if (k === Qt.Key_Question) sheet.shown = !sheet.shown
        else if (k === Qt.Key_Home) nav.moveTo(0)
        else if (k === Qt.Key_End) nav.moveTo(count - 1)
        else return
        e.accepted = true
    }
    delegate: TrackRow {}
    // An empty view: what it is in light text ("Nothing yet"), and what to do below it, quieter (the
    // part of the view's empty text after its first ": ")
    Column {
        id: emptyNote
        readonly property string empty: list.win.page.empty
        readonly property int cut: empty.indexOf(": ")
        visible: list.count === 0
        anchors.centerIn: parent
        width: Math.min(parent.width - 48, 420)
        spacing: 6
        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: emptyNote.cut < 0 ? emptyNote.empty : emptyNote.empty.slice(0, emptyNote.cut)
            color: c.text; font.family: c.font; font.pixelSize: 13
        }
        Text {
            visible: emptyNote.cut >= 0
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: emptyNote.cut < 0 ? "" : emptyNote.empty.slice(emptyNote.cut + 2).replace(/^./, ch => ch.toUpperCase())
            color: c.faint; font.family: c.font; font.pixelSize: 12
        }
    }
}
